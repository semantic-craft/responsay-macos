import Foundation

/// Resolves where the SenseVoice weights live on disk and loads a recognizer.
///
/// End users download the weights into Application Support via the in-app model
/// manager (slice 2). Until then this is also where a developer can drop the
/// extracted model folder by hand. The engine itself ships inside the .app.
enum SenseVoiceModel {
    /// sherpa-onnx model folder name (pinned to the version we test against).
    static let directoryName = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"

    /// UserDefaults key holding a custom models root (set after a storage migration).
    static let storageOverrideKey = "localModelsRoot"

    /// Default location under Application Support.
    static var defaultModelsRoot: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Responsay/models", isDirectory: true)
    }

    /// Where models live — the migrated location if one is set, else the default.
    static var modelsRoot: URL {
        if let custom = UserDefaults.standard.string(forKey: storageOverrideKey),
           !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return defaultModelsRoot
    }

    static var modelDirectory: URL {
        modelsRoot.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// True once both required files are present on disk.
    static var isInstalled: Bool {
        let model = modelDirectory.appendingPathComponent(SenseVoiceRecognizer.File.model)
        let tokens = modelDirectory.appendingPathComponent(SenseVoiceRecognizer.File.tokens)
        let fm = FileManager.default
        return fm.fileExists(atPath: model.path) && fm.fileExists(atPath: tokens.path)
    }

    /// Load a recognizer for the installed model. `language` is "" (auto) so
    /// Chinese-with-English code-switching works without a manual toggle.
    static func loadRecognizer(language: String = "") throws -> SenseVoiceRecognizer {
        try SenseVoiceRecognizer(modelDir: modelDirectory, language: language)
    }
}
