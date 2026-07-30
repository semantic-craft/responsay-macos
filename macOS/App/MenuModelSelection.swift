import Foundation

/// 379 — when the menu-bar quick picker selects a model, the selection is always recorded
/// (selection semantics preserved), but if it's an **unconfigured cloud model** we also jump
/// the user to that capability's config pane so they can add the key — instead of silently
/// selecting a model that hits a silent failure the moment they speak. Local / already-keyed
/// models switch instantly with no interruption.
///
/// Pure decision (which config section to open, if any) so the branch is unit-tested; the menu
/// view performs the actual `applySelection` + `show(section:)`.
enum MenuModelSelection {
    static func statusTitle(
        _ title: String,
        readiness: ModelLaneReadiness,
        isCurrent: Bool
    ) -> String {
        guard isCurrent else { return title }
        switch readiness {
        case .cloudUnconfigured:
            return "\(title)（未配置）"
        case .localNotInstalled:
            return "\(title)（未下载）"
        case .local, .cloudReady:
            return title
        }
    }

    /// The config section to open after selecting an ASR `optionId`, or `nil` to stay put.
    static func sectionToConfigure(
        forASR optionId: String,
        readiness: ModelLaneReadinessResolver = ModelLaneReadinessResolver()
    ) -> SettingsSection? {
        readiness.asr(optionId: optionId).needsConfiguration ? .asr : nil
    }

    /// The config section to open after selecting an LLM `optionId`, or `nil` to stay put.
    static func sectionToConfigure(
        forLLM optionId: String,
        readiness: ModelLaneReadinessResolver = ModelLaneReadinessResolver()
    ) -> SettingsSection? {
        readiness.llm(optionId: optionId).needsConfiguration ? .llm : nil
    }

    /// The config section to open after selecting a TTS `optionId`, or `nil` to stay put.
    static func sectionToConfigure(
        forTTS optionId: String,
        readiness: ModelLaneReadinessResolver = ModelLaneReadinessResolver()
    ) -> SettingsSection? {
        readiness.tts(optionId: optionId).needsConfiguration ? .tts : nil
    }

    /// The options worth showing in a menu-bar quick picker: usable cloud providers
    /// + all local engines (including models still needing download), **plus the current
    /// route is always visible even if its key was just cleared. Unconfigured cloud
    /// providers are dropped — listing them only renders a ⚠ and a jump-to-config that
    /// clutters the menu; the place to add a key is 设置·模型. Custom OpenAI-compatible
    /// endpoints follow the same rule: shown once a key is saved, hidden until then.
    static func configuredOptions(
        _ options: [CurrentModelOption],
        current: String,
        readiness: (String) -> ModelLaneReadiness
    ) -> [CurrentModelOption] {
        options.filter { option in
            option.id == current || readiness(option.id) != .cloudUnconfigured
        }
    }
}
