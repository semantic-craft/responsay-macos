import Foundation
import OSLog
import ResponsayCore

/// On-device punctuation for the 如实输入 (raw / verbatim) path. Acts only when BOTH:
/// 1. the CT-Transformer punctuation model is installed (downloading it is the opt-in), AND
/// 2. the selected ASR engine emits no punctuation of its own (offline AED models).
///
/// Otherwise returns the text unchanged — so faithful mode stays exactly verbatim for users who
/// want raw output, and already-punctuated engines (Apple / Zipformer / cloud) aren't
/// double-punctuated. No LLM, no network: this is the "verbatim words + punctuation" middle tier.
struct SettingsBackedLocalPunctuator: TextPunctuator {
    func punctuate(_ text: String) async -> String {
        guard ASREngine.selected.lacksNativePunctuation else { return text }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        return await LocalPunctuationEngine.shared.punctuate(text)
    }
}

/// Lazily loads and caches the CT-Transformer punctuation model, running `addPunct` off the main
/// thread (the actor's executor). The ~72 MB model loads once, on first faithful-mode use.
actor LocalPunctuationEngine {
    static let shared = LocalPunctuationEngine()

    private var engine: CTTransformerPunctuator?
    private var loadFailed = false
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "punct")

    func punctuate(_ text: String) -> String {
        guard let engine = loadedEngine() else { return text }
        return engine.addPunctuation(text)
    }

    /// Cache the engine after first successful load. If the model isn't installed yet, return nil
    /// WITHOUT latching failure, so a later in-session download is picked up. A genuine load error
    /// (corrupt model) latches to avoid retrying a broken file every utterance.
    private func loadedEngine() -> CTTransformerPunctuator? {
        if let engine { return engine }
        guard !loadFailed else { return nil }
        let spec = LocalModelRegistry.punctuationModel
        guard spec.isInstalled else { return nil }
        do {
            let built = try CTTransformerPunctuator(modelDir: spec.storagePath)
            engine = built
            return built
        } catch {
            loadFailed = true
            log.error("punctuation model load failed → 如实输入 stays verbatim: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
