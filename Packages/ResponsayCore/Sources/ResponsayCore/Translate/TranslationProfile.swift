import Foundation

/// Translation register (issue 142). Shapes *how* faithful vs polished the
/// output reads — never introduces facts.
public enum TranslationStyle: String, Codable, Sendable, CaseIterable, Equatable {
    case balanced
    case faithful
    case polished
    case academic

    public var title: String {
        switch self {
        case .balanced: return "平衡"
        case .faithful: return "忠实"
        case .polished: return "改写"
        case .academic: return "学术"
        }
    }

    public var directive: String {
        switch self {
        case .balanced: return "在忠实与流畅之间取得平衡，不直译生硬也不过度改写。"
        case .faithful: return "尽量忠实于原文结构与措辞，优先保留原意与术语。"
        case .polished: return "在保持原意前提下，让译文更自然、地道、可读。"
        case .academic: return "采用学术书面语域，术语规范、句式严谨。"
        }
    }
}

/// Domain profile for the translation (issue 142). The `legal` profile keeps
/// `[待核]` discipline.
public enum PromptProfile: String, Codable, Sendable, CaseIterable, Equatable {
    case general
    case technical
    case academic
    case legal
    case subtitle
    case custom

    public var title: String {
        switch self {
        case .general: return "通用"
        case .technical: return "技术"
        case .academic: return "学术"
        case .legal: return "法律"
        case .subtitle: return "字幕"
        case .custom: return "自定义"
        }
    }

    public var directive: String {
        switch self {
        case .general: return "面向一般读者，通顺易懂。"
        case .technical: return "保留技术术语与专有名词的准确性。"
        case .academic: return "遵循学术写作规范与引用语域。"
        case .legal: return "采用法律文本语域，精确表达义务、要件与例外。"
        case .subtitle: return "控制每行长度、口语化、适配字幕节奏。"
        case .custom: return ""
        }
    }

    /// Only the legal profile enforces `[待核]` on emitted fact coordinates.
    public var preservesPendingCoordinates: Bool { self == .legal }
}

/// A resolved translate-polish configuration: style × profile × target language,
/// at a fixed low temperature for determinism. Legal keeps `[待核]` (issue 142).
public struct TranslationProfileConfig: Sendable, Equatable {
    /// Fixed low temperature for translate-polish (spec §12).
    public static let temperature = 0.2

    public let style: TranslationStyle
    public let profile: PromptProfile
    public let targetLanguage: String
    public let customDirective: String?

    public init(
        style: TranslationStyle = .balanced,
        profile: PromptProfile = .general,
        targetLanguage: String = "English",
        customDirective: String? = nil
    ) {
        self.style = style
        self.profile = profile
        self.targetLanguage = targetLanguage
        self.customDirective = customDirective
    }

    public var temperature: Double { Self.temperature }
    public var preservesPendingCoordinates: Bool { profile.preservesPendingCoordinates }

    /// The composed system directive for the translate-polish prompt.
    public func resolvedDirective() -> String {
        var parts = ["将文本翻译为\(targetLanguage)。", style.directive]
        if profile == .custom {
            if let custom = customDirective?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
                parts.append(custom)
            }
        } else {
            parts.append(profile.directive)
        }
        if preservesPendingCoordinates {
            parts.append("保留所有法条/案号/日期等事实坐标；未经核验一律标注 [待核]，不得新增或擅自确认事实。")
        }
        return parts.joined(separator: " ")
    }
}
