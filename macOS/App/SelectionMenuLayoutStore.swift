import Foundation
import ResponsayCore

/// UserDefaults-backed store for the user's 划词菜单 smart-row layout (order + show/hide). The
/// 技能库 editor writes it; `CaptureSelectionController` reads it to resolve what the menu renders.
/// Missing / corrupt → `.default` (so a fresh install gets the curated legal-first order).
enum SelectionMenuLayoutStore {
    static let key = "selectionMenuLayout"

    static func load() -> SelectionMenuLayout {
        guard let data = UserDefaults.standard.data(forKey: key),
              let layout = try? JSONDecoder().decode(SelectionMenuLayout.self, from: data) else {
            return .default
        }
        return layout
    }

    static func save(_ layout: SelectionMenuLayout) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
