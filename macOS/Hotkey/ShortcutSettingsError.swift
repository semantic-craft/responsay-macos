enum ShortcutSettingsError: Error, Equatable {
    case conflict(existingAction: ShortcutAction)
    case noAvailableNormalSlot
    case invalidNormalShortcut
}
