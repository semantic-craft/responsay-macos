import Foundation
import Testing
@testable import ResponsayCore

@Suite("QwenReplayableAudioBuffer")
struct QwenReplayableAudioBufferTests {
    @Test func everyAttemptReceivesExistingAndFutureFramesInOrder() async {
        let buffer = QwenReplayableAudioBuffer()
        buffer.append(Data([0x01]))
        let firstAttempt = Task { await collect(buffer.replayingStream()) }
        buffer.append(Data([0x02]))
        buffer.finish()

        #expect(await firstAttempt.value == [Data([0x01]), Data([0x02])])
        #expect(await collect(buffer.replayingStream()) == [Data([0x01]), Data([0x02])])
    }

    private func collect(_ stream: AsyncStream<Data>) async -> [Data] {
        var frames: [Data] = []
        for await frame in stream { frames.append(frame) }
        return frames
    }
}
