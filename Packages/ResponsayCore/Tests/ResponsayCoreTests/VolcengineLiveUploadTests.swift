import Foundation
import XCTest
@testable import ResponsayCore

final class VolcengineLiveUploadTests: XCTestCase {
    func testSendsAudioBeforeInputEndsAndReturnsOnlyTerminalTranscript() async throws {
        let sent = expectation(description: "PCM sent before stop")
        let transport = VolcSocketDouble(onAudio: { sent.fulfill() })
        var api = VolcengineRealtimeTranscriptionAPI(endpoint: .init(apiKey: "test"))
        api.transportProvider = { _ in transport }
        let (audio, continuation) = AsyncStream.makeStream(of: Data.self)
        let task = Task { try await api.transcribe(audio: audio) }
        continuation.yield(Data(repeating: 3, count: 6500))
        await fulfillment(of: [sent], timeout: 2)
        XCTAssertFalse(transport.didFinish)
        continuation.finish()
        let result = try await task.value
        XCTAssertEqual(result, "整句最终结果")
        XCTAssertTrue(transport.didFinish)
        XCTAssertTrue(transport.cancelled)
        XCTAssertEqual(transport.pcmBytes, 6500)
    }

    func testSendFailureClosesSocketAndUnblocksReceiver() async throws {
        let transport = VolcSocketDouble(failAudio: true)
        var api = VolcengineRealtimeTranscriptionAPI(endpoint: .init(apiKey: "test"))
        api.transportProvider = { _ in transport }
        let (audio, continuation) = AsyncStream.makeStream(of: Data.self)
        continuation.yield(Data(repeating: 3, count: 6400))
        do { _ = try await api.transcribe(audio: audio); XCTFail("Expected send failure") }
        catch let error as URLError { XCTAssertEqual(error.code, .networkConnectionLost) }
        catch { XCTFail("Unexpected error: \(error)") }
        continuation.finish()
        XCTAssertTrue(transport.cancelled)
    }
}

private final class VolcSocketDouble: VolcengineRealtimeTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let input: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let onAudio: @Sendable () -> Void
    private let failAudio: Bool
    private var finished = false
    private var closed = false
    private var bytes = 0
    private var receiving = false
    var didFinish: Bool { lock.withLock { finished } }
    var cancelled: Bool { lock.withLock { closed } }
    var pcmBytes: Int { lock.withLock { bytes } }
    init(failAudio: Bool = false, onAudio: @escaping @Sendable () -> Void = {}) {
        (input, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
        self.failAudio = failAudio
        self.onAudio = onAudio
    }
    func start() {}
    func send(_ data: Data) async throws {
        guard data[1] >> 4 == 2 else { return }
        let last = data[1] & 2 != 0
        if failAudio {
            for _ in 0..<2000 {
                if lock.withLock({ receiving }) { throw URLError(.networkConnectionLost) }
                try await Task.sleep(for: .milliseconds(1))
            }
            throw URLError(.timedOut)
        }
        let pcm = try Gzip.decompress(Data(data.dropFirst(8)))
        lock.withLock { bytes += pcm.count; finished = last }
        if !last && pcm.count == 6400 { onAudio() }
        continuation.yield(Self.response(last ? "整句最终结果" : "中间结果", last: last))
    }
    func receive() async throws -> Data {
        lock.withLock { receiving = true }
        var iterator = input.makeAsyncIterator()
        guard let data = try await iterator.next() else { throw CancellationError() }
        return data
    }
    func cancel() {
        lock.withLock { closed = true }
        continuation.finish(throwing: CancellationError())
    }
    private static func response(_ text: String, last: Bool) -> Data {
        let json = Data("{\"result\":{\"text\":\"\(text)\"}}".utf8)
        var result = Data([0x11, last ? 0x92 : 0x90, 0x10, 0])
        var size = UInt32(json.count).bigEndian
        withUnsafeBytes(of: &size) { result.append(contentsOf: $0) }
        result.append(json)
        return result
    }
}
