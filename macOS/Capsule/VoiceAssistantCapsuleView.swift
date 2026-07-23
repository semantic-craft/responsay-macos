import SwiftUI
import AppKit
import ResponsayCore

/// 任意提问 control pill — a **compact sibling** of the dictation pill, not a separate panel
/// (Capsule System redesign). It renders the shared `UnifiedCapsule` in `.ask` mode: same
/// silhouette, surface and rhythm as dictation, distinguished only by a small "任意提问 · 倾听中…"
/// label floating above (with a soft pulsing wine halo).
///
/// Thin adapter: it maps `VoiceAssistantViewModel` onto `UnifiedCapsule`'s value inputs and
/// owns the local timer + the listening→thinking haptic. All visual anatomy lives in
/// `UnifiedCapsule`. Rendered in a fixed-size, non-activating panel that never resizes
/// mid-stream; the visible ✕ / ✓ affordances mirror Esc / hotkey finish.
@MainActor
struct VoiceAssistantCapsuleView: View {
    var vm: VoiceAssistantViewModel
    @AppStorage("useAdvancedHaptics") private var useAdvancedHaptics = true

    var body: some View {
        UnifiedCapsule(
            mode: .ask,
            phase: askPhase,
            level: vm.level,
            thinkingLabel: vm.searchProviderId != nil ? "联网搜索中" : "思考中",
            // statusText left empty → the capsule shows its design default ("暂时无法回答").
            askLabelText: askLabelText,
            askSource: askSource,
            cancelAction: {
                Task { @MainActor in
                    await vm.cancelCapture()
                    vm.clearConversation()
                }
            },
            finishAction: {
                Task { @MainActor in
                    await vm.stopCapture(client: vm.makeClient?())
                }
            }
        )
        .padding(20)  // room for shadow + halo inside the panel bounds
        .onChange(of: vm.phase) { old, new in
            if useAdvancedHaptics, old == .listening, new == .thinking {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
        }
    }

    /// Map the VM phase onto the shared capsule phase. An error mid-listen surfaces as the
    /// capsule's error state; `.responding` / `.idle` are handled by the result panel, not here.
    private var askPhase: CapsulePhase {
        if vm.errorMessage != nil, vm.phase == .listening { return .error }
        switch vm.phase {
        case .listening:           return .listening
        case .thinking:            return .thinking
        case .responding, .idle:   return .idle
        }
    }

    /// Identity label above the pill. Keep the stop hint visible: the ask hotkey is a toggle.
    /// Compact to「任意提问」during thinking/search so the 联网模型署名 chip has room.
    private var askLabelText: String {
        if vm.phase == .thinking { return "任意提问" }
        if !vm.messages.isEmpty { return "任意提问 · 追问中 · 再按 Fn 结束" }
        if vm.selectionContext != nil { return "任意提问 · 针对选区 · 再按 Fn 结束" }
        return "任意提问 · 再按 Fn 结束"
    }

    /// 联网搜索时(思考阶段)在浮标签里露出当前联网模型署名(设计稿 ask-anything-capsule Variant B)。
    private var askSource: CapsuleSearchSource? {
        guard vm.phase == .thinking, let id = vm.searchProviderId else { return nil }
        return VoiceAssistantSearchModelSettings.capsuleSource(for: id)
    }
}
