struct FnChord: Codable, Hashable, Identifiable, Sendable {
    var anchor: ShortcutAnchor
    var modifiers: Set<FnModifier>
    var key: FnKey?

    init(anchor: ShortcutAnchor = .fn, modifiers: Set<FnModifier>, key: FnKey?) {
        self.anchor = anchor
        self.modifiers = modifiers
        self.key = key
    }

    var id: String {
        let modifierPart = modifiers
            .sortedForDisplay
            .map(\.rawValue)
            .joined(separator: "+")
        let keyPart = key?.idSlug ?? ""

        return [anchor.rawValue, modifierPart, keyPart]
            .filter { !$0.isEmpty }
            .joined(separator: "+")
    }

    var isLetterKeyChord: Bool {
        key != nil
    }

    var displayString: String {
        let modifierText = modifiers
            .sortedForDisplay
            .map(\.symbol)
            .joined(separator: " ")

        if let key {
            return modifierText.isEmpty
                ? "\(anchor.displayString) \(key.display)"
                : "\(anchor.displayString) \(modifierText) \(key.display)"
        }

        return modifierText.isEmpty ? anchor.displayString : "\(anchor.displayString) \(modifierText)"
    }

    static let fnOnly = FnChord(modifiers: [], key: nil)
    static let fnShift = FnChord(modifiers: [.shift], key: nil)
    static let fnOption = FnChord(modifiers: [.option], key: nil)
    static let fnControl = FnChord(modifiers: [.control], key: nil)
    static let fnCommand = FnChord(modifiers: [.command], key: nil)
    static let fnSpace = FnChord(modifiers: [], key: .space)
    static let fnV = FnChord(modifiers: [], key: .v)
    static let fnE = FnChord(modifiers: [], key: .e)

    static let rightOptionOnly = FnChord(anchor: .rightOption, modifiers: [], key: nil)
    static let rightOptionShift = FnChord(anchor: .rightOption, modifiers: [.shift], key: nil)
    static let rightOptionControl = FnChord(anchor: .rightOption, modifiers: [.control], key: nil)
    static let rightOptionCommand = FnChord(anchor: .rightOption, modifiers: [.command], key: nil)
    /// Hyper key = ⌃⌥⇧⌘. Since right Option is the anchor, the extra Option bit is not repeated.
    /// Parse-only: no longer offered in the settings quick-add menu (nobody chords four modifiers);
    /// kept so any pre-existing binding still resolves and the runtime/NSEvent tests stay green.
    static let rightOptionHyper = FnChord(anchor: .rightOption, modifiers: [.shift, .control, .command], key: nil)

    static let stageOneAllowed: [FnChord] = [
        .fnOnly,
        .fnShift,
        .fnOption,
        .fnControl,
        .fnCommand
    ]

    static func stageOneAllowed(for anchor: ShortcutAnchor) -> [FnChord] {
        switch anchor {
        case .fn:
            stageOneAllowed
        case .rightOption:
            // Mirrors the Fn list: anchor alone + one single modifier each. (No +Option — right
            // Option IS the anchor; no Hyper — see rightOptionHyper, dropped as un-chordable.)
            [
                .rightOptionOnly,
                .rightOptionShift,
                .rightOptionControl,
                .rightOptionCommand
            ]
        }
    }

    static let settingsQuickAddAllowed: [FnChord] = stageOneAllowed + [.fnSpace, .fnV, .fnE]

    /// Anchor + single-letter chords a user can hand-pick in settings (Fn + A … Fn + Z).
    /// The runtime path (FnChordStateMachine letter detection, conflict checks, persistence)
    /// already supports these — settings just had no way to choose one.
    static func customLetterChords(for anchor: ShortcutAnchor) -> [FnChord] {
        FnKey.letters.map { FnChord(anchor: anchor, modifiers: [], key: $0) }
    }

    private enum CodingKeys: String, CodingKey {
        case anchor
        case modifiers
        case key
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.anchor = try container.decodeIfPresent(ShortcutAnchor.self, forKey: .anchor) ?? .fn
        self.modifiers = try container.decode(Set<FnModifier>.self, forKey: .modifiers)
        self.key = try container.decodeIfPresent(FnKey.self, forKey: .key)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(anchor, forKey: .anchor)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encodeIfPresent(key, forKey: .key)
    }
}
