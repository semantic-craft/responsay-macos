import Foundation

@MainActor
extension ShortcutSettingsStore {
    static func sanitizedBindings(_ bindings: [ShortcutBinding]) -> [ShortcutBinding] {
        var result: [ShortcutBinding] = []
        let hasExistingTranslate = bindings.contains {
            $0.action == .translate && $0.isEnabled && $0.family == .fn
        }
        for binding in bindings {
            guard binding.action == .translateSelection else {
                result.append(binding)
                continue
            }
            guard let chord = binding.fnChord,
                  !hasExistingTranslate,
                  !result.contains(where: { $0.action == .translate }),
                  !bindings.contains(where: {
                      $0.action != .translateSelection && $0.isEnabled && $0.family == .fn && $0.fnChord == chord
                  }) else {
                continue
            }
            result.append(.fn(action: .translate, chord: chord))
        }
        return result
    }

    static func defaultBindings(
        for anchor: ShortcutAnchor,
        defaults: UserDefaults
    ) -> [ShortcutBinding] {
        switch anchor {
        case .fn:
            if FnComboSettings.legacyHasStoredCombo(for: .raw, defaults: defaults) {
                return []
            }
            return currentFnDefaults
        case .rightOption:
            // Ships with no default bindings — the four 常用 modules start unset and the user
            // opts in per chord. (Was: 地道外文 on bare 右Option + 任意提问 on Hyper+右Option.)
            return []
        }
    }

    static func resetBindings(
        for anchor: ShortcutAnchor,
        defaults: UserDefaults
    ) -> [ShortcutBinding] {
        switch anchor {
        case .fn:
            currentFnDefaults
        case .rightOption:
            defaultBindings(for: .rightOption, defaults: defaults)
        }
    }

    static func initialRightOptionEnabled(defaults: UserDefaults) -> Bool {
        if let stored = defaults.object(forKey: Keys.rightOptionHotkeyEnabled) as? Bool {
            return stored
        }
        if defaults.string(forKey: RightOptionTriggerSettings.key) == RightOptionTriggerSettings.disabledSentinel {
            return false
        }
        return true
    }

    static func migrateOldFnShiftDefaultToDictationTranslate(in bindings: inout [ShortcutBinding]) {
        guard bindings.contains(.fn(action: .raw, chord: .fnOnly)),
              bindings.contains(.fn(action: .expressInEnglish, chord: .fnShift)),
              bindings.contains(.fn(action: .askAnything, chord: .fnSpace)),
              !bindings.contains(where: { $0.action == .translate && $0.isEnabled && $0.family == .fn })
        else {
            return
        }
        bindings.removeAll { $0.action == .expressInEnglish && $0.fnChord == .fnShift }
        bindings.append(.fn(action: .translate, chord: .fnShift))
    }
}
