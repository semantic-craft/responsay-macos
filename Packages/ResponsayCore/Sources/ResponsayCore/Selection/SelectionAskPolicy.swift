import Foundation

/// Privacy truncation for Selection-Ask (issue 169 / ADR-0014). Selected text is
/// capped at 4000 chars by default; going beyond requires an explicit,
/// user-confirmed cap; logs carry counts, never the raw text.
public enum SelectionAskPolicy {
    public static let defaultLimit = 4000

    public struct Truncation: Sendable, Equatable {
        public let text: String
        public let wasTruncated: Bool
        public let originalLength: Int
        public let limit: Int
    }

    /// Default cap. The UI shows `wasTruncated`; the raw text is never logged.
    public static func truncate(_ text: String, limit: Int = defaultLimit) -> Truncation {
        let count = text.count
        guard count > limit else {
            return Truncation(text: text, wasTruncated: false, originalLength: count, limit: limit)
        }
        return Truncation(text: String(text.prefix(limit)), wasTruncated: true, originalLength: count, limit: limit)
    }

    /// Expansion beyond the default — call ONLY after the user explicitly
    /// confirms a higher cap (e.g. an org build). Distinct entry point so the
    /// default path can never silently send more.
    public static func confirmedExpansion(_ text: String, confirmedLimit: Int) -> Truncation {
        truncate(text, limit: max(confirmedLimit, defaultLimit))
    }

    /// Log-safe one-liner — counts only, never any selected content.
    public static func redactedLog(_ truncation: Truncation) -> String {
        "selection-ask: \(truncation.originalLength)→\(truncation.text.count) chars, truncated=\(truncation.wasTruncated)"
    }
}
