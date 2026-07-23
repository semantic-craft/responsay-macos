import Foundation

// MARK: - Anchor verification UI state

public enum AnchorSearchState: Sendable, Equatable {
    case idle
    case loading
    case success(VerifiedSource)
    case notFound
    case error(String)
    case disabled

    public static func from(source: VerifiedSource?) -> AnchorSearchState {
        source.map { .success($0) } ?? .notFound
    }

    public var isPending: Bool {
        switch self {
        case .idle, .loading: return true
        default: return false
        }
    }

    public var hasResult: Bool {
        switch self {
        case .success, .notFound: return true
        default: return false
        }
    }

    public var verifiedSource: VerifiedSource? {
        if case .success(let s) = self { return s }
        return nil
    }
}
