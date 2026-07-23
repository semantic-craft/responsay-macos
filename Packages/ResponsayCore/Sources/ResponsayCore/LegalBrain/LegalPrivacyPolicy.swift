import Foundation

// MARK: - 110 LegalPrivacyPolicy + ModelRoute + send-preview
//
// The confidentiality differentiator. Runs AFTER the capture gate (052/080) and
// never bypasses it: a security denial → `.blocked`. Then it decides the model
// route from sensitivity + the user's preference, and lists EXACTLY which fields a
// cloud call may send (never the whole document). Deterministic / Foundation-only;
// it is the privacy axis the `ModelProviderRouter` (106) consults (v0.2 §14).

/// A field that may be sent to a cloud model. The send-preview shows exactly these.
public enum LegalSendField: String, Sendable, Equatable, CaseIterable {
    case selectedText      // 选中文本
    case sceneTag          // 场景标签（litigation/privacy…）
    case appCategory       // 应用类别（如 wordProcessor）— coarse, non-identifying
    case nearbyHeading     // 附近标题（仅在用户放宽时）
    case windowTitleHash   // 窗口标题哈希（v0 默认不发送）

    public var label: String {
        switch self {
        case .selectedText:    return "选中文本"
        case .sceneTag:        return "场景标签"
        case .appCategory:     return "应用类别"
        case .nearbyHeading:   return "附近标题"
        case .windowTitleHash: return "窗口标题（哈希）"
        }
    }
}

public struct LegalPrivacyDecision: Sendable, Equatable {
    public let route: ModelRoute
    /// Exactly the fields a cloud call may send (the send-preview). Empty when blocked.
    public let sendFields: [LegalSendField]
    public let reasons: [String]

    public init(route: ModelRoute, sendFields: [LegalSendField], reasons: [String]) {
        self.route = route
        self.sendFields = sendFields
        self.reasons = reasons
    }

    public var isBlocked: Bool { route == .blocked }
    public var requiresUserConfirm: Bool { route == .cloudRequiresUserConfirm }
    public var allowsCloud: Bool { route == .cloudAllowed || route == .cloudRequiresUserConfirm }
}

public struct LegalPrivacyPolicy: Sendable {
    public init() {}

    /// Decide route + send-preview. 联网 vs 本地 是用户的决定：`route` 只跟随用户显式的
    /// `modelPreference`。不再因「安全输入 / 敏感词 / 敏感应用 / OCR 取文」自动阻断或强制本地——
    /// 是否联网由用户的偏好与「联网搜索」开关决定,本策略只忠实执行。
    ///
    /// ponytail: `gate` / `surroundingText` / `appName` / `source` 已不影响路由,保留参数仅为调用点
    /// 签名稳定(彻底删需同时改协调器与一批测试,属另一次清理)。
    public func decide(
        gate: CaptureGateDecision,
        selectedText: String,
        surroundingText: String? = nil,
        appName: String? = nil,
        source: LegalContextSource = .accessibility,
        privacyPreference: PrivacyPreference = .selectedTextOnly,
        modelPreference: ModelPreference = .askEachTime
    ) -> LegalPrivacyDecision {
        // Route ladder = 用户偏好,仅此。localFirst→本地;cloudFirst→云;askEachTime→发送前确认。
        let route: ModelRoute
        switch modelPreference {
        case .localFirst:  route = .localOnly
        case .cloudFirst:  route = .cloudAllowed
        case .askEachTime: route = .cloudRequiresUserConfirm
        }

        // Send-preview: 最小默认字段集(选中文本 + 场景标签 + 应用类别);nearbyHeading 仅在用户放宽。
        // surrounding text / window 标题默认不发送。
        var sendFields: [LegalSendField] = [.selectedText, .sceneTag, .appCategory]
        if privacyPreference != .selectedTextOnly { sendFields.append(.nearbyHeading) }

        return LegalPrivacyDecision(route: route, sendFields: sendFields, reasons: [])
    }
}
