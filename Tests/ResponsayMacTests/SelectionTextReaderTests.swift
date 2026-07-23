import XCTest
@testable import ResponsayMac

/// 253 — TDD for the unified SelectionTextReader.
/// Behaviors: AX-first fallback cascade, sentinel validation, pasteboard safety.
@MainActor
final class SelectionTextReaderTests: XCTestCase {

    // MARK: - Tracer bullet: AX succeeds → return immediately, no clipboard touch

    func testAXSuccess_returnsTextWithoutClipboard() async {
        var clipboardCalled = false
        let reader = SelectionTextReader(
            axReader: { _ in "Hello world" },
            clipboardCopier: { _ in clipboardCalled = true; return "stale" })

        let result = await reader.readSelectedText(from: nil)

        XCTAssertEqual(result, "Hello world")
        XCTAssertFalse(clipboardCalled, "Clipboard should not be touched when AX succeeds")
    }

    // MARK: - AX nil → falls back to clipboard

    func testAXNil_fallsBackToClipboard() async {
        let reader = SelectionTextReader(
            axReader: { _ in nil },
            clipboardCopier: { _ in "clipboard text" })

        let result = await reader.readSelectedText(from: nil)

        XCTAssertEqual(result, "clipboard text")
    }

    // MARK: - AX whitespace-only → treated as empty, falls back to clipboard

    func testAXWhitespaceOnly_fallsBackToClipboard() async {
        let reader = SelectionTextReader(
            axReader: { _ in "  \n\t  " },
            clipboardCopier: { _ in "real selection" })

        let result = await reader.readSelectedText(from: nil)

        XCTAssertEqual(result, "real selection")
    }

    // MARK: - Both fail → returns nil

    func testBothFail_returnsNil() async {
        let reader = SelectionTextReader(
            axReader: { _ in nil },
            clipboardCopier: { _ in nil })

        let result = await reader.readSelectedText(from: nil)

        XCTAssertNil(result, "Should return nil when both AX and clipboard fail")
    }

    // MARK: - 255: sentinel scenario — Cmd+C failed, copier returns nil

    func testCmdCFailed_sentinelFiltered_returnsNil() async {
        let reader = SelectionTextReader(
            axReader: { _ in nil },
            clipboardCopier: { _ in
                // ClipboardCopier internally detects sentinel == read → returns nil
                nil
            })

        let result = await reader.readSelectedText(from: nil)

        XCTAssertNil(result, "When Cmd+C fails (sentinel not overwritten), should return nil")
    }

    // MARK: - 255: Cmd+C overwrites sentinel with real content → returns that content

    func testCmdCSuccess_overwritesSentinel_returnsContent() async {
        let reader = SelectionTextReader(
            axReader: { _ in nil },
            clipboardCopier: { _ in
                // ClipboardCopier: target app overwrote sentinel → returns real text
                "The actual selected text from target app"
            })

        let result = await reader.readSelectedText(from: nil)

        XCTAssertEqual(result, "The actual selected text from target app")
    }
}
