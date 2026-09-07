import AppKit
import SwiftUI
import XCTest
@testable import ResponsayCore
@testable import ResponsayMac

@MainActor
final class VoiceAssistantTimeoutPanelTests: XCTestCase {
    func testFirstTurnTimeoutShowsDismissibleErrorCard() async throws {
        _ = NSApplication.shared
        try XCTSkipIf(NSScreen.screens.isEmpty, "Requires a window server")
        let speech = TimeoutPanelSpeech()
        let vm = VoiceAssistantViewModel(speech: speech)
        vm.maxListeningDuration = .milliseconds(10)
        let panel = VoiceAssistantPanel(vm: vm)
        panel.start()
        defer {
            vm.clearConversation()
            for window in resultWindows(for: vm) { window.close() }
        }
        vm.startCapture()
        let deadline = ContinuousClock.now + .seconds(2)
        while !resultWindows(for: vm).contains(where: { $0.isVisible }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertEqual(speech.stopCalls, 1)
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertNil(vm.selectionContext)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(resultWindows(for: vm).contains(where: { $0.isVisible }))
        vm.clearConversation()
        let dismissDeadline = ContinuousClock.now + .seconds(2)
        while resultWindows(for: vm).contains(where: { $0.isVisible }),
              ContinuousClock.now < dismissDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(resultWindows(for: vm).contains(where: { $0.isVisible }))
        withExtendedLifetime(panel) {}
    }

    private func resultWindows(for vm: VoiceAssistantViewModel) -> [NSWindow] {
        NSApplication.shared.windows.filter {
            ($0.contentViewController as? NSHostingController<VoiceAssistantResultPanel>)?.rootView.vm === vm
        }
    }
}

@MainActor private final class TimeoutPanelSpeech: SpeechCaptureService {
    let levels = AsyncStream<Float> { $0.finish() }
    var stopCalls = 0
    func start(locale: CaptureLocale) throws {}
    func stop() async throws -> String {
        stopCalls += 1
        return "discard this question"
    }
}
