import Foundation

/// Bounded, in-memory recognition history for ASR context enhancement.
///
/// Histories are isolated by a stable caller-provided scope (the macOS app uses Bundle ID). Raw
/// final ASR text is retained; confirmed aliases are applied only when making an outgoing context
/// snapshot, so later dictionary edits never mutate the source history.
public struct RecentASRContextBuffer: Sendable {
    public static let maximumMessagesPerScope = 5
    public static let maximumCharactersPerMessage = 400

    private var messagesByScope: [String: [String]] = [:]

    public init() {}

    public mutating func record(_ text: String, scope: String) {
        let scope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scope.isEmpty, !text.isEmpty else { return }

        var messages = messagesByScope[scope, default: []]
        messages.append(String(text.prefix(Self.maximumCharactersPerMessage)))
        messagesByScope[scope] = Array(messages.suffix(Self.maximumMessagesPerScope))
    }

    public func context(
        for scope: String,
        learnedAliases: [String: String] = [:]
    ) -> [String] {
        let messages = messagesByScope[scope] ?? []
        guard !learnedAliases.isEmpty else { return messages }
        return messages.map {
            HotwordHardMatch.enforce(
                $0,
                userTerms: [],
                seedTerms: [],
                learnedAliases: learnedAliases).text
        }
    }
}
