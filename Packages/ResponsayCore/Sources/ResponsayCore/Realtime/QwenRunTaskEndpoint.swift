import Foundation

public enum QwenRunTaskRegion: String, Sendable, CaseIterable, Codable {
    case china
    case singapore

    /// Generic host, used when no Workspace ID is configured. The docs recommend migrating to the
    /// business-space host but state these still work ("现有域名仍可正常使用").
    public var genericHost: String {
        switch self {
        case .china:
            return "dashscope.aliyuncs.com"
        case .singapore:
            return "dashscope-intl.aliyuncs.com"
        }
    }

    /// Region label inside the business-space dedicated host.
    public var dedicatedHostSuffix: String {
        switch self {
        case .china:
            return "cn-beijing.maas.aliyuncs.com"
        case .singapore:
            return "ap-southeast-1.maas.aliyuncs.com"
        }
    }
}

/// WebSocket endpoint for 百炼 实时语音识别 over the run-task protocol.
///
/// The path is fixed at `/api-ws/v1/inference` and the model is NOT a query parameter — it goes in
/// the `run-task` payload (unlike the retired OmniRealtime endpoint, which put it in the URL).
public struct QwenRunTaskEndpoint: Sendable, Equatable {
    /// The only realtime model that accepts 即时热词 (`vocabulary`) — the reason this engine exists.
    public static let defaultModel = "qwen-audio-3.0-asr-flash-streaming"
    public static let path = "/api-ws/v1/inference"

    public var region: QwenRunTaskRegion
    /// Optional business space. A valid `ws-…` id switches the request to that space's dedicated
    /// host; anything else (including empty) falls back to the generic host.
    public var workspaceID: String?

    public init(region: QwenRunTaskRegion = .china, workspaceID: String? = nil) {
        self.region = region
        self.workspaceID = workspaceID
    }

    /// A Workspace ID becomes a DNS label, so only the documented `ws-…` shape is accepted —
    /// arbitrary input must never be interpolated into a host.
    public static func normalizedWorkspaceID(_ rawValue: String?) -> String? {
        guard let candidate = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              candidate.hasPrefix("ws-"), candidate.count > 3, candidate.count <= 63 else { return nil }
        let suffix = candidate.dropFirst(3)
        guard suffix.unicodeScalars.allSatisfy({ scalar in
            (48 ... 57).contains(scalar.value) || (97 ... 122).contains(scalar.value)
        }) else { return nil }
        return candidate
    }

    public var host: String {
        guard let workspaceID = Self.normalizedWorkspaceID(workspaceID) else {
            return region.genericHost
        }
        return "\(workspaceID).\(region.dedicatedHostSuffix)"
    }

    public var usesDedicatedHost: Bool { Self.normalizedWorkspaceID(workspaceID) != nil }

    /// Model Studio does not support hotwords in Singapore sub-workspaces. The workspace ID does
    /// not reveal whether a space is primary or subordinate, so dedicated Singapore workspaces are
    /// conservatively treated as unsupported to keep an optional vocabulary from breaking capture.
    public var supportsHotwords: Bool { region != .singapore || !usesDedicatedHost }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.path = Self.path
        return components.url!
    }
}

/// A precompiled vocabulary ID plus the exact environment and local dictionary snapshot it was
/// synchronized for. IDs are not portable across target models, regions or workspaces. The
/// fingerprint contains no vocabulary text and makes any later local edit fail closed at the ID
/// lane, while dictation itself fails open through request-level instant vocabulary.
public struct QwenPrecompiledVocabularyBinding: Sendable, Equatable, Codable {
    public let identifier: String
    public let model: String
    public let region: QwenRunTaskRegion
    public let workspaceID: String?
    public let vocabularyFingerprint: String

    public init(
        identifier: String,
        model: String,
        region: QwenRunTaskRegion,
        workspaceID: String?,
        vocabularyFingerprint: String
    ) {
        self.identifier = identifier
        self.model = model
        self.region = region
        self.workspaceID = workspaceID
        self.vocabularyFingerprint = vocabularyFingerprint
    }

    /// Returns only the opaque ID; callers never need to inspect or log the bound vocabulary.
    public func resolvedIdentifier(
        model currentModel: String,
        endpoint: QwenRunTaskEndpoint,
        vocabularyFingerprint currentFingerprint: String
    ) -> String? {
        guard let identifier = QwenASRHotwords.normalizedVocabularyIdentifier(identifier),
              QwenASRHotwords.supportsPrecompiledVocabulary(model: currentModel),
              endpoint.supportsHotwords,
              normalizedModel(model) == normalizedModel(currentModel),
              region == endpoint.region,
              let boundWorkspace = Self.workspaceIdentity(workspaceID),
              let currentWorkspace = Self.workspaceIdentity(endpoint.workspaceID),
              boundWorkspace == currentWorkspace,
              !vocabularyFingerprint.isEmpty,
              vocabularyFingerprint == currentFingerprint else { return nil }
        return identifier
    }

    private func normalizedModel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Empty means the account's default workspace. A non-empty malformed value is invalid, not
    /// equivalent to default — otherwise an unsafe/stale workspace could silently reuse an ID.
    private static func workspaceIdentity(_ rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        return QwenRunTaskEndpoint.normalizedWorkspaceID(trimmed)
    }
}

/// Everything the engine needs to open one run-task session, resolved fresh per capture so a
/// settings change (Workspace ID, region, model, key, 词典) takes effect without an app restart.
public struct QwenRunTaskCaptureConfig: Sendable {
    public var endpoint: QwenRunTaskEndpoint
    public var apiKey: String
    public var model: String
    public var hotwords: [String]
    /// Already validated for the endpoint/model/workspace/dictionary snapshot. Never logged.
    public var precompiledVocabularyID: String?
    public var context: [String]
    /// Local-only isolation key; never serialized onto the wire.
    public var contextScope: String?
    public var heartbeat: Bool
    public var semanticPunctuationEnabled: Bool
    public var multiThresholdModeEnabled: Bool

    public init(
        endpoint: QwenRunTaskEndpoint,
        apiKey: String,
        model: String = QwenRunTaskEndpoint.defaultModel,
        hotwords: [String] = [],
        precompiledVocabularyID: String? = nil,
        context: [String] = [],
        contextScope: String? = nil,
        heartbeat: Bool = false,
        semanticPunctuationEnabled: Bool = false,
        multiThresholdModeEnabled: Bool = false
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.hotwords = hotwords
        self.precompiledVocabularyID = precompiledVocabularyID
        self.context = context
        self.contextScope = contextScope
        self.heartbeat = heartbeat
        self.semanticPunctuationEnabled = semanticPunctuationEnabled
        self.multiThresholdModeEnabled = multiThresholdModeEnabled
    }
}
