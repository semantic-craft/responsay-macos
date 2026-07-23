import Foundation
import OSLog

/// Tuning for the chunked downloader. The defaults mirror openless's
/// `download.rs` (8MB chunks, a handful of concurrent workers, 4 retries):
/// short-lived per-chunk connections so a CDN/proxy can't throttle or kick a
/// single long-lived transfer mid-stream — the cause of the "stuck at 100%"
/// hang when pulling an 800MB+ model through a 国内 GitHub proxy.
struct ChunkDownloadConfig: Sendable {
    var chunkSize: Int64 = 8 << 20
    var maxConcurrent = 6
    var perChunkAttempts = 4
}

enum ChunkDownloadError: Error, CustomStringConvertible {
    /// Server ignored the `Range` header (returned 200/full, not 206).
    case rangeNotHonored(status: Int)
    case wrongChunkLength(expected: Int, got: Int)
    case chunkFailed(index: Int, lastError: String)

    var description: String {
        switch self {
        case .rangeNotHonored(let s): "服务端未按分块返回（HTTP \(s)）"
        case .wrongChunkLength(let e, let g): "分块长度 \(g) 与预期 \(e) 不符"
        case .chunkFailed(let i, let e): "分块 \(i) 多次重试仍失败：\(e)"
        }
    }
}

/// Serializes resume-index appends + progress accounting across the concurrent
/// chunk workers (the only shared mutable state; the file-data writes themselves
/// hit disjoint offsets and need no lock).
private actor ChunkRecorder {
    private let idxURL: URL
    private var bytes: Int64
    private let total: Int64
    private let onProgress: @Sendable (Double) -> Void

    init(idxURL: URL, bytesDone: Int64, total: Int64,
         onProgress: @escaping @Sendable (Double) -> Void) {
        self.idxURL = idxURL
        self.bytes = bytesDone
        self.total = total
        self.onProgress = onProgress
    }

    func mark(_ index: Int, length: Int) {
        bytes += Int64(length)
        if let handle = try? FileHandle(forWritingTo: idxURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("\(index)\n".utf8))
        }
        onProgress(total > 0 ? min(1, Double(bytes) / Double(total)) : 0)
    }
}

/// Downloads a single file via concurrent HTTP `Range` requests, writing each
/// chunk to its offset in a sparse `<dest>.partial` and recording completed
/// chunk indices in `<dest>.partial.idx`. Re-invoking with the same `dest`
/// resumes — only missing chunks are fetched. On full completion the partial is
/// renamed to `dest`. Honors task cancellation at chunk boundaries.
enum ChunkedRangeDownloader {
    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "chunked-download")

    static func partialURL(for dest: URL) -> URL { dest.appendingPathExtension("partial") }
    static func idxURL(for dest: URL) -> URL { dest.appendingPathExtension("partial.idx") }

    /// Completed chunk indices recorded so far (one decimal per line).
    static func readIndex(_ url: URL) -> Set<Int> {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(s.split(whereSeparator: \.isNewline).compactMap { Int($0) })
    }

    static func chunkLength(index: Int, chunkSize: Int64, total: Int64) -> Int {
        let start = Int64(index) * chunkSize
        return Int(max(0, min(chunkSize, total - start)))
    }

    static func download(
        from url: URL, to dest: URL, expectedSize: Int64,
        config: ChunkDownloadConfig = .init(),
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let fm = FileManager.default
        let partial = partialURL(for: dest)
        let idx = idxURL(for: dest)
        try fm.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        let chunkCount = max(1, Int((expectedSize + config.chunkSize - 1) / config.chunkSize))

        // Reuse a partial only if it's the right size; otherwise the asset/URL
        // changed and stale chunks would corrupt the result — start fresh.
        let partialSize = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map(Int64.init)
        var done = readIndex(idx).filter { $0 >= 0 && $0 < chunkCount }
        if !fm.fileExists(atPath: partial.path) || partialSize != expectedSize {
            try? fm.removeItem(at: partial)
            try? fm.removeItem(at: idx)
            fm.createFile(atPath: partial.path, contents: nil)
            let handle = try FileHandle(forWritingTo: partial)
            try handle.truncate(atOffset: UInt64(expectedSize))
            try handle.close()
            done = []
        }

        let bytesDone = done.reduce(Int64(0)) {
            $0 + Int64(chunkLength(index: $1, chunkSize: config.chunkSize, total: expectedSize))
        }
        onProgress(expectedSize > 0 ? min(1, Double(bytesDone) / Double(expectedSize)) : 0)

        let remaining = (0..<chunkCount).filter { !done.contains($0) }
        if remaining.isEmpty {
            try finalize(partial: partial, dest: dest, idx: idx)
            return
        }

        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 60     // a stalled chunk dies fast, then retries
            c.timeoutIntervalForResource = 600
            c.waitsForConnectivity = true
            return c
        }())
        defer { session.finishTasksAndInvalidate() }

        let recorder = ChunkRecorder(
            idxURL: idx, bytesDone: bytesDone, total: expectedSize, onProgress: onProgress)
        let chunkSize = config.chunkSize
        let attempts = config.perChunkAttempts

        @Sendable func fetchChunk(_ i: Int) async throws {
            let start = Int64(i) * chunkSize
            let len = chunkLength(index: i, chunkSize: chunkSize, total: expectedSize)
            let end = start + Int64(len) - 1
            var lastError = "unknown"
            for attempt in 0..<attempts {
                try Task.checkCancellation()
                do {
                    var req = URLRequest(url: url)
                    req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                    req.setValue("aria2/1.36.0", forHTTPHeaderField: "User-Agent")
                    let (data, resp) = try await session.data(for: req)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 206 else { throw ChunkDownloadError.rangeNotHonored(status: status) }
                    guard data.count == len else {
                        throw ChunkDownloadError.wrongChunkLength(expected: len, got: data.count)
                    }
                    let handle = try FileHandle(forWritingTo: partial)
                    defer { try? handle.close() }
                    try handle.seek(toOffset: UInt64(start))
                    try handle.write(contentsOf: data)
                    await recorder.mark(i, length: len)
                    return
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = String(describing: error)
                    if attempt < attempts - 1 {
                        // 0.25s, 1s, 4s exponential backoff.
                        try? await Task.sleep(nanoseconds: UInt64(pow(4.0, Double(attempt)) * 250_000_000))
                    }
                }
            }
            throw ChunkDownloadError.chunkFailed(index: i, lastError: lastError)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            var it = remaining.makeIterator()
            for _ in 0..<min(config.maxConcurrent, remaining.count) {
                if let i = it.next() { group.addTask { try await fetchChunk(i) } }
            }
            while try await group.next() != nil {
                try Task.checkCancellation()
                if let i = it.next() { group.addTask { try await fetchChunk(i) } }
            }
        }
        try finalize(partial: partial, dest: dest, idx: idx)
        Self.log.info("chunked download complete: \(dest.lastPathComponent, privacy: .public)")
    }

    private static func finalize(partial: URL, dest: URL, idx: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: partial, to: dest)
        try? fm.removeItem(at: idx)
    }

    /// Discard a partial + its index (e.g. after a checksum failure poisons it).
    static func clearPartial(for dest: URL) {
        try? FileManager.default.removeItem(at: partialURL(for: dest))
        try? FileManager.default.removeItem(at: idxURL(for: dest))
    }
}
