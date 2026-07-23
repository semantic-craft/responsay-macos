import Foundation

/// The「纠正胶囊」display rule (518 follow-up — user feedback 2026-07-03: the chip appearing on
/// every single dictation was too noisy). Default OFF: `QuickCaptureViewModel` only offers the
/// chip when the inserted text looks like it might contain a mis-heard proper noun
/// (`looksLikeMishearCandidate`). Turning this on shows it after every successful insert instead,
/// for a user who wants to manually review/teach every sentence.
enum CorrectionChipSettings {
    static let alwaysShowKey = "hotword.correctionChip.alwaysShow"

    static func alwaysShow(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: alwaysShowKey)   // absent → false (default: smart/heuristic only)
    }

    static func setAlwaysShow(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: alwaysShowKey)
    }
}
