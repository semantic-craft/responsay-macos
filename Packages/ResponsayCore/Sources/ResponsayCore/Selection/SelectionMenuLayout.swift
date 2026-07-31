import Foundation

/// A concrete item the 划词菜单 renders — a built-in action or an enabled 划词生成 技能.
/// Uniform `[icon][label]` (the grill outcome): third-party skills have no bespoke icon, so they
/// fall back to a generic glyph and rely on their title.
public enum SelectionMenuItem: Equatable, Sendable, Identifiable {
    case action(SelectionAction)
    case skill(id: String, title: String)

    public var id: String {
        switch self {
        case let .action(action): return action.rawValue
        case let .skill(id, _): return id
        }
    }

    public var title: String {
        switch self {
        case let .action(action): return action.title
        case let .skill(_, title): return title
        }
    }

    public var systemImage: String {
        switch self {
        case let .action(action): return action.systemImage
        case .skill: return "wand.and.stars"   // generic — imported skills carry no bespoke icon
        }
    }
}

/// The single source of truth that links 技能库 ↔ 划词菜单 (用户可配置顺序 + show/hide).
///
/// The 技能库 *writes* it (drag = reorder `entries`, toggle = `visible`); the 划词菜单 *reads* it
/// via `resolve`. Each entry references an item by **stable id** — a `SelectionAction.rawValue` or a
/// skill id — so "the item in the library" and "the item in the menu" are the same thing. Hidden or
/// reordered in the library → changed in the menu, because both sides share this one store.
public struct SelectionMenuLayout: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var id: String       // SelectionAction.rawValue or a skill id
        public var visible: Bool
        public init(id: String, visible: Bool = true) {
            self.id = id
            self.visible = visible
        }
    }

    public var entries: [Entry]
    public init(entries: [Entry]) { self.entries = entries }

    /// Every built-in action the user may order / hide — now including 翻译/朗读 (they used to be the
    /// fixed instant-row tools; the menu's icon row is dynamic, so they're configurable too). Single
    /// source for both `.default` and the 技能库 editor, so the two can't drift.
    public static let configurableActions: [SelectionAction] =
        [.translate, .readAloud, .verify, .assistedSearch, .normalizeTypography, .ask, .addToDictionary]

    /// Out-of-box order: 翻译/朗读 are the quick icon-row pair, then legal/research; 划词生成 技能
    /// are dynamic and join on enable.
    public static let `default` = SelectionMenuLayout(
        entries: configurableActions.map { Entry(id: $0.rawValue) })

    public func contains(_ id: String) -> Bool { entries.contains { $0.id == id } }

    /// Merge the items available **right now** (actions the resolver allows for this selection +
    /// the user's enabled 划词生成 技能) with this layout. Returns what the menu renders:
    /// visible layout entries in layout order that are currently available, then any available
    /// item not yet in the layout (a freshly-enabled skill / new action) appended visible.
    /// An entry that isn't currently available (action irrelevant to this selection, skill
    /// disabled) is skipped but **kept in the layout** for when it returns.
    public func resolve(
        availableActions: [SelectionAction],
        availableSkills: [(id: String, title: String)]
    ) -> [SelectionMenuItem] {
        let actionByID = Dictionary(uniqueKeysWithValues: availableActions.map { ($0.rawValue, $0) })
        let skillByID = Dictionary(availableSkills.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })

        var items: [SelectionMenuItem] = []
        for entry in entries where entry.visible {
            if let action = actionByID[entry.id] {
                items.append(.action(action))
            } else if let title = skillByID[entry.id] {
                items.append(.skill(id: entry.id, title: title))
            }
        }
        for action in availableActions where !contains(action.rawValue) {
            items.append(.action(action))
        }
        for skill in availableSkills where !contains(skill.id) {
            items.append(.skill(id: skill.id, title: skill.title))
        }
        return items
    }

    // MARK: - Editor (技能库 划词菜单 editor)

    /// One row in the 划词菜单 editor: an item plus whether it's shown. Unlike `resolve`, the editor
    /// keeps **hidden** rows (so the user can toggle them back on) — `visible` carries that state.
    public struct EditorRow: Identifiable, Equatable, Sendable {
        public let item: SelectionMenuItem
        public var visible: Bool
        public var id: String { item.id }
        public init(item: SelectionMenuItem, visible: Bool) {
            self.item = item
            self.visible = visible
        }
    }

    /// Every configurable item the editor lists: layout entries (in order, with their visibility),
    /// then any available item not yet in the layout (a newly-enabled skill / action), appended
    /// visible. Entries whose item isn't currently available (a disabled skill) are skipped.
    public func editorRows(
        availableActions: [SelectionAction],
        availableSkills: [(id: String, title: String)]
    ) -> [EditorRow] {
        let actionByID = Dictionary(uniqueKeysWithValues: availableActions.map { ($0.rawValue, $0) })
        let skillByID = Dictionary(availableSkills.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })

        var rows: [EditorRow] = []
        var placed = Set<String>()
        for entry in entries {
            if let action = actionByID[entry.id] {
                rows.append(EditorRow(item: .action(action), visible: entry.visible))
                placed.insert(entry.id)
            } else if let title = skillByID[entry.id] {
                rows.append(EditorRow(item: .skill(id: entry.id, title: title), visible: entry.visible))
                placed.insert(entry.id)
            }
        }
        for action in availableActions where !placed.contains(action.rawValue) {
            rows.append(EditorRow(item: .action(action), visible: true))
            placed.insert(action.rawValue)
        }
        for skill in availableSkills where !placed.contains(skill.id) {
            rows.append(EditorRow(item: .skill(id: skill.id, title: skill.title), visible: true))
        }
        return rows
    }

    /// Rebuild a layout from the editor's (reordered / toggled) rows — the inverse of `editorRows`.
    public static func from(rows: [EditorRow]) -> SelectionMenuLayout {
        SelectionMenuLayout(entries: rows.map { Entry(id: $0.item.id, visible: $0.visible) })
    }
}
