import AVFoundation
import XCTest
@testable import ResponsayMac

final class LocalModelDownloaderTests: XCTestCase {
    private let fm = FileManager.default

    private func makeTempDir() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("rsy-dl-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testSha256MatchesKnownValue() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("hello.txt")
        try Data("hello".utf8).write(to: file)
        // sha256("hello") — canonical.
        XCTAssertEqual(
            try LocalModelDownloader.sha256Hex(of: file),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    func testExtractTarBz2RoundTrip() throws {
        let dir = try makeTempDir()
        // Build a small folder, tar.bz2 it, then extract via the downloader.
        let payload = dir.appendingPathComponent("payload", isDirectory: true)
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data("model bytes".utf8).write(to: payload.appendingPathComponent("model.int8.onnx"))
        try Data("<tokens>".utf8).write(to: payload.appendingPathComponent("tokens.txt"))

        let archive = dir.appendingPathComponent("p.tar.bz2")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-cjf", archive.path, "-C", dir.path, "payload"]
        try tar.run(); tar.waitUntilExit()
        XCTAssertEqual(tar.terminationStatus, 0)

        let out = dir.appendingPathComponent("out", isDirectory: true)
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        try LocalModelDownloader.extractTarBz2(archive, into: out)
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("payload/model.int8.onnx").path))
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("payload/tokens.txt").path))
    }

    func testSpecPointsAtKnownAsset() throws {
        let spec = LocalModelRegistry.defaultASR
        let source = try XCTUnwrap(spec.download)
        XCTAssertEqual(source.sha256.count, 64)
        XCTAssertGreaterThan(source.byteSize, 100_000_000)
        XCTAssertEqual(spec.directoryName, SenseVoiceModel.directoryName)
        XCTAssertFalse(source.urls.isEmpty)
        XCTAssertTrue(source.urls[0].absoluteString.hasSuffix(".tar.bz2"))
    }

    /// Real network install of the actual SenseVoice model, then transcribe.
    /// Off by default (downloads ~158MB). Run with RUN_NETWORK_TESTS=1.
    func testRealInstallAndTranscribe() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_NETWORK_TESTS"] == "1",
            "network install test disabled (set RUN_NETWORK_TESTS=1 to run)")
        let spec = LocalModelRegistry.defaultASR
        try? LocalModelDownloader.remove(spec)
        try await LocalModelDownloader.install(spec) { _ in }
        XCTAssertTrue(spec.isInstalled, "model not installed after download")

        let recognizer = try SenseVoiceModel.loadRecognizer()
        let wav = spec.storagePath.appendingPathComponent("test_wavs/zh.wav")
        let file = try AVAudioFile(forReading: wav)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData)
        let samples = Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
        let result = try recognizer.transcribe(samples: samples)
        print("real-install SenseVoice zh.wav → \(result.text)")
        XCTAssertTrue(result.text.contains("时间"), "unexpected transcript: \(result.text)")
    }

    // MARK: - Destination replacement (dangling-symlink regression)

    /// Repro of the field bug: a leftover dev symlink pointed a model dir at a
    /// since-wiped /tmp path. `fileExists` follows symlinks, so the broken link
    /// was invisible to the old clear-guard and `moveItem` failed with "File
    /// exists" on every re-download. The installer must clear a dangling symlink
    /// at the destination before moving the fresh model into place.
    func testReplaceItemClearsDanglingSymlinkDestination() throws {
        let dir = try makeTempDir()
        let dest = dir.appendingPathComponent("model-dir")
        let deadTarget = dir.appendingPathComponent("gone-\(UUID().uuidString)/model-dir")
        try fm.createSymbolicLink(at: dest, withDestinationURL: deadTarget)
        // fileExists follows the link → blind to the dangling symlink…
        XCTAssertFalse(fm.fileExists(atPath: dest.path))
        // …while lstat-based attributesOfItem sees the link itself.
        XCTAssertNotNil(try? fm.attributesOfItem(atPath: dest.path))

        let extracted = dir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: extracted.appendingPathComponent("encoder.int8.onnx"))

        try LocalModelDownloader.replaceItem(at: dest, withItemAt: extracted)

        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("encoder.int8.onnx").path))
        XCTAssertNil(
            try? fm.destinationOfSymbolicLink(atPath: dest.path),
            "stale symlink should be replaced by a real directory")
    }

    /// The same clear-then-move must still work for an absent destination and
    /// for a real pre-existing directory (the ordinary re-download case).
    func testReplaceItemHandlesAbsentAndRealDestinations() throws {
        let dir = try makeTempDir()
        func extracted(_ name: String) throws -> URL {
            let u = dir.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: u, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: u.appendingPathComponent("encoder.int8.onnx"))
            return u
        }
        let absent = dir.appendingPathComponent("absent")
        try LocalModelDownloader.replaceItem(at: absent, withItemAt: extracted("ex1"))
        XCTAssertTrue(fm.fileExists(atPath: absent.appendingPathComponent("encoder.int8.onnx").path))

        let real = try extracted("real-existing")
        try LocalModelDownloader.replaceItem(at: real, withItemAt: extracted("ex2"))
        XCTAssertTrue(fm.fileExists(atPath: real.appendingPathComponent("encoder.int8.onnx").path))
    }

    // MARK: - Disk preflight (audit area 6)

    func testPreflightPassesWithEnoughFreeSpace() throws {
        // 100 MB archive needs 250 MB headroom; 1 GB free passes.
        XCTAssertNoThrow(try LocalModelDownloader.preflightDiskSpace(
            byteSize: 100_000_000, freeBytesOverride: 1_000_000_000))
    }

    func testPreflightThrowsWhenDiskTooFull() {
        XCTAssertThrowsError(try LocalModelDownloader.preflightDiskSpace(
            byteSize: 878_702_423, freeBytesOverride: 500_000_000)
        ) { error in
            guard case LocalModelDownloader.Failure.insufficientDiskSpace(let needed, let free) = error else {
                return XCTFail("expected insufficientDiskSpace, got \(error)")
            }
            XCTAssertGreaterThan(needed, 878_702_423)  // includes extraction headroom
            XCTAssertEqual(free, 500_000_000)
            // The user-facing message must explain itself in Chinese.
            XCTAssertTrue("\(error)".contains("磁盘空间不足"))
        }
    }

    func testPreflightAgainstRealVolumePasses() throws {
        // Tiny ask against the real dev volume — exercises the live capacity
        // query path (incl. the nearest-existing-ancestor probe).
        let dir = try makeTempDir()
        XCTAssertNoThrow(try LocalModelDownloader.preflightDiskSpace(
            byteSize: 1_000, at: dir.appendingPathComponent("not-created-yet")))
    }

    // MARK: - Persistent archive path (chunked-download resume across relaunch)

    func testPersistentArchivePathIsKeyedBySpecInResumeDir() throws {
        let root = try makeTempDir()
        let spec = LocalModelRegistry.defaultASR
        let url = LocalModelDownloader.persistentArchiveURL(for: spec, root: root)
        // Lives in the hidden `.resume/` dir, keyed by spec id, ending .tar.bz2 so
        // its `.partial`/`.partial.idx` siblings drive cross-relaunch resume.
        XCTAssertTrue(url.path.contains("/.resume/"))
        XCTAssertTrue(url.lastPathComponent.hasPrefix(spec.id))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".tar.bz2"))
    }

    // MARK: - Chunked Range downloader (qwen3 "stuck at 100%" fix)

    func testChunkLengthCoversWholeFileWithSmallTail() {
        // 20 MB over 8 MB chunks → 8 + 8 + 4; lengths must sum to the total.
        let total: Int64 = 20 << 20
        let chunk: Int64 = 8 << 20
        let count = Int((total + chunk - 1) / chunk)
        XCTAssertEqual(count, 3)
        let lens = (0..<count).map {
            ChunkedRangeDownloader.chunkLength(index: $0, chunkSize: chunk, total: total)
        }
        XCTAssertEqual(lens, [8 << 20, 8 << 20, 4 << 20])
        XCTAssertEqual(lens.reduce(0, +), Int(total))
    }

    func testChunkIndexNamingAndRoundTrip() throws {
        let dir = try makeTempDir()
        let dest = dir.appendingPathComponent("model.tar.bz2")
        XCTAssertEqual(
            LocalModelDownloader.persistentArchiveURL(for: LocalModelRegistry.defaultASR, root: dir)
                .pathExtension, "bz2")
        XCTAssertEqual(ChunkedRangeDownloader.partialURL(for: dest).lastPathComponent,
                       "model.tar.bz2.partial")
        XCTAssertEqual(ChunkedRangeDownloader.idxURL(for: dest).lastPathComponent,
                       "model.tar.bz2.partial.idx")

        // Completed-chunk index parses back (resume reads only finished chunks).
        let idx = ChunkedRangeDownloader.idxURL(for: dest)
        try Data("0\n2\n5\n".utf8).write(to: idx)
        XCTAssertEqual(ChunkedRangeDownloader.readIndex(idx), [0, 2, 5])
        // Missing/garbage index → empty set, never a crash.
        XCTAssertEqual(ChunkedRangeDownloader.readIndex(dir.appendingPathComponent("nope")), [])
    }

    /// Real chunked install of the actual SenseVoice model end-to-end. Off by
    /// default (downloads ~158MB). Run with RUN_NETWORK_TESTS=1.
    func testChunkedRealInstall() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_NETWORK_TESTS"] == "1",
            "network install test disabled (set RUN_NETWORK_TESTS=1 to run)")
        let spec = LocalModelRegistry.defaultASR
        try? LocalModelDownloader.remove(spec)
        let lastFraction = ProgressHolder()
        try await LocalModelDownloader.install(spec) { phase in
            if case .downloading(let f) = phase { lastFraction.setFraction(f) }
        }
        XCTAssertEqual(lastFraction.fraction, 1.0, accuracy: 0.0001)
        XCTAssertTrue(spec.isInstalled, "model not installed after chunked download")
    }

    // MARK: - Mirror ordering (audit area 6)

    func testGhfastCountsAsChinaProxy() {
        let urls = [
            URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/a/m.tar.bz2")!,
            URL(string: "https://gh-proxy.com/https://github.com/k2-fsa/x/m.tar.bz2")!,
            URL(string: "https://ghfast.top/https://github.com/k2-fsa/x/m.tar.bz2")!,
        ]
        UserDefaults.standard.set("cnproxy", forKey: "localMirror")
        defer { UserDefaults.standard.removeObject(forKey: "localMirror") }
        let ordered = LocalModelDownloader.orderedURLs(urls)
        XCTAssertEqual(ordered.first?.host, "gh-proxy.com")
        XCTAssertEqual(ordered[1].host, "ghfast.top")
        XCTAssertEqual(ordered.last?.host, "github.com")
    }

    func testEveryDownloadableSpecHasTwoChinaProxies() {
        // Redundancy guard: a single community proxy outage must not strand
        // 国内 users (audit area 6 finding F3).
        for spec in LocalModelRegistry.downloadable {
            guard let download = spec.download else { continue }
            if download.files.isEmpty {
                let hosts = download.urls.compactMap(\.host)
                XCTAssertTrue(hosts.contains("gh-proxy.com"), "\(spec.id) missing gh-proxy")
                XCTAssertTrue(hosts.contains("ghfast.top"), "\(spec.id) missing ghfast")
            } else {
                for file in download.files {
                    let hosts = file.urls.compactMap(\.host)
                    XCTAssertTrue(hosts.contains("hf-mirror.com"), "\(spec.id)/\(file.relativePath) missing hf-mirror")
                    XCTAssertTrue(hosts.contains("modelscope.cn"), "\(spec.id)/\(file.relativePath) missing modelscope")
                }
            }
        }
    }
}

private final class ProgressHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _fraction = 0.0
    var fraction: Double {
        lock.lock()
        defer { lock.unlock() }
        return _fraction
    }
    func setFraction(_ value: Double) {
        lock.lock()
        _fraction = value
        lock.unlock()
    }
}
