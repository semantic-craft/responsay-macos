import Testing
import Foundation
@testable import ResponsayCore

@Test @MainActor func mockSpeech_emitsLevels() async {
    let speech = MockSpeechCaptureService()
    var received: [Float] = []
    let task = Task { for await v in speech.levels { received.append(v); if received.count == 2 { break } } }
    speech.emitLevel(0.2); speech.emitLevel(0.7)
    await task.value
    #expect(received == [0.2, 0.7])
}
