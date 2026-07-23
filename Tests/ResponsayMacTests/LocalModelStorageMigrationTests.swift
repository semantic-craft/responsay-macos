import XCTest
@testable import ResponsayMac

final class LocalModelStorageMigrationTests: XCTestCase {
    private let fm = FileManager.default

    private func makeTempDir() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("rsy-mig-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testHasEnoughSpace() throws {
        let dir = try makeTempDir()
        XCTAssertTrue(LocalModelStorageMigration.hasEnoughSpace(forBytes: 1_000, at: dir))
        XCTAssertFalse(
            LocalModelStorageMigration.hasEnoughSpace(forBytes: Int64.max / 2, at: dir))
    }

    func testDirectorySize() throws {
        let dir = try makeTempDir()
        try Data(repeating: 0, count: 1_000).write(to: dir.appendingPathComponent("a.bin"))
        try Data(repeating: 0, count: 2_500).write(to: dir.appendingPathComponent("b.bin"))
        XCTAssertEqual(LocalModelStorageMigration.directorySize(dir), 3_500)
    }

    func testCopyChecksummedRoundTrip() throws {
        let root = try makeTempDir()
        let src = root.appendingPathComponent("model", isDirectory: true)
        try fm.createDirectory(at: src.appendingPathComponent("test_wavs"), withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: src.appendingPathComponent("model.int8.onnx"))
        try Data("tok".utf8).write(to: src.appendingPathComponent("tokens.txt"))
        try Data("RIFF".utf8).write(to: src.appendingPathComponent("test_wavs/zh.wav"))

        let dst = root.appendingPathComponent("dest/model", isDirectory: true)
        try LocalModelStorageMigration.copyChecksummed(from: src, to: dst)

        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("model.int8.onnx").path))
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("tokens.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("test_wavs/zh.wav").path))
        XCTAssertEqual(
            try LocalModelDownloader.sha256Hex(of: src.appendingPathComponent("model.int8.onnx")),
            try LocalModelDownloader.sha256Hex(of: dst.appendingPathComponent("model.int8.onnx")))
    }

    func testDeleteOldRemovesDirectories() throws {
        let oldRoot = try makeTempDir()
        let spec = LocalModelRegistry.defaultASR
        let dir = oldRoot.appendingPathComponent(spec.directoryName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("model.int8.onnx"))

        try LocalModelStorageMigration.deleteOld(at: oldRoot, specs: [spec])
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
    }

    func testMigrateWithNothingInstalledThrows() async {
        // A spec whose directory never exists on disk → nothingToMigrate.
        let ghost = LocalModelSpec(
            id: "test-ghost", displayName: "Ghost", capability: .asr,
            runtime: .sherpaOnnx, family: .senseVoice, languages: ["zh"],
            qualityTier: "test", directoryName: "never-installed-\(UUID().uuidString)",
            expected: ExpectedMetrics(asrRealtimeFactor: nil, approxDiskBytes: 1),
            download: nil)
        let dir = (try? makeTempDir()) ?? fm.temporaryDirectory
        do {
            _ = try await LocalModelStorageMigration.migrate(
                specs: [ghost], to: dir)
            XCTFail("expected nothingToMigrate")
        } catch let error as StorageMigrationError {
            if case .nothingToMigrate = error { /* ok */ } else {
                XCTFail("unexpected: \(error)")
            }
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}
