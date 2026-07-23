import Foundation

/// Which deterministic 划词 tools (`SelectionTool`) are 激活 in the 技能平台「工具」区.
///
/// Kept separate from `EnabledLegalSkillStore` on purpose: tools are not skills, and — crucially —
/// their default differs. The skill set's "never set" state means "the curated defaults"; a tool
/// instead defaults to **enabled**, so a user upgrading into this gating keeps 规范排版 in their
/// menu until they explicitly turn it off. We get that for free by persisting only the *disabled*
/// state: a missing key reads as enabled.
public struct EnabledSelectionToolStore {
    /// One key per tool: `tool.<id>.disabled`. Storing the disabled flag (not an enabled flag) is
    /// what makes "never set" == enabled — `bool(forKey:)` defaults to `false`.
    static func disabledKey(_ tool: SelectionTool) -> String { "\(tool.rawValue).disabled" }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnabled(_ tool: SelectionTool) -> Bool {
        !defaults.bool(forKey: Self.disabledKey(tool))
    }

    /// Persist only the disabled state so an untouched tool stays enabled by default.
    public func setEnabled(_ enabled: Bool, tool: SelectionTool) {
        defaults.set(!enabled, forKey: Self.disabledKey(tool))
    }

    public var enabledTools: Set<SelectionTool> {
        Set(SelectionTool.allCases.filter(isEnabled))
    }
}
