import XCTest
@testable import ResponsayMac

@MainActor
final class ShortcutSettingsMigrationTests: XCTestCase {
    func testEmptyLegacyDataCreatesDefaultBindingsWithFnEnabledByDefault() {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertTrue(store.fnHotkeyEnabled)
        XCTAssertTrue(store.rightOptionHotkeyEnabled)
        XCTAssertBindings(store.fnBindings, [
            .fn(action: .raw, chord: .fnOnly),
            .fn(action: .translate, chord: .fnShift),
            .fn(action: .askAnything, chord: .fnSpace),
            .fn(action: .selectionMenu, chord: .fnV),
            .fn(action: .readAloudSelection, chord: .fnR),
        ])
        XCTAssertTrue(defaults.bool(forKey: "shortcutSettings.didMigrate.v1"))
    }

    func testLegacyRawNoneDoesNotRecreateDefaultRawFn() {
        let defaults = makeDefaults()
        defaults.set("none", forKey: "fnCombo.raw")

        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertBindings(store.fnBindings, [
            .fn(action: .translate, chord: .fnShift),
            .fn(action: .askAnything, chord: .fnSpace),
            .fn(action: .selectionMenu, chord: .fnV),
            .fn(action: .readAloudSelection, chord: .fnR),
        ])
    }

    func testLegacyRawShiftMigratesWithoutStealingFnShift() {
        let defaults = makeDefaults()
        defaults.set("fn+shift", forKey: "fnCombo.raw")

        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertBindings(store.fnBindings, [
            .fn(action: .raw, chord: .fnShift),
            .fn(action: .askAnything, chord: .fnSpace),
            .fn(action: .selectionMenu, chord: .fnV),
            .fn(action: .readAloudSelection, chord: .fnR),
        ])
    }

    func testLegacyEnglishExpressionMigrates() {
        let defaults = makeDefaults()
        defaults.set("fn+option", forKey: "fnCombo.englishExpressionMode")

        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertBindings(store.fnBindings, [
            .fn(action: .raw, chord: .fnOnly),
            .fn(action: .translate, chord: .fnShift),
            .fn(action: .expressInEnglish, chord: .fnOption),
            .fn(action: .askAnything, chord: .fnSpace),
            .fn(action: .selectionMenu, chord: .fnV),
            .fn(action: .readAloudSelection, chord: .fnR),
        ])
    }

    func testDuplicateLegacyChordKeepsFirstVisibleAction() {
        let defaults = makeDefaults()
        defaults.set("fn+shift", forKey: "fnCombo.raw")
        defaults.set("fn+shift", forKey: "fnCombo.polish")

        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertBindings(store.fnBindings, [
            .fn(action: .raw, chord: .fnShift),
            .fn(action: .askAnything, chord: .fnSpace),
            .fn(action: .selectionMenu, chord: .fnV),
            .fn(action: .readAloudSelection, chord: .fnR),
        ])
    }

    func testExistingCurrentSnapshotSkipsLegacyMigrationAndDoesNotReseedDefaults() throws {
        let defaults = makeDefaults()
        defaults.set("fn", forKey: "fnCombo.raw")
        let snapshot = ShortcutSettingsSnapshot(
            schemaVersion: ShortcutSettingsSnapshot.currentVersion,
            fnBindings: [.fn(action: .polish, chord: .fnShift)]
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "shortcutSettings.v1")

        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertBindings(store.fnBindings, [.fn(action: .polish, chord: .fnShift)])
    }

    func testCurrentSnapshotMovesRetiredStandaloneTranslateSelectionBindingToTranslate() throws {
        let defaults = makeDefaults()
        let snapshot = ShortcutSettingsSnapshot(
            schemaVersion: ShortcutSettingsSnapshot.currentVersion,
            fnBindings: [
                .fn(action: .raw, chord: .fnOnly),
                .fn(action: .translateSelection, chord: .fnShift),
            ]
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "shortcutSettings.v1")

        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertBindings(store.fnBindings, [
            .fn(action: .raw, chord: .fnOnly),
            .fn(action: .translate, chord: .fnShift),
        ])
    }

    func testCurrentSnapshotMovesRetiredSelectionTranslateEvenWhenExpressInEnglishAlreadyExists() throws {
        let defaults = makeDefaults()
        let snapshot = ShortcutSettingsSnapshot(
            schemaVersion: ShortcutSettingsSnapshot.currentVersion,
            fnBindings: [
                .fn(action: .expressInEnglish, chord: .fnOption),
                .fn(action: .translateSelection, chord: .fnShift),
            ]
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "shortcutSettings.v1")

        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertBindings(store.fnBindings, [
            .fn(action: .expressInEnglish, chord: .fnOption),
            .fn(action: .translate, chord: .fnShift),
        ])
    }

    func testLegacyV1SnapshotSeedsMissingDefaultsOnce() throws {
        let defaults = makeDefaults()
        let snapshot = ShortcutSettingsSnapshot(
            schemaVersion: 1,
            fnBindings: [.fn(action: .polish, chord: .fnShift)]
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "shortcutSettings.v1")

        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertBindings(store.fnBindings, [
            .fn(action: .polish, chord: .fnShift),
            .fn(action: .askAnything, chord: .fnSpace),
            .fn(action: .selectionMenu, chord: .fnV),
            .fn(action: .expressInEnglish, chord: .fnE),
            .fn(action: .readAloudSelection, chord: .fnR),
        ])
        let saved = try XCTUnwrap(defaults.data(forKey: "shortcutSettings.v1"))
        let decoded = try JSONDecoder().decode(ShortcutSettingsSnapshot.self, from: saved)
        XCTAssertEqual(decoded.schemaVersion, ShortcutSettingsSnapshot.currentVersion)
    }

    func testVersionOneSnapshotDoesNotStealFnSpaceWhenOccupied() throws {
        let defaults = makeDefaults()
        let snapshot = ShortcutSettingsSnapshot(
            schemaVersion: 1,
            fnBindings: [
                .fn(action: .raw, chord: .fnOnly),
                .fn(action: .polish, chord: .fnSpace),
            ]
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "shortcutSettings.v1")

        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertBindings(store.fnBindings, [
            .fn(action: .raw, chord: .fnOnly),
            .fn(action: .polish, chord: .fnSpace),
            .fn(action: .translate, chord: .fnShift),
            .fn(action: .selectionMenu, chord: .fnV),
            .fn(action: .expressInEnglish, chord: .fnE),
            .fn(action: .readAloudSelection, chord: .fnR),
        ])
    }

    func testVersionOneSnapshotDoesNotStealFnShiftWhenOccupied() throws {
        let defaults = makeDefaults()
        let snapshot = ShortcutSettingsSnapshot(
            schemaVersion: 1,
            fnBindings: [
                .fn(action: .raw, chord: .fnOnly),
                .fn(action: .polish, chord: .fnShift),
            ]
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "shortcutSettings.v1")

        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertBindings(store.fnBindings, [
            .fn(action: .raw, chord: .fnOnly),
            .fn(action: .polish, chord: .fnShift),
            .fn(action: .askAnything, chord: .fnSpace),
            .fn(action: .selectionMenu, chord: .fnV),
            .fn(action: .expressInEnglish, chord: .fnE),
            .fn(action: .readAloudSelection, chord: .fnR),
        ])
    }

    func testRightOptionDisabledLegacySettingDoesNotSeedRightOptionBindings() {
        let defaults = makeDefaults()
        RightOptionTriggerSettings.setAction(nil, defaults: defaults)

        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertFalse(store.rightOptionHotkeyEnabled)
        XCTAssertBindings(store.fnBindings, [
            .fn(action: .raw, chord: .fnOnly),
            .fn(action: .translate, chord: .fnShift),
            .fn(action: .askAnything, chord: .fnSpace),
            .fn(action: .selectionMenu, chord: .fnV),
            .fn(action: .readAloudSelection, chord: .fnR),
        ])
    }

    func testRefreshFromDefaultsDoesNotWriteWhenValuesAreUnchanged() {
        let defaults = makeDefaults()
        let store = ShortcutSettingsStore(defaults: defaults)
        var didChangeCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            didChangeCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        didChangeCount = 0
        store.refreshFromDefaults()

        XCTAssertEqual(didChangeCount, 0)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ResponsayMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func XCTAssertBindings(
        _ actual: [ShortcutBinding],
        _ expected: [ShortcutBinding],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set(actual), Set(expected), file: file, line: line)
    }
}
