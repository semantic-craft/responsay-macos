import Foundation

/// One rendered run of the original→idiomatic diff.
public struct DiffSegment: Equatable, Sendable {
    public enum Kind: Sendable, Equatable { case same, inserted, deleted }
    public let text: String
    public let kind: Kind
    public init(_ text: String, _ kind: Kind) { self.text = text; self.kind = kind }
}

/// How the coach card should present the original vs the idiomatic version.
/// English source → colored word diff; CJK source → quote the original, no diff.
public enum CoachDiffPresentation: Equatable, Sendable {
    case diff([DiffSegment])
    case sourceQuote(String)

    public static func make(original: String, idiomatic: String) -> CoachDiffPresentation {
        guard WordDiff.shouldShow(forSource: original) else { return .sourceQuote(original) }
        let segments = WordDiff.diff(original: original, idiomatic: idiomatic).map { op -> DiffSegment in
            switch op {
            case .same(let w): return DiffSegment(w, .same)
            case .del(let w):  return DiffSegment(w, .deleted)
            case .ins(let w):  return DiffSegment(w, .inserted)
            }
        }
        return .diff(segments)
    }
}
