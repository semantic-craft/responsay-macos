import Testing
import Foundation
@testable import ResponsayCore

/// 165 — source-verification target schema (aligned to the built anchor).
/// Verification: schema decode; status transitions; `[待核]` rendering.
struct VerificationTargetTests {
    @Test func decodes_minimalTarget_defaultsToPending() throws {
        let json = #"{"id":"t1","label":"《民法典》第577条","kind":"statute"}"#.data(using: .utf8)!
        let target = try JSONDecoder().decode(VerificationTarget.self, from: json)
        #expect(target.kind == .statute)
        #expect(target.status == .pending)
        #expect(target.suggestedQueries.isEmpty)
    }

    @Test func decodes_allKinds() throws {
        for raw in ["statute", "case", "article", "date", "monetaryRule", "doctrinalClaim"] {
            let json = #"{"id":"x","label":"L","kind":"\#(raw)"}"#.data(using: .utf8)!
            let target = try JSONDecoder().decode(VerificationTarget.self, from: json)
            #expect(VerificationTargetKind.allCases.contains(target.kind))
        }
    }

    @Test func rendersPendingTag() {
        let target = VerificationTarget(id: "t", label: "（2023）京01民终1234号", kind: .caseLaw)
        #expect(target.displayLabel == "（2023）京01民终1234号 [待核]")
    }

    @Test func statusTransitions_pendingToVerifiedToRejected() {
        let pending = VerificationTarget(id: "t", label: "GB/T 39335", kind: .article)
        #expect(pending.status == .pending)
        let verified = pending.markedVerified()
        #expect(verified.status == .verified)
        #expect(verified.displayLabel.hasSuffix("[已核]"))
        let rejected = verified.markedRejected()
        #expect(rejected.status == .rejected)
        #expect(rejected.displayLabel.hasSuffix("[已驳]"))
    }

    @Test func outcomeMapsFromBuiltStatus() {
        #expect(VerificationOutcome(.pending) == .pending)
        #expect(VerificationOutcome(.verifiedLaw) == .verified)
        #expect(VerificationOutcome(.verifiedCase) == .verified)
        #expect(VerificationOutcome(.userConfirmed) == .verified)
        #expect(VerificationOutcome(.rejected) == .rejected)
    }

    @Test func bridgesToCanonicalAnchor_withoutFork() {
        let target = VerificationTarget(
            id: "t", label: "《民法典》第577条", kind: .statute,
            status: .pending, suggestedQueries: ["民法典 第577条 全文"]
        )
        let anchor = target.toAnchor()
        #expect(anchor.kind == .law)                 // statute → law
        #expect(anchor.status == .pending)
        #expect(anchor.query == "民法典 第577条 全文") // first suggested query seeds the launcher
        #expect(anchor.id == "t")
    }

    @Test func verifiedCase_lowersToVerifiedCaseStatus() {
        let target = VerificationTarget(id: "c", label: "（2023）...号", kind: .caseLaw, status: .verified)
        #expect(target.toAnchor().status == .verifiedCase)
    }
}
