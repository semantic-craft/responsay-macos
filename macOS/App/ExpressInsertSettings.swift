import Foundation
import ResponsayCore

/// What the 地道外文 action does after producing the idiomatic target-language text — two modes,
/// both card-based (the former `.directWrite` "no card, just insert" mode was merged into 听写翻译
/// / Fn+Shift, whose nativeIntent translate covers spoken → idiomatic-insert):
///   - `.writeAndExplain` — write in **and** show the explanation card (former ON state).
///   - `.explainOnly`     — only show the explanation card; write in manually (former OFF state).
enum ExpressOutputMode: String, CaseIterable, Sendable {
    case writeAndExplain
    case explainOnly

    /// The capture-pipeline mode this drives.
    var outputMode: QuickCaptureViewModel.OutputMode {
        switch self {
        case .writeAndExplain: .teachingFeedback
        case .explainOnly: .coachRewrite
        }
    }
}

/// Single source of truth for the 地道外文 output mode — the picker in 改写设置 and the
/// controller at capture time both read this. Migrates the retired `expressAutoInsert`
/// boolean (true → writeAndExplain, false → explainOnly). Fresh install → writeAndExplain:
/// Responsay is an input method, so the common case is "put the English where I'm typing".
enum ExpressInsertSettings {
    static let key = "express.outputMode"
    static let legacyAutoInsertKey = "expressAutoInsert"

    static func mode(defaults: UserDefaults = .standard) -> ExpressOutputMode {
        if let raw = defaults.string(forKey: key), let mode = ExpressOutputMode(rawValue: raw) {
            return mode
        }
        if let legacy = defaults.object(forKey: legacyAutoInsertKey) as? Bool {
            return legacy ? .writeAndExplain : .explainOnly
        }
        return .writeAndExplain
    }

    static func setMode(_ mode: ExpressOutputMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: key)
    }
}
