import AVFoundation
import ResponsayCore

extension AudioReadAloudPlayer {
    // MARK: - 482 sample-rate / format conversion

    struct ScheduledBuffers {
        let format: AVAudioFormat
        let buffers: [AVAudioPCMBuffer]
        let converted: Bool
        let converterFailed: Bool
        var totalFrames: Int { buffers.reduce(0) { $0 + Int($1.frameLength) } }
    }

    /// Convert the composed chunks to `outputRate` when it differs from the source rate,
    /// else return the source buffers (the engine resamples downstream). Any converter
    /// failure falls back to the source buffers so playback never breaks on conversion.
    static func makeScheduledBuffers(
        for composed: ComposedReadAloud,
        sourceFormat: AVAudioFormat,
        outputRate: Double
    ) throws -> ScheduledBuffers {
        guard outputRate.isFinite, outputRate > 0 else {
            throw TTSError.synthesisFailed("音频输出设备格式无效")
        }
        let sourceBuffers = composed.chunks.compactMap { Self.buffer(from: $0.samples, format: sourceFormat, allowingSilence: true) }
        guard sourceBuffers.count == composed.chunks.count, !sourceBuffers.isEmpty else {
            throw TTSError.synthesisFailed("无法准备剩余音频")
        }
        let sourceRate = sourceFormat.sampleRate
        guard outputRate.isFinite, outputRate > 0, abs(outputRate - sourceRate) > 1,
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: outputRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return ScheduledBuffers(
                format: sourceFormat, buffers: sourceBuffers, converted: false, converterFailed: false)
        }
        var converted: [AVAudioPCMBuffer] = []
        for src in sourceBuffers {
            guard let out = Self.convert(src, using: converter, to: targetFormat) else {
                return ScheduledBuffers(
                    format: sourceFormat, buffers: sourceBuffers, converted: false, converterFailed: true)
            }
            converted.append(out)
        }
        return ScheduledBuffers(
            format: targetFormat, buffers: converted, converted: true, converterFailed: false)
    }

    private static func convert(
        _ src: AVAudioPCMBuffer, using converter: AVAudioConverter, to target: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(ReadAloudResampling.outputFrameCount(
            sourceFrames: Int(src.frameLength),
            sourceRate: src.format.sampleRate,
            targetRate: target.sampleRate)) + 1024
        guard capacity > 0, let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if fed { inputStatus.pointee = .noDataNow; return nil }
            fed = true
            inputStatus.pointee = .haveData
            return src
        }
        guard status != .error, error == nil, out.frameLength > 0 else { return nil }
        return out
    }

    static func buffer(
        from samples: [Float], format: AVAudioFormat, allowingSilence: Bool = false
    ) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              samples.allSatisfy(\.isFinite),
              allowingSilence || samples.contains(where: { $0 != 0 }),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData else { return nil }
        samples.withUnsafeBufferPointer { src in
            channel[0].update(from: src.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard buffer.frameLength > 0 else { return nil }
        return buffer
    }

}
