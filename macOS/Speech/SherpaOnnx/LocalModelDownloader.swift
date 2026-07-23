import CryptoKit
import Foundation
import OSLog

/// Downloads, verifies, and extracts a local model archive into Application
/// Support — fully native (URLSession + CryptoKit + /usr/bin/tar), no backend.
/// Mirrors the openless `download`/`sherpa_download` flow (GitHub release asset +
/// sha256 + mirror fallback), adapted to Swift.
enum LocalModelDownloader {
    enum Phase: Sendable, Equatable {
        case downloading(Double)   // 0...1
        case verifying
        case extracting
    }

    enum Failure: Error, CustomStringConvertible {
        case allSourcesFailed(String)
        case checksumMismatch(expected: String, actual: String)
        case extractionFailed(String)
        case missingAfterExtract
        case insufficientDiskSpace(neededBytes: Int64, freeBytes: Int64)

        var description: String {
            switch self {
            case .allSourcesFailed(let why): "下载失败：\(why)"
            case .checksumMismatch: "校验失败：下载内容与预期不符,请重试。"
            case .extractionFailed(let why): "解压失败：\(why)"
            case .missingAfterExtract: "解压后未找到模型文件。"
            case .insufficientDiskSpace(let needed, let free):
                "磁盘空间不足：需要约 \(Self.bytes(needed))，可用 \(Self.bytes(free))。"
            }
        }

        private static func bytes(_ count: Int64) -> String {
            ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
        }
    }

    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "model-download")

    /// Order the candidate URLs by the user's 下载镜像 choice (`localMirror`):
    /// the default `"hf"` keeps GitHub-direct first; any 国内 choice tries the
    /// `gh-proxy` / mirror links first so it doesn't stall on a GitHub timeout.
    /// (Was the orphaned write-only setting — now actually consumed.)
    static func orderedURLs(_ urls: [URL]) -> [URL] {
        let mirror = UserDefaults.standard.string(forKey: "localMirror") ?? "hf"
        guard mirror != "hf", urls.count > 1 else { return urls }
        func isProxy(_ u: URL) -> Bool {
            let host = u.host ?? ""
            return host.contains("gh-proxy") || host.contains("ghfast")
                || host.contains("mirror") || host.contains("modelscope")
        }
        return urls.filter(isProxy) + urls.filter { !isProxy($0) }
    }

    /// Disk headroom multiplier: archive + extracted copy + scratch.
    private static let diskHeadroomFactor = 2.5

    /// Throws `.insufficientDiskSpace` when the models volume lacks room for the
    /// archive plus its extracted copy. `freeBytesOverride` is for tests only.
    static func preflightDiskSpace(
        byteSize: Int64, at root: URL = SenseVoiceModel.modelsRoot,
        freeBytesOverride: Int64? = nil
    ) throws {
        let needed = Int64(Double(byteSize) * diskHeadroomFactor)
        let free: Int64
        if let freeBytesOverride {
            free = freeBytesOverride
        } else {
            // The models root may not exist before the first install; probe the
            // nearest existing ancestor so the volume query cannot throw ENOENT.
            var probe = root
            let fm = FileManager.default
            while !fm.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
                probe = probe.deletingLastPathComponent()
            }
            let values = try? probe.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            guard let capacity = values?.volumeAvailableCapacityForImportantUsage else {
                return  // Cannot determine free space — do not block the download.
            }
            free = capacity
        }
        guard free >= needed else {
            throw Failure.insufficientDiskSpace(neededBytes: needed, freeBytes: free)
        }
    }

    /// Download → verify sha256 → extract → atomically install. Honors cancellation.
    static func install(
        _ spec: LocalModelSpec,
        onPhase: @escaping @Sendable (Phase) -> Void
    ) async throws {
        guard let source = spec.download else {
            throw Failure.allSourcesFailed("\(spec.id) 暂不支持应用内下载")
        }
        try preflightDiskSpace(byteSize: source.byteSize)
        if !source.files.isEmpty {
            try await installFiles(spec, source: source, onPhase: onPhase)
            return
        }
        let fm = FileManager.default
        let tmpDir = try fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: SenseVoiceModel.modelsRoot, create: true)
        defer { try? fm.removeItem(at: tmpDir) }
        // The archive downloads to a *persistent* per-spec path under `.resume/`
        // so an interrupted 800MB+ transfer resumes on the next click / relaunch
        // — the chunked downloader keeps completed-chunk state beside it. Only
        // the extraction scratch lives in the throwaway tmpDir.
        let archive = persistentArchiveURL(for: spec)

        var lastError = "unknown"
        var ok = false
        // Chunked HTTP Range download (8MB chunks, concurrent, per-chunk retry):
        // short-lived connections so a CDN / 国内代理 can't throttle or kick a
        // single long transfer mid-stream — the "stuck at 100%" failure on big
        // models like Qwen3-ASR.
        for url in orderedURLs(source.urls) {
            do {
                try await ChunkedRangeDownloader.download(
                    from: url, to: archive, expectedSize: source.byteSize
                ) { frac in onPhase(.downloading(frac)) }
                ok = true
                break
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = String(describing: error)
                log.warning("source failed \(url.host ?? "?", privacy: .public): \(lastError, privacy: .public)")
            }
        }
        guard ok else { throw Failure.allSourcesFailed(lastError) }

        try Task.checkCancellation()
        onPhase(.verifying)
        let actual = try sha256Hex(of: archive)
        guard actual == source.sha256.lowercased() else {
            // Corrupt bytes must not poison resume — drop the archive + partial
            // so the next attempt re-fetches cleanly.
            try? fm.removeItem(at: archive)
            ChunkedRangeDownloader.clearPartial(for: archive)
            throw Failure.checksumMismatch(expected: source.sha256.lowercased(), actual: actual)
        }

        try Task.checkCancellation()
        onPhase(.extracting)
        let extractDir = tmpDir.appendingPathComponent("extract", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try extractTarBz2(archive, into: extractDir)

        let extracted = extractDir.appendingPathComponent(spec.directoryName, isDirectory: true)
        guard fm.fileExists(atPath: extracted.path) else { throw Failure.missingAfterExtract }

        try fm.createDirectory(at: SenseVoiceModel.modelsRoot, withIntermediateDirectories: true)
        try replaceItem(at: spec.storagePath, withItemAt: extracted)
        guard spec.isInstalled else { throw Failure.missingAfterExtract }
        try? fm.removeItem(at: archive)  // installed — the cached archive is done
        log.info("installed model \(spec.id, privacy: .public)")
    }

    /// Download a model whose official distribution is several loose files rather than one archive.
    private static func installFiles(
        _ spec: LocalModelSpec,
        source: DownloadSource,
        onPhase: @escaping @Sendable (Phase) -> Void
    ) async throws {
        let fm = FileManager.default
        let tmpDir = try fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: SenseVoiceModel.modelsRoot, create: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let staged = tmpDir.appendingPathComponent(spec.directoryName, isDirectory: true)
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)

        var completedBytes: Int64 = 0
        for file in source.files {
            let baseCompletedBytes = completedBytes
            let cached = persistentFileURL(for: spec, file: file)
            var lastError = "unknown"
            var ok = false
            for url in orderedURLs(file.urls) {
                do {
                    try await ChunkedRangeDownloader.download(
                        from: url, to: cached, expectedSize: file.byteSize
                    ) { fraction in
                        let done = Double(baseCompletedBytes) + Double(file.byteSize) * fraction
                        onPhase(.downloading(done / Double(source.byteSize)))
                    }
                    ok = true
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = String(describing: error)
                    log.warning("source failed \(url.host ?? "?", privacy: .public): \(lastError, privacy: .public)")
                }
            }
            guard ok else { throw Failure.allSourcesFailed(lastError) }

            try Task.checkCancellation()
            onPhase(.verifying)
            let actual = try sha256Hex(of: cached)
            guard actual == file.sha256.lowercased() else {
                try? fm.removeItem(at: cached)
                ChunkedRangeDownloader.clearPartial(for: cached)
                throw Failure.checksumMismatch(expected: file.sha256.lowercased(), actual: actual)
            }

            let dest = staged.appendingPathComponent(file.relativePath)
            try fm.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: cached, to: dest)
            completedBytes += file.byteSize
        }

        try Task.checkCancellation()
        onPhase(.extracting)
        try fm.createDirectory(at: SenseVoiceModel.modelsRoot, withIntermediateDirectories: true)
        try replaceItem(at: spec.storagePath, withItemAt: staged)
        guard spec.isInstalled else { throw Failure.missingAfterExtract }
        for file in source.files {
            let cached = persistentFileURL(for: spec, file: file)
            try? fm.removeItem(at: cached)
            ChunkedRangeDownloader.clearPartial(for: cached)
        }
        log.info("installed model \(spec.id, privacy: .public)")
    }

    /// Move a freshly extracted model directory onto `dest`, first clearing
    /// whatever already occupies that path. Crucially this removes a **dangling
    /// symlink** too: `FileManager.fileExists(atPath:)` *follows* the link, so a
    /// broken link reports `false` and the old guard left it in place — then
    /// `moveItem` failed with POSIX 17 "File exists" and every re-download
    /// failed the same way. `attributesOfItem` is lstat-based (sees the link
    /// itself), and `removeItem` unlinks it. Regression: a leftover dev symlink
    /// pointing a model dir into wiped `/tmp` stranded Qwen3-ASR re-installs.
    static func replaceItem(at dest: URL, withItemAt source: URL) throws {
        let fm = FileManager.default
        if (try? fm.attributesOfItem(atPath: dest.path)) != nil {
            try fm.removeItem(at: dest)
        }
        try fm.moveItem(at: source, to: dest)
    }

    /// Remove an installed model directory.
    static func remove(_ spec: LocalModelSpec) throws {
        let dir = spec.storagePath
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - Persistent archive (interrupted downloads resume across relaunch)

    /// Where the in-flight model archive lives so a large download resumes across
    /// clicks/relaunches — its `.partial` + `.partial.idx` sit beside it. A
    /// hidden `.resume/` dir keyed by spec id.
    static func persistentArchiveURL(
        for spec: LocalModelSpec, root: URL = SenseVoiceModel.modelsRoot
    ) -> URL {
        root.appendingPathComponent(".resume", isDirectory: true)
            .appendingPathComponent("\(spec.id).tar.bz2")
    }

    static func persistentFileURL(
        for spec: LocalModelSpec,
        file: DownloadFile,
        root: URL = SenseVoiceModel.modelsRoot
    ) -> URL {
        let name = file.relativePath.replacingOccurrences(of: "/", with: "__")
        return root.appendingPathComponent(".resume", isDirectory: true)
            .appendingPathComponent("\(spec.id)-\(name)")
    }

    // MARK: - Verify

    /// Streaming sha256 (lowercase hex) so a 150MB+ file never loads fully in RAM.
    static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while case let chunk = handle.readData(ofLength: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Extract

    static func extractTarBz2(_ archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archive.path, "-C", directory.path]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Failure.extractionFailed(msg.isEmpty ? "tar exit \(process.terminationStatus)" : msg)
        }
    }
}
