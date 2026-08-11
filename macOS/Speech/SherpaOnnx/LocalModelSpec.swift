import Foundation

/// What a local model does.
enum LocalModelCapability: String, Codable, Sendable {
    case asr, llm, tts, ocr
    /// On-device punctuation restoration (ct-transformer) for the 如实输入 path.
    case punctuation
}

/// How a local model is executed on-device.
enum ModelRuntime: String, Codable, Sendable {
    case sherpaOnnx = "sherpa-onnx"
    case onnxRuntime = "onnxruntime"
}

/// Model family (drives which sherpa-onnx config is built).
enum ModelFamily: String, Codable, Sendable {
    case senseVoice, qwen3Asr, funAsrNano
    /// Kokoro offline TTS (multi-lang zh+en). Drives the `OfflineTts` Kokoro config.
    case kokoro
    /// CT-Transformer offline punctuation (zh+en). Drives the `OfflinePunctuation` config.
    case ctTransformerPunct
    /// PaddleOCR PP-OCRv6 local OCR, running det + rec ONNX models in-process.
    case paddleOCR
}

/// Rough expected performance, used by the Load & Test self-check (issue 162).
struct ExpectedMetrics: Codable, Sendable, Equatable {
    /// ASR real-time factor target: audio_seconds / process_seconds. >1 = faster
    /// than real time. nil for non-ASR models.
    let asrRealtimeFactor: Double?
    /// Approximate on-disk size once extracted.
    let approxDiskBytes: Int64
}

/// Where to fetch a model archive and how to verify it. `nil` on a spec means the
/// entry is a catalog preview that the app cannot download yet.
struct DownloadSource: Codable, Sendable, Equatable {
    /// Candidate URLs, tried in order (direct first, mirror fallback).
    let urls: [URL]
    /// Expected sha256 of the archive (lowercase hex).
    let sha256: String
    /// Archive size in bytes.
    let byteSize: Int64
    /// Files that must exist after extraction for the model to count as installed.
    let requiredFiles: [String]
    /// Optional multi-file package. Empty means `urls` points to one archive.
    let files: [DownloadFile]

    init(
        urls: [URL],
        sha256: String,
        byteSize: Int64,
        requiredFiles: [String],
        files: [DownloadFile] = []
    ) {
        self.urls = urls
        self.sha256 = sha256
        self.byteSize = byteSize
        self.requiredFiles = requiredFiles
        self.files = files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        urls = try container.decode([URL].self, forKey: .urls)
        sha256 = try container.decode(String.self, forKey: .sha256)
        byteSize = try container.decode(Int64.self, forKey: .byteSize)
        requiredFiles = try container.decode([String].self, forKey: .requiredFiles)
        files = try container.decodeIfPresent([DownloadFile].self, forKey: .files) ?? []
    }
}

/// A single file inside a multi-file local model package.
struct DownloadFile: Codable, Sendable, Equatable {
    /// Relative path under `LocalModelSpec.storagePath`.
    let relativePath: String
    /// Candidate URLs, tried in order.
    let urls: [URL]
    /// Expected sha256 of the file (lowercase hex).
    let sha256: String
    /// File size in bytes.
    let byteSize: Int64
}

/// A registry entry describing one local model: capability/runtime metadata,
/// where it lives on disk, its install/verify state, and expected metrics.
/// Codable so the catalog can be serialized/decoded (issue 161 acceptance).
struct LocalModelSpec: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let capability: LocalModelCapability
    let runtime: ModelRuntime
    let family: ModelFamily
    let languages: [String]
    let qualityTier: String
    /// Folder name the archive extracts to (the model directory).
    let directoryName: String
    let expected: ExpectedMetrics
    /// nil = catalog preview, not yet downloadable in-app.
    let download: DownloadSource?

    var isDownloadable: Bool { download != nil }

    /// `~/Library/Application Support/Responsay/models/<directoryName>`
    var storagePath: URL {
        SenseVoiceModel.modelsRoot.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// True once all required files exist on disk.
    var isInstalled: Bool {
        guard let required = download?.requiredFiles, !required.isEmpty else { return false }
        let fm = FileManager.default
        return required.allSatisfy {
            fm.fileExists(atPath: storagePath.appendingPathComponent($0).path)
        }
    }
}
