import AppKit
import AVFoundation
import KeyboardShortcuts
import Observation
import ResponsayCore

/// The status bar, de-SwiftUI-ed (#576). Classic `NSStatusItem` + `NSMenu`, built fresh on
/// every open via `menuNeedsUpdate` with plain imperative reads — no scene, no @AppStorage
/// subscriptions, no hosting windows.
///
/// Why: crashes 1–7 (1.4.14 → 1.4.19) all died in macOS 26's display-cycle loop breaker on a
/// framework-owned SwiftUI window. #574's window-inventory forensics showed EIGHT full-width
/// MenuBarExtra hosting strips per snapshot, recreated at will, and the fatal window was born
/// within 90ms of an intent insert — the moment alias-learning writes UserDefaults, which the
/// menu content's live @AppStorage subscriptions turned into scene re-evaluation. A constant
/// label (#573/#574) starved the icon but not the scene. AppKit status items have carried
/// mutable icons and dynamic menus safely for two decades; the red listening icon returns.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private unowned let controller: CaptureController

    init(controller: CaptureController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
            button.setAccessibilityLabel(AppBrand.displayName)
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        observeListeningState()
    }

    // MARK: - Listening state (red icon — safe again in AppKit)

    private func observeListeningState() {
        withObservationTracking {
            _ = self.controller.vm.phase
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyIcon()
                self.observeListeningState()
            }
        }
    }

    private func applyIcon() {
        guard let button = statusItem.button else { return }
        let listening = controller.vm.phase == .listening
        button.image = NSImage(named: listening ? "MenuBarIconActive" : "MenuBarIcon")
        button.image?.isTemplate = !listening
        button.setAccessibilityLabel(
            listening ? "\(AppBrand.displayName) 正在听" : AppBrand.displayName)
    }

    // MARK: - Menu (fresh per open; imperative reads, zero live subscriptions)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item("打开主面板") { MainWindowController.shared.show() })
        let onboardingCompleted = UserDefaults.standard.bool(forKey: OnboardingWindowController.completedKey)
        menu.addItem(item(onboardingCompleted ? "重看新手引导…" : "继续首次设置…") {
            OnboardingWindowController.shared.show()
        })

        menu.addItem(.separator())
        menu.addItem(modelSubmenu(
            title: "语音识别服务：\(asrTitle)",
            options: ModelRouteCatalog.asrOptions,
            current: ModelRouteCatalog.currentASRId(),
            readiness: { self.readiness.asr(optionId: $0) },
            groupByBadge: true) { raw in
                ModelRouteSelectionActions.applyASRSelection(raw)
                ASRResidencyPrewarm.onSelection(raw)
                if let section = MenuModelSelection.sectionToConfigure(forASR: raw) {
                    MacSettingsWindowController.shared.show(section: section)
                }
            })
        menu.addItem(modelSubmenu(
            title: "文本改写：\(coachTitle)",
            options: ModelRouteCatalog.llmOptions,
            current: ModelRouteCatalog.currentLLMId(),
            readiness: { self.readiness.llm(optionId: $0) }) { id in
                ModelRouteSelectionActions.applyLLMSelection(id)
                if let section = MenuModelSelection.sectionToConfigure(forLLM: id) {
                    MacSettingsWindowController.shared.show(section: section)
                }
            })
        menu.addItem(modelSubmenu(
            title: "文本朗读：\(ttsTitle)",
            options: ModelRouteCatalog.ttsOptions,
            current: ModelRouteCatalog.currentTTSId(),
            readiness: { self.readiness.tts(optionId: $0) }) { id in
                ModelRouteSelectionActions.applyTTSSelection(id)
                if let section = MenuModelSelection.sectionToConfigure(forTTS: id) {
                    MacSettingsWindowController.shared.show(section: section)
                }
            })

        menu.addItem(.separator())
        let lightRewrite = DictationRewriteSettings.lightRewriteEnabled()
        let faithful = item("如实输入") {
            UserDefaults.standard.set(!DictationRewriteSettings.lightRewriteEnabled(), forKey: DictationRewriteSettings.key)
        }
        faithful.state = lightRewrite ? .off : .on
        menu.addItem(faithful)
        menu.addItem(caption(lightRewrite
            ? "默认帮你整理听写（补标点、去口癖、顺句）。想只用语音原文、不过大模型，就打开「如实输入」。"
            : "已开「如实输入」：只上屏语音识别原文，不过大模型整理。关掉即恢复默认整理。"))

        menu.addItem(.separator())
        menu.addItem(actionItem("地道外文", .expressInEnglish) { self.controller.triggerExpressInEnglish() })
        menu.addItem(caption("说目标外文或不顺的外文，得到 Native Speaker 说法——并告诉你为什么这样说，可朗读"))

        menu.addItem(.separator())
        menu.addItem(actionItem("截图翻译", .snapOCR) { self.controller.snapOCR() })
        menu.addItem(item("截图取字") { self.controller.snapTextOCR() })
        menu.addItem(actionItem("截图复制", .snapImageCopy) { self.controller.snapImageCopy() })

        menu.addItem(.separator())
        menu.addItem(micSubmenu())
        let settings = item("设置…") { MacSettingsWindowController.shared.show() }
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = .command
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = item("退出 \(AppBrand.displayName)") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
    }

    // MARK: - Submenus

    private func modelSubmenu(
        title: String,
        options: [CurrentModelOption],
        current: String,
        readiness: @escaping (String) -> ModelLaneReadiness,
        groupByBadge: Bool = false,
        select: @escaping (String) -> Void
    ) -> NSMenuItem {
        let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        let visible = MenuModelSelection.configuredOptions(options, current: current, readiness: readiness)
        func add(_ group: [CurrentModelOption]) {
            for option in group {
                let entry = item(option.title) { select(option.id) }
                entry.state = option.id == current ? .on : .off
                submenu.addItem(entry)
            }
        }
        if groupByBadge {
            let cloud = visible.filter { $0.badge == "云端" }
            let local = visible.filter { $0.badge == "本机" }
            if !cloud.isEmpty {
                submenu.addItem(sectionHeader("云端"))
                add(cloud)
            }
            if !local.isEmpty {
                submenu.addItem(sectionHeader("本机"))
                add(local)
            }
        } else {
            add(visible)
        }
        root.submenu = submenu
        return root
    }

    private func micSubmenu() -> NSMenuItem {
        let root = NSMenuItem(title: "选择麦克风", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "选择麦克风")
        let currentUID = UserDefaults.standard.string(forKey: "micDeviceID") ?? ""
        func micItem(_ name: String, uid: String) -> NSMenuItem {
            let entry = item(name) { UserDefaults.standard.set(uid, forKey: "micDeviceID") }
            entry.state = currentUID == uid ? .on : .off
            return entry
        }
        submenu.addItem(micItem("系统默认", uid: ""))
        for device in AVCaptureDevice.devices(for: .audio) {
            submenu.addItem(micItem(device.localizedName, uid: device.uniqueID))
        }
        root.submenu = submenu
        return root
    }

    // MARK: - Item helpers

    private final class ClosureMenuItem: NSMenuItem {
        var handler: (() -> Void)?
        @objc func invoke() { handler?() }
    }

    private func item(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let entry = ClosureMenuItem(title: title, action: #selector(ClosureMenuItem.invoke), keyEquivalent: "")
        entry.handler = handler
        entry.target = entry
        return entry
    }

    /// Mirrors the SwiftUI menu's inline shortcut hint — read live from
    /// `ShortcutSettingsStore`, never hardcoded.
    private func actionItem(_ title: String, _ action: ShortcutAction, _ handler: @escaping () -> Void) -> NSMenuItem {
        if let shortcut = shortcutDisplay(for: action) {
            return item("\(title)   \(shortcut)", handler)
        }
        return item(title, handler)
    }

    private func caption(_ text: String) -> NSMenuItem {
        let entry = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        entry.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        entry.isEnabled = false
        return entry
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private var readiness: ModelLaneReadinessResolver { ModelLaneReadinessResolver() }

    private var asrTitle: String {
        let (base, _) = ModelRouteOptionID.parse(ModelRouteCatalog.currentASRId())
        return ASREngine.fromStoredValue(base)?.title ?? ASREngine.apple.title
    }

    private var ttsTitle: String {
        let raw = UserDefaults.standard.string(forKey: TTSEngine.defaultsKey) ?? ""
        return TTSEngine(rawValue: raw)?.title ?? TTSEngine.selected.title
    }

    private var coachTitle: String {
        let pid = UserDefaults.standard.string(forKey: "byok.llm.provider") ?? ""
        if let preset = ProviderCatalog.presets(for: .llm).first(where: { $0.id == pid }) {
            return preset.displayName(for: .llm)
        }
        return "自定义 OpenAI 兼容"
    }

    private func shortcutDisplay(for action: ShortcutAction) -> String? {
        guard let binding = ShortcutSettingsStore.shared.bindings(for: action).first else { return nil }
        switch binding.family {
        case .fn:
            return binding.fnChord?.displayString
        case .normal:
            guard let index = binding.normalSlotIndex else { return nil }
            return KeyboardShortcuts.getShortcut(for: NormalShortcutSlot(action: action, index: index).name)?.description
        }
    }
}
