struct ShortcutBinding: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var action: ShortcutAction
    var family: ShortcutBindingFamily
    var normalSlotIndex: Int?
    var fnChord: FnChord?
    var isEnabled: Bool

    static func normal(action: ShortcutAction, slotIndex: Int) -> ShortcutBinding {
        ShortcutBinding(
            id: "normal:\(action.rawValue):\(slotIndex)",
            action: action,
            family: .normal,
            normalSlotIndex: slotIndex,
            fnChord: nil,
            isEnabled: true
        )
    }

    static func fn(action: ShortcutAction, chord: FnChord) -> ShortcutBinding {
        anchor(action: action, chord: chord)
    }

    static func anchor(action: ShortcutAction, chord: FnChord) -> ShortcutBinding {
        ShortcutBinding(
            id: "\(chord.anchor.rawValue):\(chord.id)",
            action: action,
            family: .fn,
            normalSlotIndex: nil,
            fnChord: chord,
            isEnabled: true
        )
    }
}
