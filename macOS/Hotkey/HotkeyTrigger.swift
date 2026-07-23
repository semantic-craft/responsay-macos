enum HotkeyTrigger: Hashable, Sendable {
    case normal(NormalShortcutSlot)
    case anchor(FnChord)

    static func fn(_ chord: FnChord) -> HotkeyTrigger {
        .anchor(chord)
    }

    var id: String {
        switch self {
        case let .normal(slot):
            "normal:\(slot.id)"
        case let .anchor(chord):
            "anchor:\(chord.id)"
        }
    }
}
