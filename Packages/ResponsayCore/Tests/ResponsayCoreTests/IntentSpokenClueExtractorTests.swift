import Foundation
import Testing
@testable import ResponsayCore

// #562 — the deterministic spoken-character-clue extractor (口述释字). A clue phrase is
// self-evidencing: 「X的Y」 counts ONLY when Y ∈ X (如何的何 — 何 is in 如何), which is what
// separates orthographic clues from ordinary possessive 的 phrases without any hardcoded
// name list. Extraction is a whitelist candidate SOURCE — it never touches rendering itself.

private func extract(_ transcript: String) -> [IntentSpokenClueExtraction] {
    IntentSpokenClueExtractor.extract(
        transcript: transcript,
        units: IntentSourceSegmenter.segment(transcript))
}

@Test func clueExtraction_assemblesNameFromSelfEvidencingClues() {
    // 顿号-joined clues in one unit; ASR transcribed the name correctly → identity target.
    let extractions = extract("何正杰，如何的何、纯正的正、杰出的杰")

    #expect(extractions.count == 1)
    let extraction = try! #require(extractions.first)
    #expect(extraction.value == "何正杰")
    #expect(extraction.clueSourceIDs == ["source-0001"])
    #expect(extraction.target?.exactQuote == "何正杰")
    #expect(extraction.target?.sourceID == "source-0000")
}

@Test func clueExtraction_findsMisheardTargetByLengthAndOverlap() {
    // ASR heard 贺正杰; the clues prove 何正杰. Same length + position-wise overlap → target.
    let extractions = extract("贺正杰，如何的何、纯正的正、杰出的杰")

    let extraction = try! #require(extractions.first)
    #expect(extraction.value == "何正杰")
    #expect(extraction.target?.exactQuote == "贺正杰")
}

@Test func clueExtraction_mergesConsecutiveCommaSeparatedClueUnits() {
    let extractions = extract("王伟明，伟大的伟，明天的明")

    let extraction = try! #require(extractions.first)
    #expect(extraction.value == "伟明")
    #expect(extraction.clueSourceIDs == ["source-0001", "source-0002"])
    // Only the position-wise-overlapping span qualifies (伟明, not 王伟).
    #expect(extraction.target?.exactQuote == "伟明")
}

@Test func clueExtraction_possessive的PhrasesAreNotClues() {
    // Y ∉ X → ordinary speech, zero extractions (的 is everywhere in Chinese).
    #expect(extract("我的书很好看，美丽的花开了").isEmpty)
    #expect(extract("如何的问题都可以问我").isEmpty)   // 的 followed by multi-char word
    #expect(extract("这个方案的核心是安全").isEmpty)
}

@Test func clueExtraction_clueInsideOrdinarySentenceIsNotAClueUnit() {
    // A unit with substantial non-clue content is not a clue unit — no extraction.
    #expect(extract("他问如何的何要不要写全名").isEmpty)
}

@Test func clueExtraction_supportsTwoIndependentNames() {
    let extractions = extract("联系人是何正杰，如何的何、杰出的杰，另一位是李伟，伟大的伟")

    #expect(extractions.count == 2)
    #expect(extractions[0].value == "何杰")
    #expect(extractions[1].value == "伟")
}

// MARK: - Homophone derivation (#570)

@Test func clueExtraction_derivesHomophoneCharFromCarrier() {
    // #570 golden case (real session, 2026-07-12): ASR renders the isolated clued character
    // with the same homophone it misheard in the name — the carrier word must prove 镇.
    let extractions = extract("给这个我的学生何振杰写一封邮件，何是如何的何，振是城镇的振，杰是杰出的杰。")

    let extraction = try! #require(extractions.first)
    #expect(extraction.value == "何镇杰")
    #expect(extraction.target?.exactQuote == "何振杰")
    #expect(extraction.clueSourceIDs == ["source-0001", "source-0002", "source-0003"])
}

@Test func clueCharacters_announcedPhrasingResolvesAgainstTrueCarrier() {
    // All four ASR spellings of 「zhèn 是城镇的 zhèn」 must prove 镇 — the misheard char can
    // never prove itself via its own announcement.
    #expect(IntentSpokenClueExtractor.resolvedClueCharacter(inCarrier: "振是城镇", clued: "振") == "镇")
    #expect(IntentSpokenClueExtractor.resolvedClueCharacter(inCarrier: "镇是城镇", clued: "振") == "镇")
    #expect(IntentSpokenClueExtractor.resolvedClueCharacter(inCarrier: "振是城镇", clued: "镇") == "镇")
    #expect(IntentSpokenClueExtractor.resolvedClueCharacter(inCarrier: "镇是城镇", clued: "镇") == "镇")
}

@Test func clueExtraction_findsFullyMisheardHomophoneTarget() {
    // #571 real-Mac case (1.4.15 HITL): ASR miswrote EVERY name character (何振杰→和郑姐),
    // zero verbatim overlap with the assembled 何镇结 — but 和~何 and 姐~结 are the same
    // syllable, so the position-wise homophone overlap finds the span (郑 zheng ≠ 镇 zhen
    // doesn't matter; two of three positions carry it).
    let extractions = extract("给我的学生和郑姐写一封邮件，和是如何的和，镇呢是城镇的镇，结是结束的结。")

    let extraction = try! #require(extractions.first)
    #expect(extraction.value == "何镇结")
    #expect(extraction.target?.exactQuote == "和郑姐")
}

@Test func clueCharacters_ambiguousHomophonesAbstain() {
    // 制/止 are both zhi (tone-insensitive) — two candidate carriers → not a clue, abstain.
    #expect(IntentSpokenClueExtractor.clueCharacters(in: "智是制止的智") == nil)
}

@Test func clueCharacters_possessivePhrasesNeverDerive() {
    // 门/们 and 他/塔 rhyme, but derivation is gated on the announced 「Y是X的Y」 signature —
    // ordinary possessives and 这是/就是 clauses stay ordinary speech.
    #expect(IntentSpokenClueExtractor.clueCharacters(in: "他们的门") == nil)
    #expect(IntentSpokenClueExtractor.clueCharacters(in: "这是他们的门") == nil)
    #expect(IntentSpokenClueExtractor.clueCharacters(in: "他的塔") == nil)
}

@Test func clueCharacters_legacyPhrasingsUnchanged() {
    // Long announcement before 是: verbatim containment in the fused capture still resolves.
    #expect(IntentSpokenClueExtractor.clueCharacters(in: "名字是城镇的镇") == ["镇"])
    // 是-final carrier: the suffix after 是 is empty → full capture resolves verbatim.
    #expect(IntentSpokenClueExtractor.clueCharacters(in: "实事求是的是") == ["是"])
}

@Test func groundingRole_isNeverRenderedAndBarredFromSupersessions() throws {
    let transcript = "何正杰，如何的何、纯正的正、杰出的杰，请转告他"
    let units = IntentSourceSegmenter.segment(transcript)
    let candidates = IntentEntityCandidateTable.build(
        transcript: transcript, units: units, grounding: .empty)

    let verified = try IntentPlanVerifier.verify(
        IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(units[0]), role: .content),
                .init(source: .init(units[1]), role: .grounding),
                .init(source: .init(units[2]), role: .content)
            ],
            supersessions: [],
            entities: ["entity-0000"]),
        sourceUnits: units,
        transcript: transcript,
        entityCandidates: candidates)
    #expect(verified.renderedSourceIDs == ["source-0000", "source-0002"])
    #expect(verified.selectedCandidates.map(\.value) == ["何正杰"])

    // #575: a render plan that marks grounding units but resolves nothing no longer dies at
    // the verifier (weak models slip here stochastically) — with a non-empty table it verifies
    // and the arbiter downgrades to a candidate-confirm review. The clue still can't silently
    // vanish: the outcome is a review, never an insert.
    let unresolved = IntentPlan(
        version: 1,
        decision: .render,
        units: [
            .init(source: .init(units[0]), role: .content),
            .init(source: .init(units[1]), role: .grounding),
            .init(source: .init(units[2]), role: .content)
        ],
        supersessions: [])
    let lazyVerified = try IntentPlanVerifier.verify(
        unresolved, sourceUnits: units, transcript: transcript, entityCandidates: candidates)
    #expect(lazyVerified.selectedCandidates.isEmpty)
    let review = IntentEntityConflictArbiter.unresolvedGroundingReview(
        verified: lazyVerified, transcript: transcript)
    guard case let .needsReview(reason, proposal) = review else {
        Issue.record("expected candidate-confirm review, got \(String(describing: review))")
        return
    }
    #expect(reason == .unexplainedGroundingCue)
    #expect(proposal?.candidates.map(\.value) == ["何正杰"])

    // With an EMPTY table the same lazy plan stays unsatisfiable → invalid (model must abstain).
    #expect(throws: IntentPlanVerifier.VerificationError.self) {
        try IntentPlanVerifier.verify(
            unresolved, sourceUnits: units, transcript: transcript, entityCandidates: [])
    }

    // grounding may not be winner/loser/cue.
    let invalid = IntentPlan(
        version: 1,
        decision: .render,
        units: [
            .init(source: .init(units[0]), role: .content),
            .init(source: .init(units[1]), role: .grounding),
            .init(source: .init(units[2]), role: .content)
        ],
        supersessions: [
            .init(winner: .init(units[2]), loser: .init(units[1]), cue: .init(units[1]))
        ])
    #expect(throws: IntentPlanVerifier.VerificationError.self) {
        try IntentPlanVerifier.verify(invalid, sourceUnits: units, transcript: transcript)
    }

    // noIntentControl may not hide grounding units.
    let hidden = IntentPlan(
        version: 1,
        decision: .noIntentControl,
        units: [
            .init(source: .init(units[0]), role: .content),
            .init(source: .init(units[1]), role: .grounding),
            .init(source: .init(units[2]), role: .content)
        ],
        supersessions: [])
    #expect(throws: IntentPlanVerifier.VerificationError.self) {
        try IntentPlanVerifier.verify(hidden, sourceUnits: units, transcript: transcript)
    }
}
