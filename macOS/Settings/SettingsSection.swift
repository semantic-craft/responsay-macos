import Foundation

/// Sidebar sections, grouped by user-facing domain (settings redesign):
/// 输入 / 引擎 / 法律 / 英语 / 系统. Mirrors `responsay-settings.html` IA.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case hotkeys
    case selectionMenu
    case rewrite
    case models
    case asr
    case llm
    case tts
    case ocr
    case dictionary
    case legalSkills
    case legalConfig
    case verify
    case appearance
    case privacy
    case data
    case storage
    case diagnostics
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"; case .hotkeys: "快捷键"; case .selectionMenu: "划词菜单"; case .rewrite: "改写设置"
        case .models: "模型"
        case .asr: "语音识别"; case .llm: "文本改写"; case .tts: "文本朗读"
        case .ocr: "图片识别"
        case .dictionary: "识别词典"
        case .legalSkills: "技能平台"; case .legalConfig: "技能偏好"; case .verify: "法律 AI"
        case .appearance: "外观主题"
        case .privacy: "隐私与权限"; case .data: "数据"; case .storage: "离线模型"
        case .diagnostics: "诊断"; case .about: "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"; case .hotkeys: "keyboard"; case .selectionMenu: "filemenu.and.selection"; case .rewrite: "wand.and.stars"
        case .models: "slider.horizontal.3"
        case .asr: "waveform"; case .llm: "cpu"; case .tts: "speaker.wave.2"
        case .ocr: "text.viewfinder"
        case .dictionary: "text.book.closed"
        case .legalSkills: "scalemass"; case .legalConfig: "person.text.rectangle"; case .verify: "checkmark.seal"
        case .appearance: "paintpalette"
        case .privacy: "lock.shield"; case .data: "tray.full"; case .storage: "externaldrive"
        case .diagnostics: "stethoscope"; case .about: "info.circle"
        }
    }

    /// Sidebar group accent; nil = neutral wine (输入 / 引擎).
    var domain: SettingsDomain? {
        switch self {
        case .legalSkills, .legalConfig, .verify: .legal
        case .appearance, .privacy, .data, .storage, .diagnostics, .about: .system
        default: nil
        }
    }
}
