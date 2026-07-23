import Foundation

/// The allowed grounding inputs the app hands to entity-candidate generation (#562, spec
/// decision 15): personal-dictionary terms, confirmed aliases, and privacy-gated text from the
/// user-permitted screen context. Absence of a source is expressed by emptiness — there is no
/// other way in, so unauthorized sources (contacts / web / model memory) are structurally
/// unrepresentable.
public struct IntentGroundingSources: Sendable, Equatable {
    public struct Alias: Sendable, Equatable {
        /// The surface form an ASR routinely produces (e.g. 拉伦兹).
        public let surface: String
        /// The user-confirmed canonical spelling (e.g. 拉伦茨).
        public let canonical: String

        public init(surface: String, canonical: String) {
            self.surface = surface
            self.canonical = canonical
        }
    }

    public let dictionaryTerms: [String]
    public let aliases: [Alias]
    /// Raw text fields from the ALLOWED context snapshot (already gated by 屏幕上下文). The
    /// table builder tokenizes and privacy-filters these; they are candidate evidence, never
    /// instructions.
    public let contextTexts: [String]

    public init(
        dictionaryTerms: [String] = [],
        aliases: [Alias] = [],
        contextTexts: [String] = []
    ) {
        self.dictionaryTerms = dictionaryTerms
        self.aliases = aliases
        self.contextTexts = contextTexts
    }

    public static let empty = IntentGroundingSources()
}
