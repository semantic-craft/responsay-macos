import Foundation

/// Style learning (P1): the learned + user-overridable style descriptor that feeds the 意图成稿
/// prompt. Default ON (convenience-first). Precedence: a non-empty user override wins over the
/// learned descriptor; disabled → no descriptor at all.
enum StyleProfileSettings {
    static let enabledKey = "style.profile.enabled"
    static let learnedKey = "style.profile.learned"
    static let overrideKey = "style.profile.override"
    static let lastBuiltAtKey = "style.profile.lastBuiltAt"

    /// Minimum kept dictations before the first distillation, and the re-distill cadence.
    static let minSamples = 5
    static let refreshInterval: TimeInterval = 24 * 3600

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true   // default ON
    }

    static func setEnabled(_ on: Bool, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: enabledKey)
    }

    /// What actually reaches the polish prompt: override > learned, and nothing when disabled.
    static func effectiveDescriptor(defaults: UserDefaults = .standard) -> String? {
        guard isEnabled(defaults: defaults) else { return nil }
        if let override = nonEmpty(defaults.string(forKey: overrideKey)) { return override }
        return nonEmpty(defaults.string(forKey: learnedKey))
    }

    static func learned(defaults: UserDefaults = .standard) -> String? {
        nonEmpty(defaults.string(forKey: learnedKey))
    }

    static func hasLearned(defaults: UserDefaults = .standard) -> Bool {
        learned(defaults: defaults) != nil
    }

    static func setLearned(_ descriptor: String, at date: Date, defaults: UserDefaults = .standard) {
        defaults.set(descriptor, forKey: learnedKey)
        defaults.set(date.timeIntervalSince1970, forKey: lastBuiltAtKey)
    }

    static func lastBuiltAt(defaults: UserDefaults = .standard) -> Date? {
        let t = defaults.double(forKey: lastBuiltAtKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
