import Foundation

public enum CaptureModeResolver {
    public static func resolve(
        _ mode: CaptureMode,
        sidecarOverride: SidecarPolicy? = nil
    ) -> ResolvedCaptureMode {
        let resolved: ResolvedCaptureMode
        switch mode {
        case .raw:
            resolved = .init(
                mode: mode,
                transformKind: .none,
                outputLanguage: .source,
                sidecarPolicy: .collapsed,
                insertPolicy: .insertImmediately)
        case .polishSameLanguage:
            resolved = .init(
                mode: mode,
                transformKind: .sameLanguagePolish,
                outputLanguage: .source,
                sidecarPolicy: .badgeOnly,
                insertPolicy: .insertImmediately)
        case .intentAwareDictation:
            resolved = .init(
                mode: mode,
                transformKind: .intentCompilation,
                outputLanguage: .source,
                sidecarPolicy: .badgeOnly,
                insertPolicy: .insertImmediately)
        case .expressInEnglish:
            resolved = .init(
                mode: mode,
                transformKind: .intentToEnglish,
                outputLanguage: .english,
                sidecarPolicy: .autoOpenCoach,
                insertPolicy: .insertImmediately)
        case .coach:
            resolved = .init(
                mode: mode,
                transformKind: .coachOnly,
                outputLanguage: .englishWithChineseCoach,
                sidecarPolicy: .autoOpenCoach,
                insertPolicy: .noInsert)
        case .rewriteSelection:
            resolved = .init(
                mode: mode,
                transformKind: .rewriteSelection,
                outputLanguage: .english,
                sidecarPolicy: .badgeOnly,
                insertPolicy: .replaceSelection)
        case .translateSelection:
            resolved = .init(
                mode: mode,
                transformKind: .translateSelection,
                outputLanguage: .target,
                sidecarPolicy: .collapsed,
                insertPolicy: .replaceSelection)
        case .legal:
            resolved = .init(
                mode: mode,
                transformKind: .legalSkillPalette,
                outputLanguage: .source,
                sidecarPolicy: .none,
                insertPolicy: .noInsert)
        }

        guard let sidecarOverride else {
            return resolved
        }

        return .init(
            mode: resolved.mode,
            transformKind: resolved.transformKind,
            outputLanguage: resolved.outputLanguage,
            sidecarPolicy: sidecarOverride,
            insertPolicy: resolved.insertPolicy)
    }
}
