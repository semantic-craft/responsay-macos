import Testing
import Foundation
@testable import ResponsayCore

/// 200 — diagnostics event bus (ring buffer) + R6 TTSError userMessage. T1 headless.
@MainActor
struct DiagnosticsCenterTests {
    private func event(_ i: Int, _ category: DiagnosticEvent.Category = .tts) -> DiagnosticEvent {
        DiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: TimeInterval(i)),
            category: category, level: .info, title: "e\(i)")
    }

    @Test func recordAppendsNewestLast() {
        let center = DiagnosticsCenter()
        center.record(event(1)); center.record(event(2))
        #expect(center.events.map(\.title) == ["e1", "e2"])
    }

    @Test func capsAtMaxDroppingOldest() {
        let center = DiagnosticsCenter(maxEvents: 3)
        for i in 1...5 { center.record(event(i)) }
        #expect(center.events.count == 3)
        #expect(center.events.map(\.title) == ["e3", "e4", "e5"])  // oldest two evicted
    }

    @Test func clearEmptiesBuffer() {
        let center = DiagnosticsCenter()
        center.record(event(1))
        center.clear()
        #expect(center.events.isEmpty)
    }

    @Test func categoryFilterReturnsNewestFirst() {
        let center = DiagnosticsCenter()
        center.record(event(1, .tts)); center.record(event(2, .asr)); center.record(event(3, .tts))
        #expect(center.events(in: .tts).map(\.title) == ["e3", "e1"])  // newest first, asr excluded
        #expect(center.events(in: .asr).map(\.title) == ["e2"])
    }

    // MARK: - R6 TTSError

    @Test func ttsErrorUserMessagesAreNonEmptyAndCarryContext() {
        #expect(TTSError.missingAPIKey(provider: "通义千问").userMessage.contains("通义千问"))
        #expect(TTSError.http(status: 401).userMessage.contains("401"))
        #expect(TTSError.providerReturnedNoAudio(provider: "Gemini").userMessage.contains("Gemini"))
        #expect(!TTSError.modelNotInstalled.userMessage.isEmpty)
        #expect(TTSError.synthesisFailed("raw detail").userMessage == "raw detail")
        #expect(TTSError.network("timeout").userMessage.contains("timeout"))
    }

    @Test func ttsErrorCasesAreEquatable() {
        #expect(TTSError.http(status: 401) == .http(status: 401))
        #expect(TTSError.http(status: 401) != .http(status: 500))
        #expect(TTSError.missingAPIKey(provider: "a") != .missingAPIKey(provider: "b"))
    }
}
