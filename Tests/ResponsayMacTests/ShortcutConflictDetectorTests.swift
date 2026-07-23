import KeyboardShortcuts
import XCTest
@testable import ResponsayMac

@MainActor
final class ShortcutConflictDetectorTests: XCTestCase {
    func testNormalConflictDetectsAppDuplicate() {
        let detector = ShortcutConflictDetector()
        let occupiedSlot = NormalShortcutSlot(action: .raw, index: 1)
        let candidateSlot = NormalShortcutSlot(action: .polish, index: 1)
        let shortcut = KeyboardShortcuts.Shortcut(.d, modifiers: [.command, .control])

        KeyboardShortcuts.setShortcut(shortcut, for: occupiedSlot.name)
        defer {
            KeyboardShortcuts.setShortcut(nil, for: occupiedSlot.name)
        }

        XCTAssertEqual(detector.normalConflict(shortcut: shortcut, excluding: candidateSlot), .raw)
        XCTAssertNil(detector.normalConflict(shortcut: shortcut, excluding: occupiedSlot))
    }

    func testFnConflictDetectsExistingBinding() {
        let detector = ShortcutConflictDetector()
        let bindings: [ShortcutBinding] = [
            .fn(action: .raw, chord: .fnOnly),
            .fn(action: .polish, chord: .fnShift)
        ]

        XCTAssertEqual(detector.fnConflict(chord: .fnShift, bindings: bindings), .polish)
        XCTAssertNil(detector.fnConflict(chord: .fnControl, bindings: bindings))
    }
}
