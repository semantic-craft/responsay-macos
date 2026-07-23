import Foundation

// MARK: - Anchor verify commit guard
//
// Decides whether an in-flight online-verification result should be committed to
// the UI, or discarded. A verify network call can take up to ~90s; if the user
// cancels it or dismisses the panel meanwhile, a late result must NOT overwrite a
// view they already moved on from. Borrowed from openless's `cancelled`-flag
// session discipline ("无法撤销…只会让 UI 出现 cancelled"): a cancelled run, or a
// CancellationError, commits nothing.
//
// Pure + UI-agnostic so the rule is unit-testable without a SwiftUI host.

public enum AnchorVerifyCommit {
    /// The state to commit after a verify resolves — or `nil` to discard it.
    /// - `cancelled`: whether the run was cancelled (task cancelled / panel torn down).
    /// - `result`: the verify outcome (a `VerifiedSource?`, or the thrown error).
    public static func resolve(
        cancelled: Bool,
        result: Result<VerifiedSource?, Error>
    ) -> AnchorSearchState? {
        guard !cancelled else { return nil }
        switch result {
        case .success(let source):
            return AnchorSearchState.from(source: source)
        case .failure(let error):
            if error is CancellationError { return nil }
            return .error(error.localizedDescription)
        }
    }
}
