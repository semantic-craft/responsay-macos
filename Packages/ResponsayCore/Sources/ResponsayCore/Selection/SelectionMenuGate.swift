import Foundation

/// Narrows the content-appropriate `SelectionAction`s (from `SelectionActionResolver`) to those the
/// user has actually 激活 in the 技能平台 — the contract asked for: 翻译 / 朗读 / 加入词典 / 任意提问
/// are fixed and always offered; 引注源验 / 来源辅助检索 / 规范排版 appear only once their backing
/// skill / 工具 is on. Pure over injected enable-state, so the live menu
/// (`CaptureSelectionController`) and the 划词菜单 设置面板 filter identically and it is unit-testable.
public struct SelectionMenuGate: Sendable {
    public let enabledSkillIDs: Set<String>
    public let enabledTools: Set<SelectionTool>

    public init(enabledSkillIDs: Set<String>, enabledTools: Set<SelectionTool>) {
        self.enabledSkillIDs = enabledSkillIDs
        self.enabledTools = enabledTools
    }

    /// App-runtime convenience: read enable-state straight from the standard stores.
    public init(
        skillStore: EnabledLegalSkillStore = EnabledLegalSkillStore(),
        toolStore: EnabledSelectionToolStore = EnabledSelectionToolStore()
    ) {
        self.enabledSkillIDs = skillStore.enabledIDs
        self.enabledTools = toolStore.enabledTools
    }

    public func isAvailable(_ action: SelectionAction) -> Bool {
        switch action.gate {
        case .always:         return true
        case .skill(let id):  return enabledSkillIDs.contains(id)
        case .tool(let tool): return enabledTools.contains(tool)
        }
    }

    /// Order-preserving filter — the layout / resolver order is untouched.
    public func available(from actions: [SelectionAction]) -> [SelectionAction] {
        actions.filter(isAvailable)
    }
}
