import AppKit
import ResponsayCore

/// 来源核验 source picker — pops a native, grouped NSMenu at the cursor so the user
/// chooses WHICH source to verify against (法规 / 案例 / 文献 / 兜底). Replaces the old
/// "auto-open up to 4 sites" behavior: one pick, one source (ADR-0022 stays a gated,
/// opinionated action — never a free-form box). The grouped model comes from Core's
/// `SelectionVerifyMenu`; this layer only renders + reports the pick.
@MainActor
final class SelectionVerifyMenuController: NSObject {
    private var onPick: ((VerifyMenuItem) -> Void)?

    /// Present the menu at a screen point (e.g. `NSEvent.mouseLocation`). `popUp` tracks
    /// modally and fires the pick synchronously before returning.
    func present(groups: [VerifyMenuGroup], at screenPoint: CGPoint,
                 onPick: @escaping (VerifyMenuItem) -> Void) {
        guard !groups.isEmpty else { return }
        self.onPick = onPick

        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, group) in groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            let header = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for item in group.items {
                let entry = NSMenuItem(title: "  \(item.title)", action: #selector(didPick(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = item
                menu.addItem(entry)
            }
        }
        menu.popUp(positioning: nil, at: screenPoint, in: nil)
    }

    @objc private func didPick(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? VerifyMenuItem else { return }
        onPick?(item)
    }
}
