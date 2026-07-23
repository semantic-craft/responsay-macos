import Foundation

/// Which text action produced a history entry. Mirrors the user-facing capture
/// modes (`QuickCaptureViewModel.OutputMode`) collapsed to the kinds worth
/// showing in History. Source: spec §6.2.2.
public enum TextActionKind: String, Codable, Sendable, Equatable, CaseIterable {
    case dictation   // 如实输入 — raw transcript
    case polish      // 改写原话 — light polish
    case rewrite     // 重改写 — heavy same-language rewrite
    case translate   // 翻译
    case coach       // 地道表达 / 地道外文
    case feedback    // 发音 / 口语反馈
    case other
}

/// Whether an entry was produced fully on-device or via a cloud provider — the
/// privacy posture recorded at capture time. Source: spec §6.2.2.
public enum RoutePrivacyMode: String, Codable, Sendable, Equatable, CaseIterable {
    case onDevice    // fully local (offline ASR/LLM/TTS)
    case cloud       // a cloud provider was used
    case unknown
}

/// One History entry: audio + text metadata for a past capture. Persisted by
/// `HistoryMediaStore`. Mirrors spec §6.2.2 — do NOT redesign the field set.
///
/// `audioFileURL` points at a file inside the store's `audioDirectory`; the
/// store persists only the filename and resolves the absolute URL on read.
public struct HistoryItem: Codable, Identifiable, Sendable, Equatable {
    public static let unretainedSourceMessage = "原口述未保存"

    public let id: UUID
    public let createdAt: Date
    public let sourceAppName: String?
    public let sourceBundleID: String?
    public let actionKind: TextActionKind
    public let transcript: String?
    public let resultText: String?
    public let audioFileURL: URL?
    public let duration: TimeInterval?
    public let providerSummary: String?
    public let privacyMode: RoutePrivacyMode
    /// Intent-aware display metadata (#565): the visible compile route and the coarse terminal
    /// outcome of an approved 校验成稿 record, or `nil` for every other kind. Presentation only —
    /// the raw utterance stays unsaved (`transcript == nil`).
    public let intentRoute: IntentInsertRoute?
    public let intentOutcome: IntentHistoryOutcome?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil,
        actionKind: TextActionKind,
        transcript: String? = nil,
        resultText: String? = nil,
        audioFileURL: URL? = nil,
        duration: TimeInterval? = nil,
        providerSummary: String? = nil,
        privacyMode: RoutePrivacyMode,
        intentRoute: IntentInsertRoute? = nil,
        intentOutcome: IntentHistoryOutcome? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.actionKind = actionKind
        self.transcript = transcript
        self.resultText = resultText
        self.audioFileURL = audioFileURL
        self.duration = duration
        self.providerSummary = providerSummary
        self.privacyMode = privacyMode
        self.intentRoute = intentRoute
        self.intentOutcome = intentOutcome
    }

    /// Best one-line text for a row: the produced result, falling back to the
    /// transcript.
    public var displayText: String {
        if let resultText, !resultText.isEmpty { return resultText }
        return transcript ?? ""
    }

    /// Detail text for the source section. The marker is presentation only and is
    /// never persisted or treated as searchable source content.
    public var sourceDisplayText: String {
        transcript ?? Self.unretainedSourceMessage
    }

    /// Search only content that was actually retained. No display fallback is used.
    public func matchesSearch(_ query: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return transcript?.localizedCaseInsensitiveContains(term) == true
            || resultText?.localizedCaseInsensitiveContains(term) == true
    }

    /// Export the approved result when available, otherwise the actually retained
    /// source. If neither exists, explicitly state that the source was not retained.
    public var exportText: String {
        if let resultText, !resultText.isEmpty { return resultText }
        return transcript ?? Self.unretainedSourceMessage
    }

    /// A short, content-free badge for an Intent-aware record ("校验成稿 · 已插入"), or `nil` for
    /// non-intent records. Route + coarse outcome only — never any of the unsaved raw utterance.
    public var intentBadge: String? {
        guard let intentRoute else { return nil }
        let route = intentRoute == .intentPlan ? "校验成稿" : "普通整理"
        guard let intentOutcome else { return route }
        return "\(route) · \(intentOutcome == .inserted ? "已插入" : "已复制")"
    }
}
