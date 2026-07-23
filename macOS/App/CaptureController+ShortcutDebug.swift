import OSLog
import ResponsayCore

#if DEBUG
extension CaptureController {
    func debugLogShortcutBindings() {
        shortcutSettingsStore.refreshFromDefaults()
        let summary = ShortcutAction.visibleInShortcutSettings
            .map { action in
                let bindings = shortcutSettingsStore.bindings(for: action)
                    .map(Self.debugDescription(for:))
                    .joined(separator: ", ")
                return "\(action.rawValue)=[\(bindings)]"
            }
            .joined(separator: " ")

        Self.debugLog.info("Shortcut bindings dump: \(summary, privacy: .public)")
    }

    func debugSimulateNormalHotkey(actionRaw: String, slotIndex: Int, phaseRaw: String) {
        guard
            let action = ShortcutAction(rawValue: actionRaw),
            let phase = Self.hotkeyPhase(from: phaseRaw)
        else {
            Self.debugLog.error("Invalid normal hotkey simulation action=\(actionRaw, privacy: .public) phase=\(phaseRaw, privacy: .public)")
            return
        }

        let slot = NormalShortcutSlot(action: action, index: slotIndex)
        hotkeyRouter.handle(phase, action: action, trigger: HotkeyTrigger.normal(slot))
    }

    func debugSimulateFnHotkey(chordID: String, phaseRaw: String) {
        guard
            let chord = (ShortcutAnchor.allCases
                .flatMap(FnChord.stageOneAllowed(for:))
                + [FnChord.fnSpace])
                .first(where: { $0.id == chordID }),
            let phase = Self.hotkeyPhase(from: phaseRaw)
        else {
            Self.debugLog.error("Invalid Fn hotkey simulation chord=\(chordID, privacy: .public) phase=\(phaseRaw, privacy: .public)")
            return
        }

        hotkeyDispatcher.handleFnChord(phase, chord: chord)
    }

    private static let debugLog = Logger(subsystem: AppBrand.loggerSubsystem, category: "shortcut-debug")

    private static func hotkeyPhase(from rawValue: String) -> HotkeyPhase? {
        switch rawValue {
        case "down":
            .down
        case "up":
            .up
        default:
            nil
        }
    }

    private static func debugDescription(for binding: ShortcutBinding) -> String {
        switch binding.family {
        case .fn:
            binding.fnChord?.id ?? "anchor:missing"
        case .normal:
            if let index = binding.normalSlotIndex {
                "normal:\(index)"
            } else {
                "normal:missing"
            }
        }
    }
}
#endif
