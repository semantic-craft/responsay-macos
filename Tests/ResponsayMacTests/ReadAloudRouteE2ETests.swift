import AVFoundation
import CoreAudio
import XCTest
import ResponsayCore
@testable import ResponsayMac

/// Human-operated output changes. Opt-in only; this test never writes audio routes.
@MainActor
final class ReadAloudRouteE2ETests: XCTestCase {
    func testHumanOutputChangesAcrossPlayingPausedAndStreaming() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_READ_ALOUD_ROUTE_E2E"] == "1")
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["READ_ALOUD_ROUTE_STATUS"])
        let engine = AVAudioEngine()
        let player = AudioReadAloudPlayer(engine: engine)
        defer { player.stop() }
        var failures: [String] = []
        player.onPlaybackFailure = { failures.append($0.localizedDescription) }
        let original = try outputDevice()
        let speech = Self.tone
        do {
            if ProcessInfo.processInfo.environment["READ_ALOUD_ROUTE_START"] != "streaming" {
                try player.play(ComposedReadAloud(chunks: [speech], timeline: [], totalDuration: speech.duration))
                try await wait(seconds: 5) { player.elapsed > 0.2 }
                if ProcessInfo.processInfo.environment["READ_ALOUD_ROUTE_START"] != "paused" {
                    var before = player.elapsed
                    try status("playing:ready", path: path)
                    try await wait(seconds: 180) {
                        if try self.outputDevice() != original { return true }
                        before = player.elapsed
                        return false
                    }
                    guard player.elapsed >= before - 0.05 else { throw RouteTestError.failed("Playback position reset during route change") }
                    try await wait(seconds: 5) { !failures.isEmpty || (engine.isRunning && player.elapsed > before + 0.3) }
                    guard failures.isEmpty else { throw RouteTestError.failed(failures.joined(separator: "; ")) }
                    try await Task.sleep(for: .seconds(1))
                    guard failures.isEmpty, engine.isRunning else { throw RouteTestError.failed("Playing recovery did not remain running") }
                    try status("playing:passed", path: path)
                }

                player.pause()
                let pausedAt = player.elapsed
                let pausedDevice = try outputDevice()
                try status("paused:ready", path: path)
                try await wait(seconds: 180) { try self.outputDevice() != pausedDevice }
                try await Task.sleep(for: .seconds(1))
                guard failures.isEmpty, abs(player.elapsed - pausedAt) < 0.02 else {
                    throw RouteTestError.failed("Paused state or position changed: \(failures)")
                }
                player.resume()
                try await wait(seconds: 5) { !failures.isEmpty || player.elapsed > pausedAt + 0.3 }
                guard failures.isEmpty else { throw RouteTestError.failed(failures.joined(separator: "; ")) }
                try status("paused:passed", path: path)
                player.stop()
                try await Task.sleep(for: .seconds(1))

            }
            let reader = ReadAloudDocumentReader(player: player)
            reader.coordinator = nil
            reader.makeSynthesizer = { (RouteToneSynthesizer(speech: speech), nil) }
            defer { reader.stop() }
            reader.read("Human route test for streaming playback and retry.")
            try await wait(seconds: 5) { reader.phase == .playing && player.elapsed > 0.2 }
            let streamingDevice = try outputDevice()
            try status("streaming:ready", path: path)
            try await wait(seconds: 180) { try self.outputDevice() != streamingDevice }
            try status("streaming:awaiting-failure", path: path)
            try await wait(seconds: 5) { reader.phase == .idle }
            guard reader.errorMessage != nil, reader.shouldShowControls, !engine.isRunning else {
                throw RouteTestError.failed("Streaming failure did not stop with visible retry state")
            }
            try await Task.sleep(for: .seconds(1))
            try status("streaming:retrying", path: path)
            reader.pauseOrResume()
            try await wait(seconds: 5) { reader.phase == .playing && player.elapsed > 0.3 }
            guard reader.errorMessage == nil else { throw RouteTestError.failed("Streaming retry kept an error") }
            try await Task.sleep(for: .seconds(2))
            try status("all:passed", path: path)
        } catch {
            try? status("failed:\(error.localizedDescription)", path: path)
            throw error
        }
    }

    private func status(_ value: String, path: String) throws {
        try value.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func outputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let result = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard result == noErr, device != 0 else { throw RouteTestError.failed("No valid default output device") }
        return device
    }

    private func wait(seconds: Double, until condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while try !condition() {
            guard Date() < deadline else { throw RouteTestError.failed("Timed out waiting for route/playback state") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static var tone: SynthesizedSpeech {
        let step = 2.0 * Double.pi * 440.0 / 24_000.0
        let samples: [Float] = (0..<2_880_000).map { Float(sin(Double($0) * step) * 0.04) }
        return SynthesizedSpeech(samples: samples, sampleRate: 24_000)
    }
}

private enum RouteTestError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let message) = self { return message }; return nil }
}

private struct RouteToneSynthesizer: SpeechSynthesizer {
    let speech: SynthesizedSpeech
    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech { speech }
}
