import CoreGraphics
import XCTest
@testable import ResponsayMac

/// `SyntheticEventTag` is how the Fn CGEventTap tells its own posted keystrokes (text insertion,
/// ⌘V, ⌘C) apart from real presses. The only non-trivial assumption is that a userData stamp set on
/// the source round-trips into `kCGEventSourceUserData` on the created event — assert exactly that.
final class SyntheticEventTagTests: XCTestCase {
    private let cKeyCode: CGKeyCode = 8  // C — what ClipboardCopier synthesizes for ⌘C

    func testRecognisesEventPostedFromTaggedSource() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .combinedSessionState))
        source.userData = SyntheticEventTag.userData
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true))
        XCTAssertTrue(SyntheticEventTag.isOurs(event))
    }

    func testDoesNotClaimUntaggedEvent() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .combinedSessionState))  // userData defaults to 0
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true))
        XCTAssertFalse(SyntheticEventTag.isOurs(event))
    }
}
