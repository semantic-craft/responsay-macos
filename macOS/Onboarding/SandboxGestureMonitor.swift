import AppKit

/// The real trigger a sandbox flow asks the user to press (hands-on 实操). Detected via a local
/// NSEvent monitor (no accessibility permission needed while the onboarding window is key), like
/// the 设快捷键 calibration. The press is real; the revealed result stays a labelled 示例 (there's
/// no model to translate/answer the user's actual words during onboarding).
enum SandboxGesture {
    case fnShift   // 语音翻译 start
    case fnSpace   // 任意提问 start
    case fnTap     // 结束键（再按 Fn 结束）
    case fnV       // 来源核验（划词菜单触发键 fn+V）

    var keycaps: [String] {
        switch self {
        case .fnShift: ["Fn", "Shift"]
        case .fnSpace: ["Fn", "Space"]
        case .fnTap:   ["Fn"]
        case .fnV:     ["Fn", "V"]
        }
    }

    var prompt: String {
        switch self {
        case .fnShift: "按 Fn Shift 说中文"
        case .fnSpace: "按 Fn Space 问一句"
        case .fnTap:   "再按 Fn 结束"
        case .fnV:     "按 Fn V 核对原文"
        }
    }

    /// Pure predicate (unit-tested). `keyCode` 49 = Space, 9 = V.
    nonisolated static func matches(type: NSEvent.EventType,
                                    modifiers: NSEvent.ModifierFlags,
                                    keyCode: UInt16,
                                    gesture: SandboxGesture) -> Bool {
        switch gesture {
        case .fnShift:
            return type == .flagsChanged && modifiers.contains(.function) && modifiers.contains(.shift)
        case .fnSpace:
            return type == .keyDown && keyCode == 49 && modifiers.contains(.function)
        case .fnTap:
            return type == .flagsChanged && modifiers.contains(.function)
        case .fnV:
            return type == .keyDown && keyCode == 9 && modifiers.contains(.function)
        }
    }
}

@MainActor
final class SandboxGestureMonitor {
    private var monitor: Any?

    func start(_ gesture: SandboxGesture, onTrigger: @escaping @MainActor () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if SandboxGesture.matches(type: event.type, modifiers: event.modifierFlags,
                                      keyCode: event.keyCode, gesture: gesture) {
                Task { @MainActor in onTrigger() }
            }
            return event   // never swallow the user's keystroke
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
