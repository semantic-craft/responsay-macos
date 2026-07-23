import OSLog
import ResponsayCore

@MainActor
final class HotkeyActionRouter {
    private let logger = Logger(subsystem: AppBrand.loggerSubsystem, category: "hotkey-router")
    private let handlers: HotkeyActionHandlers
    private var activeTriggers = Set<String>()

    init(handlers: HotkeyActionHandlers) {
        self.handlers = handlers
    }

    func handle(_ phase: HotkeyPhase, action: ShortcutAction, trigger: HotkeyTrigger) {
        switch phase {
        case .down:
            guard activeTriggers.insert(trigger.id).inserted else {
                return
            }
            handleDown(action, trigger: trigger)
        case .up:
            activeTriggers.remove(trigger.id)
            handleUp(action, trigger: trigger)
        }
    }

    private func handleDown(_ action: ShortcutAction, trigger: HotkeyTrigger) {
        logger.debug("Hotkey down action=\(action.rawValue, privacy: .public) trigger=\(trigger.id, privacy: .public)")

        // A tap of a capture key is always that capture mode — a live selection never diverts it.
        // Selection commands live elsewhere: 任意提问 (Fn/Option + Space) and the drag-to-select 划词菜单.
        switch action {
        case .raw, .translate, .polish, .expressInEnglish:
            handlers.beginCapture(action, trigger)
        case .rewriteSelection:
            handlers.rewriteSelection()
        case .translateSelection:
            handlers.translateSelection()
        case .snapOCR:
            handlers.snapOCR()
        case .snapTextOCR:
            handlers.snapTextOCR()
        case .snapImageCopy:
            handlers.snapImageCopy()
        case .selectionMenu:
            handlers.showSelectionMenu()
        case .askAnything:
            handlers.beginAskAnything(trigger)
        case .openApp:
            handlers.openApp()
        case .openSettings:
            handlers.openSettings()
        case .confirmInsert:
            handlers.confirmInsert()
        }
    }

    private func handleUp(_ action: ShortcutAction, trigger: HotkeyTrigger) {
        logger.debug("Hotkey up action=\(action.rawValue, privacy: .public) trigger=\(trigger.id, privacy: .public)")

        guard handlers.isHoldToTalkEnabled() else {
            return
        }

        switch action {
        case .raw, .translate, .polish, .expressInEnglish:
            handlers.finishCurrentHotkeyAction(trigger)
        case .askAnything:
            handlers.finishAskAnything(trigger)
        case .rewriteSelection, .translateSelection, .snapOCR, .snapTextOCR, .snapImageCopy,
             .selectionMenu, .openApp, .openSettings, .confirmInsert:
            break
        }
    }
}
