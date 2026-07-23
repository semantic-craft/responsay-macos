import Foundation

/// Stable id for a TTS provider (e.g. `"qwen"`, `"minimax"`, `"openai"`).
public typealias TTSProviderID = String

/// One synthesis model a provider exposes (spec §1.2.1).
public struct TTSModelSpec: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var supportsStreaming: Bool
    public var supportsWordTiming: Bool
    public var supportsSentenceTiming: Bool
    public var supportsRealtimeWS: Bool
    public var maxCharsPerRequest: Int?

    public init(
        id: String,
        displayName: String,
        supportsStreaming: Bool = false,
        supportsWordTiming: Bool = false,
        supportsSentenceTiming: Bool = false,
        supportsRealtimeWS: Bool = false,
        maxCharsPerRequest: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.supportsStreaming = supportsStreaming
        self.supportsWordTiming = supportsWordTiming
        self.supportsSentenceTiming = supportsSentenceTiming
        self.supportsRealtimeWS = supportsRealtimeWS
        self.maxCharsPerRequest = maxCharsPerRequest
    }
}

/// A voice, valid for a subset of the provider's models (spec §1.2.1).
public struct TTSVoiceSpec: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var supportedModelIDs: [String]
    public var languageHints: [String]
    public var genderHint: String?
    public var styleTags: [String]

    public init(
        id: String,
        displayName: String,
        supportedModelIDs: [String] = [],
        languageHints: [String] = [],
        genderHint: String? = nil,
        styleTags: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.supportedModelIDs = supportedModelIDs
        self.languageHints = languageHints
        self.genderHint = genderHint
        self.styleTags = styleTags
    }

    /// A voice with no `supportedModelIDs` is treated as model-agnostic.
    public func supports(modelID: String) -> Bool {
        supportedModelIDs.isEmpty || supportedModelIDs.contains(modelID)
    }
}

/// Default model / voice / speed / sample-rate for a provider (spec §1.2.1).
public struct TTSDefaults: Codable, Sendable, Equatable {
    public var modelID: String
    public var voiceID: String
    public var speed: Double
    public var sampleRate: Int

    public init(modelID: String, voiceID: String, speed: Double = 1.0, sampleRate: Int = 24_000) {
        self.modelID = modelID
        self.voiceID = voiceID
        self.speed = speed
        self.sampleRate = sampleRate
    }
}

/// Provider/model/voice as **data**, so nothing is hard-coded into the UI
/// (issue 129; mirrors the ASR/LLM `ProviderCatalog`). Billing lives in the
/// settings layer; this core type stays about capability + defaults.
public struct TTSProviderCatalog: Codable, Sendable, Equatable, Identifiable {
    public var providerID: TTSProviderID
    public var displayName: String
    public var models: [TTSModelSpec]
    public var voices: [TTSVoiceSpec]
    public var defaults: TTSDefaults

    public var id: TTSProviderID { providerID }

    public init(
        providerID: TTSProviderID,
        displayName: String,
        models: [TTSModelSpec],
        voices: [TTSVoiceSpec],
        defaults: TTSDefaults
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.models = models
        self.voices = voices
        self.defaults = defaults
    }

    public func model(id: String) -> TTSModelSpec? { models.first { $0.id == id } }

    /// Voices valid for a given model (issue 129: voice filterable by model).
    public func voices(forModel modelID: String) -> [TTSVoiceSpec] {
        voices.filter { $0.supports(modelID: modelID) }
    }

    /// Default model resolved against the model list (nil if `defaults` dangles).
    public var defaultModel: TTSModelSpec? { model(id: defaults.modelID) }

    /// Default voice — only if it's actually valid for the default model.
    public var defaultVoice: TTSVoiceSpec? {
        voices.first { $0.id == defaults.voiceID && $0.supports(modelID: defaults.modelID) }
    }
}
