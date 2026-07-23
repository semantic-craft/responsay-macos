import Foundation
import Testing
@testable import ResponsayCore

/// #567 · S3 — protected-literal invariant as a property test: with NO explicit correction, every
/// high-impact literal (number / date / amount / phone / URL / email / path / code / version /
/// citation) survives the deterministic source render VERBATIM. This tests the shipped guarantee —
/// the renderer only splices verbatim source substrings — not a separate literal extractor (which
/// `main` does not have). Negation / hedge / stance are
/// semantic-corpus concerns, deliberately NOT smuggled into a string property test (Testing #8).
struct IntentProtectedLiteralPropertyTests {
    /// Literals with no CJK inside them (so `TextCorrectionRules` Han↔ASCII spacing can only add
    /// space AROUND them, never split them). Dotted forms are split by the sentence segmenter and
    /// must reassemble exactly across units.
    static let literals = [
        "3000", "¥5000", "2026-07-12", "13800138000", "v1.2.3",
        "HT-2026-071", "user@ex.co", "https://a.co", "/usr/local/bin", "case-no-123"
    ]

    /// Han + ASCII carriers that place the literal at the start / middle / end and beside other text.
    static let carriers = ["金额{L}元", "记录一下{L}", "{L}", "发给他{L}谢谢", "先{L}再确认", "the value is {L} today"]

    static func compositions() -> [(transcript: String, literals: [String])] {
        var out = [(String, [String])]()
        for literal in literals {
            for carrier in carriers {
                out.append((carrier.replacingOccurrences(of: "{L}", with: literal), [literal]))
            }
        }
        // Two literals side by side in one utterance — both must survive.
        for i in literals.indices {
            let a = literals[i], b = literals[(i + 3) % literals.count]
            out.append(("先付 \(a) 再记编号 \(b) 存档", [a, b]))
        }
        return out
    }

    /// Deterministic render of an all-content, no-correction plan (no supersession / structure /
    /// entity), then the same `TextCorrectionRules` the pipeline applies. No provider, no preflight.
    private static func renderAllContent(_ transcript: String) throws -> String {
        let units = IntentSourceSegmenter.segment(transcript)
        let plan = IntentPlan(
            version: 1, decision: .noIntentControl,
            units: units.map { .init(source: .init($0), role: .content) },
            supersessions: [])
        let verified = try IntentPlanVerifier.verify(plan, sourceUnits: units, transcript: transcript)
        return TextCorrectionRules.apply(to: IntentSourceRenderer.render(verified).text)
    }

    @Test func everyLiteralSurvivesDeterministicRenderVerbatim() throws {
        for composition in Self.compositions() {
            let rendered = try Self.renderAllContent(composition.transcript)
            for literal in composition.literals {
                #expect(rendered.contains(literal),
                        "literal \(literal.debugDescription) lost from \(composition.transcript.debugDescription) → \(rendered.debugDescription)")
            }
        }
    }

    /// The whole no-correction render is the transcript itself, modulo deterministic Han↔ASCII
    /// spacing — no unit is dropped, so no literal-bearing content can silently vanish.
    @Test func noCorrectionRenderEqualsCorrectedTranscript() throws {
        for composition in Self.compositions() {
            let rendered = try Self.renderAllContent(composition.transcript)
            #expect(rendered == TextCorrectionRules.apply(to: composition.transcript),
                    "no-correction render must equal the corrected transcript")
        }
    }
}
