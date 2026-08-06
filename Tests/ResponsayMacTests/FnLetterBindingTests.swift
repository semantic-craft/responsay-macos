import XCTest
@testable import ResponsayMac

@MainActor
final class FnLetterBindingTests: XCTestCase {

    private var store: ShortcutSettingsStore!
    private var testDefaults: UserDefaults!
    private let suite = "FnLetterBindingTests.\(UUID().uuidString)"

    override func setUp() {
        testDefaults = UserDefaults(suiteName: suite)!
        testDefaults.removePersistentDomain(forName: suite)
        store = ShortcutSettingsStore(defaults: testDefaults)
        store.fnHotkeyEnabled = true
        // A fresh store deliberately seeds the out-of-the-box `Fn → raw`
        // binding (migrateLegacyFnBindings) — clear it so these tests start
        // from a true zero baseline. They shipped red in bf001af7 because they
        // assumed an empty store; the seeding is intended first-run behavior.
        for binding in store.fnBindings { store.remove(binding) }
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suite)
    }

    // MARK: - Persistence of key chords

    func testAddFnLetterBinding() throws {
        let g = FnKey.from(keyCode: 5)!
        let chord = FnChord(modifiers: [], key: g)
        try store.addFnBinding(action: .raw, chord: chord)

        XCTAssertEqual(store.fnBindings.count, 1)
        XCTAssertEqual(store.fnBindings.first?.fnChord, chord)
        XCTAssertEqual(store.fnBindings.first?.action, .raw)
    }

    func testFnLetterBindingPersistsAcrossReload() throws {
        let g = FnKey.from(keyCode: 5)!
        let chord = FnChord(modifiers: [.shift], key: g)
        try store.addFnBinding(action: .polish, chord: chord)

        let store2 = ShortcutSettingsStore(defaults: testDefaults)
        let persisted = store2.fnBindings.first { $0.fnChord == chord }
        XCTAssertNotNil(persisted)
        XCTAssertEqual(persisted?.fnChord?.key?.display, "G")
        XCTAssertEqual(persisted?.fnChord?.modifiers, [.shift])
        XCTAssertEqual(persisted?.action, .polish)
    }

    func testActionLookupWithKeyChord() throws {
        let t = FnKey.from(keyCode: 17)!
        let chord = FnChord(modifiers: [], key: t)
        try store.addFnBinding(action: .polish, chord: chord)

        XCTAssertEqual(store.action(for: chord), .polish)
    }

    func testActionLookupWithFnSpaceChord() {
        XCTAssertNil(store.action(for: .fnSpace))

        XCTAssertNoThrow(try store.addFnBinding(action: .askAnything, chord: .fnSpace))
        XCTAssertEqual(store.action(for: .fnSpace), .askAnything)
    }

    func testRemoveFnLetterBinding() throws {
        let g = FnKey.from(keyCode: 5)!
        let chord = FnChord(modifiers: [], key: g)
        try store.addFnBinding(action: .raw, chord: chord)

        let binding = store.fnBindings.first!
        store.remove(binding)

        XCTAssertTrue(store.fnBindings.isEmpty)
        XCTAssertNil(store.action(for: chord))
    }

    // MARK: - Conflict detection with key chords

    func testFnLetterConflictDetected() throws {
        let g = FnKey.from(keyCode: 5)!
        let chord = FnChord(modifiers: [], key: g)
        try store.addFnBinding(action: .raw, chord: chord)

        XCTAssertThrowsError(try store.addFnBinding(action: .polish, chord: chord)) { error in
            if case ShortcutSettingsError.conflict(let existing) = error {
                XCTAssertEqual(existing, .raw)
            } else {
                XCTFail("Expected conflict error")
            }
        }
    }

    func testFnGAndFnShiftGDoNotConflict() throws {
        let g = FnKey.from(keyCode: 5)!
        let fnG = FnChord(modifiers: [], key: g)
        let fnShiftG = FnChord(modifiers: [.shift], key: g)

        try store.addFnBinding(action: .raw, chord: fnG)
        try store.addFnBinding(action: .polish, chord: fnShiftG)

        XCTAssertEqual(store.fnBindings.count, 2)
        XCTAssertEqual(store.action(for: fnG), .raw)
        XCTAssertEqual(store.action(for: fnShiftG), .polish)
    }

    func testFnLetterDoesNotConflictWithModifierOnly() throws {
        let g = FnKey.from(keyCode: 5)!
        let fnG = FnChord(modifiers: [], key: g)

        try store.addFnBinding(action: .raw, chord: .fnOnly)
        try store.addFnBinding(action: .polish, chord: fnG)

        XCTAssertEqual(store.fnBindings.count, 2)
    }

    func testConflictDetectorWithKeyChords() {
        let g = FnKey.from(keyCode: 5)!
        let fnG = FnChord(modifiers: [], key: g)
        let bindings: [ShortcutBinding] = [
            .fn(action: .raw, chord: fnG),
            .fn(action: .polish, chord: .fnShift)
        ]

        let detector = ShortcutConflictDetector()
        XCTAssertEqual(detector.fnConflict(chord: fnG, bindings: bindings), .raw)

        let fnT = FnChord(modifiers: [], key: FnKey.from(keyCode: 17)!)
        XCTAssertNil(detector.fnConflict(chord: fnT, bindings: bindings))
    }

    // MARK: - Modifier-only path not degraded

    func testModifierOnlyBindingsStillWork() throws {
        try store.addFnBinding(action: .raw, chord: .fnOnly)
        try store.addFnBinding(action: .polish, chord: .fnShift)

        XCTAssertEqual(store.action(for: .fnOnly), .raw)
        XCTAssertEqual(store.action(for: .fnShift), .polish)
    }

    /// Regression: deleting the shipped `Fn → 语音输入` default must stay recoverable. The bare-Fn
    /// chord can't be re-recorded (a bare Fn emits only `.flagsChanged`, never the `.keyDown` the
    /// recorder completes on), so the 「预设」menu re-adds it via `addFnBinding(.raw, .fnOnly)` —
    /// exactly what `UnifiedShortcutSection.addPreset` calls. Before the fix this was a one-way trap.
    func testDeletedBareFnDefaultCanBeReAdded() throws {
        try store.addFnBinding(action: .raw, chord: .fnOnly)
        let bareFn = store.fnBindings.first { $0.fnChord == .fnOnly }!
        store.remove(bareFn)
        XCTAssertNil(store.action(for: .fnOnly))

        try store.addFnBinding(action: .raw, chord: .fnOnly)   // user picks 「Fn」 from 预设
        XCTAssertEqual(store.action(for: .fnOnly), .raw)
    }

    /// The 「预设」menu is populated from `FnChord.stageOneAllowed(for:)`; it must keep offering every
    /// modifier-only default the recorder can't capture, or deleting them becomes unrecoverable again.
    func testPresetMenuOffersUnrecordableDefaults() {
        XCTAssertTrue(FnChord.stageOneAllowed(for: .fn).contains(.fnOnly))
        XCTAssertTrue(FnChord.stageOneAllowed(for: .fn).contains(.fnShift))
        XCTAssertTrue(FnChord.stageOneAllowed(for: .rightOption).contains(.rightOptionOnly))
    }

    func testResetToFnDefaultClearsKeyChords() throws {
        let g = FnKey.from(keyCode: 5)!
        try store.addFnBinding(action: .polish, chord: FnChord(modifiers: [], key: g))

        store.resetToFnDefault()

        XCTAssertEqual(store.fnBindings, [
            .fn(action: .raw, chord: .fnOnly),
            .fn(action: .translate, chord: .fnShift),
            .fn(action: .askAnything, chord: .fnSpace),
            .fn(action: .expressInEnglish, chord: .fnE),
            .fn(action: .selectionMenu, chord: .fnV),
            .fn(action: .readAloudSelection, chord: .fnR),
        ])
    }

    // MARK: - Binding ID format

    func testFnLetterBindingId() {
        let g = FnKey.from(keyCode: 5)!
        let chord = FnChord(modifiers: [], key: g)
        let binding = ShortcutBinding.fn(action: .raw, chord: chord)
        XCTAssertEqual(binding.id, "fn:fn+g")
    }
}
