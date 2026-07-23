import Foundation

@MainActor
public enum CaptureResultInserter {
    @discardableResult
    public static func insertIfNeeded(
        _ result: CaptureResult,
        using inserter: TextInserter
    ) async throws -> Bool {
        try result.validate()
        guard let text = result.insertText else { return false }
        // isEditableTarget: nil here → the copy-pill arm is unreachable (nil ≠ false), so this is
        // purely the policy rule (insert for insertImmediately/replaceSelection, skip otherwise).
        switch InsertionStrategyResolver.route(policy: result.insertPolicy, isEditableTarget: nil, hasText: !text.isEmpty) {
        case .insert:
            // Intent-aware insertText is already the exact byte sequence accepted by its
            // post-render guard. Do not mutate it after verification.
            let finalText = result.mode == .intentAwareDictation
                ? text
                : TextCorrectionRules.apply(to: text)
            try await inserter.insert(finalText)
            return true
        case .copyPill, .skip:
            return false
        }
    }
}
