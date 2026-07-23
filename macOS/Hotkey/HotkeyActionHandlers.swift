struct HotkeyActionHandlers {
    var isHoldToTalkEnabled: @MainActor () -> Bool
    var beginCapture: @MainActor (ShortcutAction, HotkeyTrigger) -> Void
    var finishCurrentHotkeyAction: @MainActor (HotkeyTrigger) -> Void
    var rewriteSelection: @MainActor () -> Void
    var translateSelection: @MainActor () -> Void
    var snapOCR: @MainActor () -> Void
    var snapTextOCR: @MainActor () -> Void
    var snapImageCopy: @MainActor () -> Void
    var showSelectionMenu: @MainActor () -> Void
    var beginAskAnything: @MainActor (HotkeyTrigger) -> Void
    var finishAskAnything: @MainActor (HotkeyTrigger) -> Void
    var openApp: @MainActor () -> Void
    var openSettings: @MainActor () -> Void
    var confirmInsert: @MainActor () -> Void
}
