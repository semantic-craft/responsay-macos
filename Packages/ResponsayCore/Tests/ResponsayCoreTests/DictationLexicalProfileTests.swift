import Foundation
import Testing
@testable import ResponsayCore

struct DictationLexicalProfileTests {
    @Test func builderKeepsTopTermsAndLearnedAliasesWithoutRawText() throws {
        let store = HotwordStore(userTermEntries: [
            HotwordTerm(text: "Claude Code", source: .manual),
            HotwordTerm(text: "Zotero", source: .auto, learnedSource: .localRules, learnedAt: Date(timeIntervalSince1970: 10), confidence: 0.9),
        ], seeds: [:])
        let records = [
            HotwordLearningRecord(
                term: "Claude Code",
                source: .localRules,
                status: .added,
                reason: "用户纠正",
                learnedAt: Date(timeIntervalSince1970: 20),
                sourceTerm: "Cloud Code",
                appName: "Notes",
                windowTitle: "论文草稿",
                confidence: 0.92),
        ]

        let profile = DictationLexicalProfileBuilder().build(store: store, records: records, now: Date(timeIntervalSince1970: 30))

        #expect(profile.terms.map(\.text).contains("Claude Code"))
        #expect(profile.terms.map(\.text).contains("Zotero"))
        #expect(profile.aliases == [.init(sourceTerm: "Cloud Code", term: "Claude Code", source: "localRules", lastUsedAt: Date(timeIntervalSince1970: 20))])
        #expect(profile.sceneSummary["Notes"] == 1)
        #expect(!profile.markdownMirror.contains("论文草稿"))
        #expect(profile.profileHash.count == 64)
    }

    @Test func privacyGateRejectsSensitiveInputs() {
        let gate = LexicalProfilePrivacyGate()

        #expect(gate.rejectionReason(text: "https://example.com") == .url)
        #expect(gate.rejectionReason(text: "x@example.com") == .email)
        #expect(gate.rejectionReason(text: "/" + "Users/example/.env") == .filePath)
        #expect(gate.rejectionReason(text: "git push origin main") == .command)
        #expect(gate.rejectionReason(text: "OPENAI_API_KEY=sk-" + "not-a-real-key") == .secretLike)
        #expect(gate.rejectionReason(text: "let token = foo()") == .codeLike)
        #expect(gate.rejectionReason(text: "Claude Code", appName: "Xcode") == .protectedApp)
        #expect(gate.rejectionReason(text: "Claude Code", appName: "Notes") == nil)
    }

    @Test func profileHashIsStableAndChangesWithProfileContent() {
        let builder = DictationLexicalProfileBuilder()
        let now = Date(timeIntervalSince1970: 10)
        let first = builder.build(
            store: HotwordStore(userTerms: ["Claude Code"], seeds: [:]),
            records: [],
            now: now)
        let second = builder.build(
            store: HotwordStore(userTerms: ["Claude Code"], seeds: [:]),
            records: [],
            now: now)
        let changed = builder.build(
            store: HotwordStore(userTerms: ["Zotero"], seeds: [:]),
            records: [],
            now: now)

        #expect(first.profileHash == second.profileHash)
        #expect(first.profileHash != changed.profileHash)
    }

    @Test func profileMergeFeedsBiasingRoutes() {
        let sets = HotwordBiasingSets(
            weakPrompt: [],
            hardMatchUser: [],
            hardMatchSeed: [],
            learnedAliases: [:])
        let profile = DictationLexicalProfile(
            schemaVersion: DictationLexicalProfile.schemaVersion,
            refreshedAt: Date(timeIntervalSince1970: 1),
            terms: [
                .init(text: "Claude Code", source: "manual", score: 100, lastUsedAt: nil),
                .init(text: "Trusted Auto", source: "auto", score: 89, lastUsedAt: nil),
                .init(text: "Low Auto", source: "auto", score: 84, lastUsedAt: nil),
            ],
            aliases: [.init(sourceTerm: "Cloud Code", term: "Claude Code", source: "localRules", lastUsedAt: nil)],
            recentAcceptedCorrections: [],
            sourceSummary: [:],
            sceneSummary: [:],
            privacyRejectionCounts: [:],
            profileHash: "hash")

        let merged = sets.merging(profile: profile)

        #expect(merged.weakPrompt == ["Claude Code", "Trusted Auto", "Low Auto"])
        #expect(merged.hardMatchUser == ["Claude Code", "Trusted Auto", "Low Auto"])
        #expect(merged.learnedAliases == ["Cloud Code": "Claude Code"])
    }
}
