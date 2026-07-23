import Foundation
import Testing
@testable import ResponsayCore

/// #567 · S3 — source-coordinate / UTF-16 / exact-quote invariants of the segmenter, as property
/// tests over a DETERMINISTIC composition grid (reproducible, not random — a release gate must not
/// flake). Atoms cover emoji surrogate pairs, combining marks, CJK, mixed alphanumerics, repeated
/// substrings and every separator, in every 1–3 atom arrangement.
struct IntentSourceCoordinatePropertyTests {
    /// e + U+0301 (one grapheme, two UTF-16 units), 😀 (surrogate pair), CJK, mixed, a repeat seed,
    /// and three separator flavours.
    static let atoms = ["😀", "e\u{0301}", "测试", "Ab1", "重复", "，", "。", ","]

    /// All 1-, 2- and 3-atom concatenations (8 + 64 + 512 = 584 transcripts), fully deterministic.
    static func compositions() -> [String] {
        var out = [""]                    // include the degenerate empty transcript
        for a in atoms {
            out.append(a)
            for b in atoms {
                out.append(a + b)
                for c in atoms { out.append(a + b + c) }
            }
        }
        return out
    }

    @Test func segmentUnitsRoundTripToTheirExactSubstring() {
        for transcript in Self.compositions() {
            let ns = transcript as NSString
            for unit in IntentSourceSegmenter.segment(transcript) {
                #expect(unit.utf16Range.location >= 0 && unit.utf16Range.length > 0)
                #expect(unit.utf16Range.location + unit.utf16Range.length <= ns.length)
                #expect(ns.substring(with: unit.utf16Range.nsRange) == unit.originalText,
                        "round-trip failed for \(transcript.debugDescription)")
            }
        }
    }

    @Test func segmentRangesSeamlesslyPartitionTheTranscript() {
        for transcript in Self.compositions() {
            let units = IntentSourceSegmenter.segment(transcript)
            var cursor = 0
            for (index, unit) in units.enumerated() {
                #expect(unit.utf16Range.location == cursor,
                        "gap/overlap at unit \(index) of \(transcript.debugDescription)")
                #expect(unit.id == String(format: "source-%04d", index))
                cursor += unit.utf16Range.length
            }
            #expect(cursor == (transcript as NSString).length,
                    "units must cover every UTF-16 unit of \(transcript.debugDescription)")
        }
    }

    /// Every composition compiles to a verifier-valid all-content plan — i.e. the segmenter's
    /// coordinates + exact quotes survive the verifier's reference validation round-trip.
    @Test func allContentPlanVerifiesForEveryComposition() throws {
        for transcript in Self.compositions() {
            let units = IntentSourceSegmenter.segment(transcript)
            guard !units.isEmpty else {
                #expect(transcript.isEmpty)   // only the empty transcript yields zero units
                continue
            }
            let plan = IntentPlan(
                version: 1, decision: .noIntentControl,
                units: units.map { .init(source: .init($0), role: .content) },
                supersessions: [])
            #expect(throws: Never.self, "verify must accept \(transcript.debugDescription)") {
                _ = try IntentPlanVerifier.verify(plan, sourceUnits: units, transcript: transcript)
            }
        }
    }

    // MARK: - Out-of-range / exact-quote tamper is rejected (the UTF-16 guard)

    @Test func outOfBoundsRangeOrQuoteMismatchIsRejected() {
        let transcript = "测试，Ab1"
        let units = IntentSourceSegmenter.segment(transcript)
        let overLength = (transcript as NSString).length + 3

        // (1) A reference claiming a length past the end of the transcript.
        let outOfBounds = IntentPlan(
            version: 1, decision: .noIntentControl,
            units: [
                .init(source: .init(
                    sourceID: units[0].id,
                    range: .init(location: units[0].utf16Range.location, length: overLength),
                    exactQuote: units[0].originalText), role: .content),
                .init(source: .init(units[1]), role: .content)
            ], supersessions: [])
        #expect(throws: (any Error).self) {
            _ = try IntentPlanVerifier.verify(outOfBounds, sourceUnits: units, transcript: transcript)
        }

        // (2) A reference whose exactQuote no longer matches the substring at its range.
        let quoteMismatch = IntentPlan(
            version: 1, decision: .noIntentControl,
            units: [
                .init(source: .init(
                    sourceID: units[0].id, range: units[0].utf16Range,
                    exactQuote: units[0].originalText + "X"), role: .content),
                .init(source: .init(units[1]), role: .content)
            ], supersessions: [])
        #expect(throws: (any Error).self) {
            _ = try IntentPlanVerifier.verify(quoteMismatch, sourceUnits: units, transcript: transcript)
        }
    }
}
