import Foundation

/// Whether the input method auto-learns hotwords from the user's post-insertion corrections
/// (434). When on, a term the user repeatedly fixes (same misrecognition → correction, past the
/// `HotwordLearner` threshold) is auto-added to the recognition dictionary's auto bucket. All
/// local, and undoable — auto terms are removable in 识别词典.
///
/// Default OFF: the Typeless-style flywheel only starts after the user explicitly opts in.
enum AutoLearnHotwordSettings {
    static let key = "hotword.autoLearn"

    static var isEnabled: Bool {
        resolve(defaults: .standard)
    }

    /// Absent key → default OFF.
    static func resolve(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }
}
