import ResponsayCore

struct TTSFallbackAttempt {
    let target: TTSFallbackTarget
    let title: String
    let makeSynthesizer: () throws -> any SpeechSynthesizer
}

extension TTSFallbackAttempt {
    static func attempts(
        selected: TTSEngine = .selected,
        makeSelected: @escaping () throws -> any SpeechSynthesizer
    ) -> [TTSFallbackAttempt] {
        TTSFallbackPlan.runtimeTargets(selectedIsKokoro: selected == .sherpaKokoroLocal).map { target in
            switch target {
            case .selected:
                TTSFallbackAttempt(target: target, title: selected.title, makeSynthesizer: makeSelected)
            case .kokoro:
                TTSFallbackAttempt(target: target, title: "Kokoro") { try SherpaTTSEngine.loadDefault() }
            case .system:
                TTSFallbackAttempt(target: target, title: "Apple system TTS") {
                    SystemSpeechSynthesizer()
                }
            }
        }
    }
}
