import Foundation
import Testing
@testable import ResponsayCore

// #561 — the sideNote role: a span that may inform the plan but must NEVER render. These tests
// pin the verifier/renderer contract at the unit level: side notes are excluded from the
// rendered source IDs, cannot take part in any supersession, and cannot hide inside a
// noIntentControl plan (which promises "all content, nothing withheld").

private func plan(
    _ decision: IntentPlanDecision,
    units: [(IntentSourceUnit, IntentSourceRole)],
    supersessions: [IntentSupersession] = []
) -> IntentPlan {
    IntentPlan(
        version: 1,
        decision: decision,
        units: units.map { .init(source: .init($0.0), role: $0.1) },
        supersessions: supersessions)
}

@Test func sideNoteUnit_isNeverRendered_zeroLeakIntoDraft() throws {
    let transcript = "会议改到周四，这句是给你的备注，请转告大家"
    let units = IntentSourceSegmenter.segment(transcript)

    let verified = try IntentPlanVerifier.verify(
        plan(.render, units: [(units[0], .content), (units[1], .sideNote), (units[2], .content)]),
        sourceUnits: units,
        transcript: transcript)
    let draft = IntentSourceRenderer.render(verified)

    #expect(verified.renderedSourceIDs == ["source-0000", "source-0002"])
    #expect(draft.text == "会议改到周四，请转告大家")
    #expect(!draft.text.contains("备注"))
}

@Test func sideNote_combinedWithCorrection_excludesNoteCueAndLoser() throws {
    let transcript = "周三交稿，不对，周五交稿，这句别写出来"
    let units = IntentSourceSegmenter.segment(transcript)

    let verified = try IntentPlanVerifier.verify(
        plan(
            .render,
            units: [
                (units[0], .content), (units[1], .correction),
                (units[2], .content), (units[3], .sideNote)
            ],
            supersessions: [
                .init(winner: .init(units[2]), loser: .init(units[0]), cue: .init(units[1]))
            ]),
        sourceUnits: units,
        transcript: transcript)
    let draft = IntentSourceRenderer.render(verified)

    #expect(draft.sourceIDs == ["source-0002"])
    #expect(draft.text == "周五交稿，")
}

@Test func sideNote_mayNotParticipateInSupersessions() {
    let transcript = "A，note，B"
    let units = IntentSourceSegmenter.segment(transcript)
    let roles: [[IntentSourceRole]] = [
        [.sideNote, .correction, .content],   // side note as loser
        [.content, .sideNote, .content],      // side note as cue
        [.content, .correction, .sideNote]    // side note as winner
    ]

    for assignment in roles {
        let invalid = plan(
            .render,
            units: zip(units, assignment).map { ($0, $1) },
            supersessions: [
                .init(winner: .init(units[2]), loser: .init(units[0]), cue: .init(units[1]))
            ])
        #expect(throws: IntentPlanVerifier.VerificationError.self) {
            try IntentPlanVerifier.verify(invalid, sourceUnits: units, transcript: transcript)
        }
    }
}

@Test func noIntentControlPlan_mayNotContainSideNote() {
    let transcript = "A，B"
    let units = IntentSourceSegmenter.segment(transcript)

    let invalid = plan(.noIntentControl, units: [(units[0], .content), (units[1], .sideNote)])
    #expect(throws: IntentPlanVerifier.VerificationError.self) {
        try IntentPlanVerifier.verify(invalid, sourceUnits: units, transcript: transcript)
    }
}

@Test func renderPlan_withOnlySideNotesAndCues_hasNothingToInsert() {
    let transcript = "这句是旁注"
    let units = IntentSourceSegmenter.segment(transcript)

    let invalid = plan(.render, units: [(units[0], .sideNote)])
    #expect(throws: IntentPlanVerifier.VerificationError.self) {
        try IntentPlanVerifier.verify(invalid, sourceUnits: units, transcript: transcript)
    }
}

@Test func sideNoteRole_decodesFromPlanJSON_unknownRoleStillRejected() throws {
    let good = #"{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"sideNote"}"#
    let unit = try JSONDecoder().decode(IntentPlanUnit.self, from: Data(good.utf8))
    #expect(unit.role == .sideNote)

    let bad = #"{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"metaThought"}"#
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(IntentPlanUnit.self, from: Data(bad.utf8))
    }
}
