import Foundation

/// The four hands-on flows in the guided sandbox sequence (实操体验), in order. Every flow is real to
/// the touch — the user presses the actual keys; only the *result* is a labelled 示例 when no model
/// is configured. Each flow owns its real-vs-sample behaviour:
///   - 听写 records real speech (`SandboxDictateFlow`);
///   - 语音翻译 is a hands-on sim — Fn Shift → speak → Fn end → 示例 译文 (`SandboxSpokenFlow`);
///   - 任意提问 划选 a passage (tap-to-select) → Fn Space → speak → Fn end → 示例 答卡 about it
///     (`SandboxSpokenFlow` with a `selectionPassage`);
///   - 来源核验 划选 a citation → **fn+V** → jump to 知网 to check 熊伟 的原文 (`SandboxVerifyFlow`).
enum SandboxFlow: Int, CaseIterable, Identifiable, Sendable {
    case dictate     // 听写
    case translate   // 语音翻译
    case ask         // 任意提问（划词提问）
    case verify      // 来源核验

    var id: Int { rawValue }
}
