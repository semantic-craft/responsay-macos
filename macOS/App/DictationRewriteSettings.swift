import Foundation
import ResponsayCore

/// 听写默认力度的单一真相源（393；2026-06-19 反转默认为清稿，对标 Typeless「把语音当意图草稿」）。
/// **默认（未设置过）= 轻度改写**（去口水词、加标点、顺句）；
/// **关 = 如实输入**（只用 ASR 原文逐字上屏、不过 LLM）——给不认同整理的用户的逃生口。
/// 菜单栏「如实输入」开关与设置「改写力度」面板的「如实 / 轻度改写」二选一都读写这同一个 key，故两处即时联动。
///
/// 无 LLM 配置时，轻度改写（polish）会自动退回逐字，所以离线安全——默认开着也不会报错。
enum DictationRewriteSettings {
    /// 未设置过 → 缺省 `true` → 轻度改写（清稿）。用户显式选「如实输入」才存 `false`。
    static let key = "dictation.lightRewrite"

    /// 是否启用轻度改写。key 缺失时缺省 **true**（清稿默认）；用户显式设过则尊重其选择。
    static func lightRewriteEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    /// 听写（`.raw` 动作）的上屏模式：默认轻度整理；用户开了「如实输入」(= 关轻度改写) 才逐字。
    /// 校验成稿（实验，558）只在轻度改写档上叠加——如实输入永远是逃生口，不被实验模式劫持。
    static func dictationOutputMode(_ defaults: UserDefaults = .standard) -> QuickCaptureViewModel.OutputMode {
        guard lightRewriteEnabled(defaults) else { return .rawTranscript }
        return IntentDictationSettings.isEnabled(defaults) ? .intentAwareDictation : .polishedTranscript
    }
}
