import Foundation

/// Drives the guided sandbox flow order + progress (实操体验 sequence, spec §4.2).
/// `下一个` and `跳过此项` both advance; `跳过实操` jumps to the end.
struct SandboxSequence: Sendable, Equatable {
    let flows: [SandboxFlow]
    private(set) var index: Int = 0

    init(flows: [SandboxFlow] = SandboxFlow.allCases) {
        self.flows = flows
    }

    var current: SandboxFlow? { index < flows.count ? flows[index] : nil }
    var isComplete: Bool { index >= flows.count }
    /// "2/5"-style progress (clamped at the last flow).
    var progress: String { "\(min(index + 1, flows.count))/\(flows.count)" }

    /// 下一个 / 跳过此项 — move to the next flow (caps at the end).
    mutating func advance() {
        if index < flows.count { index += 1 }
    }

    /// 返回 — step back one flow (clamped at the first).
    mutating func back() {
        if index > 0 { index -= 1 }
    }

    /// 跳过实操 — jump to the end.
    mutating func skipAll() {
        index = flows.count
    }
}
