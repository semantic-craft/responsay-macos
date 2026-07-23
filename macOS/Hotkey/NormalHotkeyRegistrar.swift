import KeyboardShortcuts
import OSLog
import ResponsayCore

@MainActor
final class NormalHotkeyRegistrar {
    private let logger = Logger(subsystem: AppBrand.loggerSubsystem, category: "normal-hotkey")
    private var tasks: [String: Task<Void, Never>] = [:]

    func registerAllSlots(
        handler: @escaping @MainActor (HotkeyPhase, ShortcutAction, HotkeyTrigger) -> Void
    ) {
        stop()

        for action in ShortcutAction.visibleInShortcutSettings {
            for slot in NormalShortcutSlot.slots(for: action) {
                let taskID = slot.id
                tasks[taskID] = Task { @MainActor in
                    for await event in KeyboardShortcuts.events(for: slot.name) {
                        let phase: HotkeyPhase = event == .keyDown ? .down : .up
                        handler(phase, action, .normal(slot))
                    }
                }

                logger.debug("Registered normal slot \(slot.id, privacy: .public)")
            }
        }
    }

    func stop() {
        for task in tasks.values {
            task.cancel()
        }

        tasks.removeAll()
    }
}
