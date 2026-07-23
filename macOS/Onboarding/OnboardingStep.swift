import Foundation

/// The first-run onboarding steps in their persisted order. `basicsLayer`（装离线基础层）
/// follows the sandbox.
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    // Keep the existing raw values stable because unfinished onboarding sessions
    // persist `onboardingStep` as an Int. `.demo` is reinserted into the visible
    // flow through `allCases`, without shifting sandbox/basicsLayer/done.
    case skin = 0
    // (rawValue 1 retired — 选用途 step removed; it only flavored demo copy, never gated skills.
    //  Other raw values stay stable; a persisted "1" just won't restore, falling back to .skin.)
    case engine = 2
    case snapOCR = 3
    case permissions = 4
    case hotkey = 5
    case sandbox = 7
    case basicsLayer = 8
    case done = 9
    case demo = 10
    case autoLearn = 11

    static let allCases: [OnboardingStep] = [
        .skin, .engine, .snapOCR, .permissions, .hotkey,
        .autoLearn, .demo, .sandbox, .basicsLayer, .done,
    ]

    var id: Int { rawValue }
    static var count: Int { allCases.count }
    var number: Int { (Self.allCases.firstIndex(of: self) ?? rawValue) + 1 }

    var label: String {
        switch self {
        case .skin:        "选皮肤"
        case .engine:      "选引擎"
        case .snapOCR:     "截图翻译"
        case .permissions: "开权限"
        case .hotkey:      "设快捷键"
        case .autoLearn:   "自动学习"
        case .demo:        "看演示"
        case .sandbox:     "实操体验"
        case .basicsLayer: "装基础层"
        case .done:        "完成"
        }
    }

    var sub: String {
        switch self {
        case .skin:        "外观"
        case .engine:      "本地 / 云端"
        case .snapOCR:     "忠实翻译"
        case .permissions: "麦克风等"
        case .hotkey:      "随处唤起"
        case .autoLearn:   "从纠正学词"
        case .demo:        "功能预览"
        case .sandbox:     "任务制沙盒"
        case .basicsLayer: "离线听写+标点"
        case .done:        "开始使用"
        }
    }

    /// "STEP 0N · 外观" eyebrow.
    var kicker: String { String(format: "STEP %02d · %@", number, sub) }
}
