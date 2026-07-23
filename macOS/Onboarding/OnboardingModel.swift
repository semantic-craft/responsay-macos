import SwiftUI
import Observation
import ResponsayCore

/// Drives the wizard: current step, furthest reached, and the user's selections (route / engine /
/// hotkey / granted permissions) for the final-step summary.
@MainActor
@Observable
final class OnboardingModel {
    var step: OnboardingStep = .skin

    /// True when the wizard reopened after a completed first run (菜单栏
    /// 「重看新手引导…」). Re-runs prefill from the live stores and `commit()`
    /// only applies sections the user actually changed — an innocent
    /// click-through must not reset the configured engine/coach/shortcuts
    /// (313 already shields the repair pane from `commit()`; this extends the
    /// same rule to the re-entered full wizard — R26's first-time-gate pattern
    /// at the commit level. 猎虫⑦ H12).
    private let isRerun: Bool
    private let initialEngine: EngineChoice
    private let initialScheme: ShortcutScheme
    private let initialAutoLearn: Bool

    init() {
        let defaults = UserDefaults.standard
        let rerun = defaults.bool(forKey: OnboardingWindowController.completedKey)

        // Mirror the live config on re-runs so the summary tells the truth and
        // an unchanged walk-through is a no-op. Computed into locals first —
        // the stored `let`s must be set before the @Observable vars can be
        // touched. (shortcutScheme's didSet may fire on the prefill assignment;
        // it only writes the same raw value back — idempotent.)
        var prefillScheme = ShortcutScheme.fn
        var prefillEngine = EngineChoice.local
        // First run: pre-select 开启 (recommended) — the audit found auto-learn default-OFF +
        // buried is why the flywheel never runs. Re-runs mirror the live setting (no-clobber).
        var prefillAutoLearn = true
        if rerun {
            if let raw = defaults.string(forKey: "shortcutScheme"),
               let scheme = ShortcutScheme(rawValue: raw) {
                prefillScheme = scheme
            }
            // 「本地引擎」= 选了本机离线转写（SenseVoice 等 sherpa 模型）；Apple/云端 ASR → 云端档。
            let asr = ASREngine.selected(defaults: defaults)
            prefillEngine = (asr.associatedProviderId == nil && asr != .apple) ? .local : .cloud
            prefillAutoLearn = AutoLearnHotwordSettings.resolve(defaults: defaults)
        }
        isRerun = rerun
        initialEngine = prefillEngine
        initialScheme = prefillScheme
        initialAutoLearn = prefillAutoLearn

        if let raw = defaults.object(forKey: "onboardingStep") as? Int,
           let savedStep = OnboardingStep(rawValue: raw) {
            self.step = savedStep
        }
        if rerun {
            shortcutScheme = prefillScheme
            engine = prefillEngine
            autoLearnEnabled = prefillAutoLearn
        }
    }

    // Selections (handoff copy; reconciled to the real flow later).
    var usage: Usage = .legal
    var engine: EngineChoice = .local
    /// 280 — 国内/海外 one-shot choice, preselected from the system locale.
    /// Persisting goes through `NetworkRegion.select` (writes `networkRegion`
    /// AND syncs `localMirror`), so the 基础层 step downloads from the right
    /// source even if the user never touches the picker — the engine step
    /// commits the preselected value on appear.
    var region: NetworkRegion = NetworkRegion.current {
        didSet { NetworkRegion.select(region) }
    }
    var shortcutScheme: ShortcutScheme = .fn {
        didSet { UserDefaults.standard.set(shortcutScheme.rawValue, forKey: "shortcutScheme") }
    }
    var granted: Set<PermissionKind> = []
    /// 自动学习 opt-in (434) — surfaced as its own onboarding step instead of staying OFF and
    /// buried in Settings. First run pre-selects ON (recommended); committed in `commit()`.
    var autoLearnEnabled: Bool = true
    /// 实操体验 sub-step state, lifted here so the wizard footer's 继续/返回 drive the sandbox
    /// flow sequence (otherwise the footer's 继续 jumped to the next step and skipped the rest of
    /// the sandbox — onboarding走查 bug). The footer advances flows until the sequence completes.
    var sandboxSequence = SandboxSequence()
    /// True on the 实操体验 step while flows remain — the footer continues *within* the sandbox.
    var sandboxInProgress: Bool { step == .sandbox && !sandboxSequence.isComplete }
    /// 看演示 sub-step index (0-based). The footer's 继续/返回 page through the 五大模块 one
    /// screen at a time — same single-CTA pattern as `sandboxSequence` for 实操体验.
    var demoIndex = 0
    /// True on 看演示 while later modules remain — the footer continues *within* the demo.
    var demoInProgress: Bool { step == .demo && demoIndex < FeatureDemoShowcase.modules.count - 1 }
    /// Active step sequence. Usage only changes demo copy; it does not gate skills.
    var steps: [OnboardingStep] {
        OnboardingStep.allCases
    }
    var currentIndex: Int { steps.firstIndex(of: step) ?? 0 }
    var isFirst: Bool { currentIndex == 0 }
    var isLast: Bool { currentIndex == steps.count - 1 }
    var progress: Double { Double(currentIndex + 1) / Double(steps.count) }

    func go(to s: OnboardingStep) {
        if s == .demo { demoIndex = 0 }   // 看演示 always opens on the first module
        step = s
        UserDefaults.standard.set(s.rawValue, forKey: "onboardingStep")
    }
    func next() { if currentIndex + 1 < steps.count { go(to: steps[currentIndex + 1]) } }
    func back() { if currentIndex > 0 { go(to: steps[currentIndex - 1]) } }
    func isDone(_ s: OnboardingStep) -> Bool {
        guard let i = steps.firstIndex(of: s) else { return false }
        return i < currentIndex
    }

    var engineSummary: String {
        switch engine {
        case .local: "本地引擎 · 隐私优先"
        case .cloud: "云端引擎 · 更准更快"
        }
    }

    // MARK: - Apply selections to the real stores

    /// Re-read live OS permission state into `granted` (called while the permissions step is on
    /// screen). Only assigns on change so the poll doesn't churn the view.
    func refreshPermissions() {
        var g = granted
        if MicrophonePermission.isGranted { g.insert(.microphone) } else { g.remove(.microphone) }
        if AccessibilityPermission.isTrusted { g.insert(.accessibility) } else { g.remove(.accessibility) }
        if ScreenRecordingPermission.isAuthorized { g.insert(.screenRecording) } else { g.remove(.screenRecording) }
        if g != granted { granted = g }
    }

    /// Commit the wizard's choices to the same stores the Settings window writes, so the app
    /// launches configured. Called once when "开始使用" is tapped on the last step. Skin is already
    /// applied live (step 1) and permissions are requested in their own step; this commits the
    /// shortcut scheme and engine routing.
    func commit() {
        let d = UserDefaults.standard

        // Shortcut scheme → real bindings (ADR-0018). Mirrors Settings「快捷键方案」 onChange.
        // Re-runs apply this ONLY on an actual change: resetTo*Default wipes the
        // user's custom bindings, so an unchanged scheme must not re-apply it.
        if !isRerun || shortcutScheme != initialScheme {
            d.set(shortcutScheme.rawValue, forKey: "shortcutScheme")
            switch shortcutScheme {
            case .fn:    ShortcutSettingsStore.shared.resetToFnDefault()
            case .other: ShortcutSettingsStore.shared.resetToNormalDefault()
            }
        }

        // Engine → ASR / TTS. Local picks the on-device transcription + TTS baseline (works
        // without a key); cloud keeps Apple ASR as the zero-key dictation baseline. Text 改写
        // always runs on the BYOK cloud provider (entered later in Settings — the engine step
        // only links the 图文教程). Re-runs write only on an actual change, so a configured
        // engine survives an innocent wizard re-watch.
        if !isRerun || engine != initialEngine {
            switch engine {
            case .local:
                let asr: ASREngine = SenseVoiceModel.isInstalled ? .sensevoiceLocal : .apple
                d.set(asr.rawValue, forKey: ASREngine.defaultsKey)
                d.set(TTSEngine.sherpaKokoroLocal.rawValue, forKey: TTSEngine.defaultsKey)
            case .cloud:
                d.set(ASREngine.apple.rawValue, forKey: ASREngine.defaultsKey)
            }
        }

        // Auto-learn hotwords (434) → the same key the Settings toggle writes. First run writes the
        // user's onboarding choice; re-runs write only on an actual change (no-clobber, like above).
        if !isRerun || autoLearnEnabled != initialAutoLearn {
            d.set(autoLearnEnabled, forKey: AutoLearnHotwordSettings.key)
        }

        // Clean up the persisted step state so next time (if manually opened) it starts fresh
        d.removeObject(forKey: "onboardingStep")
    }
}

/// The primary use selected during onboarding.
enum Usage: String, CaseIterable, Sendable {
    case legal, general, english
    var title: String {
        switch self {
        case .legal:   "法律写作"
        case .general: "通用输入"
        case .english: "英语提升"
        }
    }
    var detail: String {
        switch self {
        case .legal:   "法条 / 案件 / 书状——围绕法律技能的改写与核验，本应用的核心。"
        case .general: "聊天 / 邮件 / 笔记——任意 App 里说话即插入，干净听写。"
        case .english: "把不顺的外文说成地道外文，附讲解与韵律——口语提升。"
        }
    }
}

enum EngineChoice: String, CaseIterable, Sendable { case local, cloud }

/// The two real ResponsayMac shortcut schemes (ADR-0018; mirrors Settings「快捷键方案」 — 围绕 Fn /
/// 其他组合键). Selecting persists `UserDefaults["shortcutScheme"]`; the actual binding apply
/// (`ShortcutSettingsStore.resetToFnDefault` / `resetToNormalDefault`) is wired during reconciliation.
enum ShortcutScheme: String, CaseIterable, Sendable {
    case fn, other

    var title: String {
        switch self {
        case .fn:    "围绕 Fn 键（推荐）"
        case .other: "其他组合键"
        }
    }
    var detail: String {
        switch self {
        case .fn:    "开箱即用：点按 Fn 开始说话，再点按结束并插入。适合 Fn 没有别的用途。"
        case .other: "用 ⌃⌥⌘ 一类组合键触发，把 Fn 留给系统（输入法 / emoji / 听写）。"
        }
    }
    var meta: String {
        switch self {
        case .fn:    "Fn → 听写"
        case .other: "⌃⌥⌘Y 听写 · ⌥R 改写 · ⌥T 翻译 · ⌥L 法律"
        }
    }
    /// Representative keycaps for the preview row.
    var keycaps: [String] {
        switch self {
        case .fn:    ["Fn"]
        case .other: ["⌃", "⌥", "⌘", "Y"]
        }
    }
    var summary: String {
        switch self {
        case .fn:    "围绕 Fn 键"
        case .other: "其他组合键"
        }
    }
}

enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case microphone, accessibility, screenRecording

    var id: String { rawValue }
    var title: String {
        switch self {
        case .microphone:    "麦克风"
        case .accessibility: "辅助功能"
        case .screenRecording: "屏幕录制"
        }
    }
    var required: Bool { self != .screenRecording }
    var detail: String {
        switch self {
        case .microphone:    "用于收录你的语音并转写。"
        case .accessibility: "监听全局快捷键，让你在任何 app 里唤起、并把文字插入光标处。"
        case .screenRecording: "只用于“截图翻译”。不授权也能继续使用听写、改写和法言输入。"
        }
    }
    var actionTitle: String {
        switch self {
        case .screenRecording: "开启截图翻译"
        default: "开启"
        }
    }
    var glyph: String {
        switch self {
        case .microphone:    "mic.fill"
        case .accessibility: "command"
        case .screenRecording: "viewfinder"
        }
    }
}
