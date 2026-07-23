struct ShortcutSettingsSnapshot: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var fnBindings: [ShortcutBinding]

    static let currentVersion = 5
}
