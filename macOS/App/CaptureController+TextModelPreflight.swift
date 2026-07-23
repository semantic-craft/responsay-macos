import AppKit
import ResponsayCore

@MainActor
extension CaptureController {
    func requireTextModelIfNeeded(outputMode: QuickCaptureViewModel.OutputMode) -> Bool {
        guard outputMode.spec.requiresTextModel else { return true }
        return requireTextModel(feature: Self.textModelFeatureLabel(outputMode))
    }

    static func textModelFeatureLabel(_ mode: QuickCaptureViewModel.OutputMode) -> String {
        switch mode {
        case .rewriteSameLanguage: "改写选中文本"
        case .normalizeTypographySelection: "规范排版"
        case .idiomaticPreview: "地道表达"
        case .coachRewrite, .teachingFeedback: "地道外文"
        case .translateSpoken, .translateWritten, .translatePreview: "翻译"
        case .askSelection: "任意提问"
        case .rawTranscript, .polishedTranscript, .intentAwareDictation: ""
        }
    }

    func requireTextModel(feature: String) -> Bool {
        guard !LLMEndpointResolver.isConfigured() else { return true }
        vm.fail("需要先配置文本改写大模型。")
        showTextModelSetupAlert(feature: feature)
        return false
    }

    private func showTextModelSetupAlert(feature: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "需要配置文本改写大模型")
        alert.informativeText = String(localized: "\(feature) 需要文本改写大模型才能运行。没配置模型时，听写仍可用（自动退回语音原文上屏）；要使用翻译、改写、地道外文或任意提问，请先在设置里配置一个文本模型。")
        alert.addButton(withTitle: String(localized: "打开文本改写设置"))
        alert.addButton(withTitle: String(localized: "取消"))
        if alert.runModal() == .alertFirstButtonReturn {
            MacSettingsWindowController.shared.show(section: .llm)
        }
    }
}
