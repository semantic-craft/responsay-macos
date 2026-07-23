import Foundation

/// A fact coordinate the model emitted (法条 / 案号 / 日期 / 标准).
public struct DetectedCoordinate: Sendable, Equatable {
    public let text: String
    public let kind: VerificationKind
    public init(text: String, kind: VerificationKind) {
        self.text = text
        self.kind = kind
    }
}

/// Output post-pass that enforces `[待核]` discipline (issue 121 / 108):
/// every fact coordinate in the (possibly style-pack-shaped) output is
/// reconciled against the known anchors. A coordinate keeps a verified status
/// **only if** an existing anchor confirms it *with a source*; everything else —
/// including a status a pack/model tried to assert without evidence — is forced
/// back to `.pending`. A style pack can never cancel pending.
public struct NewCoordinateGuard: Sendable {
    public init() {}

    private struct Detector {
        let kind: VerificationKind
        let regex: NSRegularExpression
    }

    private static let detectors: [Detector] = {
        func make(_ pattern: String, _ kind: VerificationKind) -> Detector? {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            return Detector(kind: kind, regex: re)
        }
        return [
            // 《名称》第X条 (provision) or bare 《名称》 (law/document)
            make("《[^》]{1,40}》(第[0-9一二三四五六七八九十百千零两]+条(之[0-9一二三四五六七八九十]+)?)?", .law),
            // 案号 （2023）京01民终1234号
            make("[（(][0-9]{4}[)）][^，。；、\\s]{0,24}?号", .caseLaw),
            // 国标 GB/T 39335 / GB 1234-2020
            make("GB(/T)?\\s?[0-9]+(\\.[0-9]+)*(-[0-9]{4})?", .standard),
            // 日期 2026年6月7日 / 2026-06-07
            make("[0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日", .date),
            make("[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}", .date),
        ].compactMap { $0 }
    }()

    /// All fact coordinates found in `text`, de-duplicated by surface form.
    public func detectCoordinates(in text: String) -> [DetectedCoordinate] {
        let ns = text as NSString
        var seen = Set<String>()
        var found: [DetectedCoordinate] = []
        for detector in Self.detectors {
            for match in detector.regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let surface = ns.substring(with: match.range)
                guard !seen.contains(surface) else { continue }
                seen.insert(surface)
                found.append(DetectedCoordinate(text: surface, kind: detector.kind))
            }
        }
        return found
    }

    /// Reconcile detected coordinates against `existing` anchors. Verified-with-
    /// source anchors are preserved; every other coordinate becomes `.pending`.
    public func reconcile(text: String, existing: [VerificationAnchor]) -> [VerificationAnchor] {
        detectCoordinates(in: text).enumerated().map { index, coordinate in
            if let confirmed = existing.first(where: { anchor in
                anchor.status != .pending
                    && anchor.source != nil
                    && (anchor.label.contains(coordinate.text) || coordinate.text.contains(anchor.label))
            }) {
                return confirmed
            }
            return VerificationAnchor(
                id: "guard.\(index)",
                label: coordinate.text,
                kind: coordinate.kind,
                status: .pending,
                query: coordinate.text
            )
        }
    }

    /// True when every detected coordinate in `text` is backed by a verified
    /// anchor — i.e. the output introduced no unverified coordinate.
    public func allCoordinatesVerified(text: String, existing: [VerificationAnchor]) -> Bool {
        reconcile(text: text, existing: existing).allSatisfy { $0.status != .pending }
    }
}
