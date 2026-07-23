import AppKit
import SwiftUI

/// Hosts the first-run onboarding wizard in a fixed-size AppKit window (mirrors
/// `MacSettingsWindowController`). Shows on first launch; `onFinish` marks it complete and closes.
///
/// Two dead-ends fixed in issue 313:
/// - Closing the window mid-wizard no longer strands the session: it posts
///   `.onboardingDeferred` ("稍后完成") so the app starts capture anyway, and the
///   menu bar offers 「继续首次设置…」 to come back.
/// - A revoked permission after a completed onboarding opens the single
///   permissions-repair pane (`showPermissionsRepair`), never the full 9-step
///   wizard — and repair NEVER runs `OnboardingModel.commit()`, which would
///   overwrite the user's live engine/shortcut configuration with defaults.
@MainActor
final class OnboardingWindowController: NSObject {
    static let shared = OnboardingWindowController()
    static let completedKey = "onboarding.completed"

    private var window: NSWindow?
    /// True once finish() ran for the current presentation — distinguishes a
    /// deliberate completion close from a mid-wizard "稍后完成" close.
    private var finished = false
    private var repairMode = false

    /// Show only if onboarding hasn't been completed (no-op afterwards).
    func showIfFirstRun() {
        guard !UserDefaults.standard.bool(forKey: Self.completedKey) else { return }
        show()
    }

    /// The full wizard (resumes the saved step). Also the menu-bar re-entry.
    func show() {
        finished = false
        repairMode = false
        let root = AnyView(OnboardingView(onFinish: { [weak self] in self?.finish() })
            .environment(AppearanceStore.shared))
        present(root: root, size: NSSize(width: 860, height: 620), title: "欢迎使用 Responsay")
    }

    /// 权限回收修复（313）：只呈现权限单步 + 完成按钮，关窗即结束。
    func showPermissionsRepair() {
        finished = false
        repairMode = true
        let root = AnyView(PermissionsRepairView(onDone: { [weak self] in self?.window?.close() })
            .environment(AppearanceStore.shared))
        present(root: root, size: NSSize(width: 640, height: 600), title: "补齐权限")
    }

    private func present(root: AnyView, size: NSSize, title: String) {
        // Recreate per presentation: full wizard vs repair differ in size/content,
        // and a fresh hosting controller avoids stale @State across modes.
        window?.delegate = nil
        window?.close()
        let controller = NSHostingController(rootView: root)
        // #569: the window is the size authority (fixed per presentation, set below) —
        // don't let the hosting controller rewrite its min/max or resize it toward content.
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.delegate = self
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        finished = true
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
        window?.close()
    }
}

extension OnboardingWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Mid-wizard close = "稍后完成": let the app run with whatever permissions
        // exist instead of a dead session (the old behavior required a relaunch).
        // Repair-mode close needs no signal — capture already started.
        guard !finished, !repairMode,
              !UserDefaults.standard.bool(forKey: Self.completedKey) else { return }
        NotificationCenter.default.post(name: .onboardingDeferred, object: nil)
    }
}

extension Notification.Name {
    /// Posted when the user closes the wizard before finishing (313).
    static let onboardingDeferred = Notification.Name("onboardingDeferred")
}

/// The standalone permissions-repair pane: the wizard's permissions step content
/// with its own footer, no rail, no commit.
private struct PermissionsRepairView: View {
    @Environment(AppearanceStore.self) private var appearance
    @State private var model = OnboardingModel()
    var onDone: () -> Void

    var body: some View {
        let p = appearance.palette
        VStack(spacing: 0) {
            ScrollView {
                PermissionsStepView(model: model)
                    .padding(EdgeInsets(top: 30, leading: 36, bottom: 24, trailing: 36))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("授权在系统设置里生效后，上方会自动打勾。")
                    .font(.system(size: 12)).foregroundStyle(p.ink3)
                Spacer()
                Button { onDone() } label: {
                    Text("完成").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(p.accent)
            }
            .padding(EdgeInsets(top: 12, leading: 36, bottom: 16, trailing: 36))
        }
        .background(p.bg)
    }
}
