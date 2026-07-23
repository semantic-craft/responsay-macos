import Foundation

enum StorageMigrationError: Error, CustomStringConvertible {
    case nothingToMigrate
    case insufficientSpace(neededBytes: Int64, availableBytes: Int64)
    case copyChecksumMismatch(String)
    case loadTestFailed(String)

    var description: String {
        switch self {
        case .nothingToMigrate: "没有已安装的模型可迁移。"
        case .insufficientSpace(let need, let have):
            "目标磁盘空间不足：需要约 \(ByteCountFormatter.string(fromByteCount: need, countStyle: .file))," +
            "可用 \(ByteCountFormatter.string(fromByteCount: have, countStyle: .file))。"
        case .copyChecksumMismatch(let f): "复制校验失败：\(f)"
        case .loadTestFailed(let why): "新位置加载测试未通过,已回退：\(why)"
        }
    }
}

/// Move local model storage to another directory safely (issue 163):
/// space check → checksummed copy → load-test gate → switch only on pass.
/// Deleting the old copies is a separate, explicitly-confirmed step.
enum LocalModelStorageMigration {
    /// Free space available for important usage at `url`'s volume.
    static func availableSpace(at url: URL) -> Int64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    static func hasEnoughSpace(
        forBytes needed: Int64, at dir: URL, marginBytes: Int64 = 200_000_000
    ) -> Bool {
        guard let available = availableSpace(at: dir) else { return false }
        return available >= needed + marginBytes
    }

    static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let files = fm.subpaths(atPath: url.path) else { return 0 }
        return files.reduce(0) { total, rel in
            let attrs = try? fm.attributesOfItem(atPath: url.appendingPathComponent(rel).path)
            return total + Int64((attrs?[.size] as? UInt64) ?? 0)
        }
    }

    /// Copy a model directory and verify every file's sha256 matches the source.
    static func copyChecksummed(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        try fm.createDirectory(
            at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: src, to: dst)
        for rel in fm.subpaths(atPath: src.path) ?? [] {
            let source = src.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: source.path, isDirectory: &isDir)
            if isDir.boolValue { continue }
            let destFile = dst.appendingPathComponent(rel)
            guard try LocalModelDownloader.sha256Hex(of: source)
                == LocalModelDownloader.sha256Hex(of: destFile)
            else { throw StorageMigrationError.copyChecksumMismatch(rel) }
        }
    }

    /// Copy installed models to `newRoot`, verify, load-test, then switch the
    /// active storage root. Reverts the switch if the load test fails. Old files
    /// stay until `deleteOld` is called with the user's confirmation.
    static func migrate(specs: [LocalModelSpec], to newRoot: URL) async throws -> URL {
        let installed = specs.filter(\.isInstalled)
        guard !installed.isEmpty else { throw StorageMigrationError.nothingToMigrate }

        let needed = installed.reduce(Int64(0)) { $0 + directorySize($1.storagePath) }
        guard hasEnoughSpace(forBytes: needed, at: newRoot) else {
            throw StorageMigrationError.insufficientSpace(
                neededBytes: needed, availableBytes: availableSpace(at: newRoot) ?? 0)
        }
        try FileManager.default.createDirectory(
            at: newRoot, withIntermediateDirectories: true)
        let oldRoot = SenseVoiceModel.modelsRoot
        for spec in installed {
            try copyChecksummed(
                from: spec.storagePath,
                to: newRoot.appendingPathComponent(spec.directoryName, isDirectory: true))
        }

        // Switch, then gate on a real load test; revert on failure.
        let previous = UserDefaults.standard.string(forKey: SenseVoiceModel.storageOverrideKey)
        UserDefaults.standard.set(newRoot.path, forKey: SenseVoiceModel.storageOverrideKey)
        do {
            for spec in installed where spec.family == .senseVoice {
                _ = try LocalModelSelfCheck.runASR(spec)
            }
        } catch {
            if let previous {
                UserDefaults.standard.set(previous, forKey: SenseVoiceModel.storageOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: SenseVoiceModel.storageOverrideKey)
            }
            throw StorageMigrationError.loadTestFailed(String(describing: error))
        }
        return oldRoot
    }

    /// Delete the old model copies. Caller MUST confirm with the user first.
    static func deleteOld(at oldRoot: URL, specs: [LocalModelSpec]) throws {
        let fm = FileManager.default
        for spec in specs {
            let dir = oldRoot.appendingPathComponent(spec.directoryName, isDirectory: true)
            if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
        }
    }
}
