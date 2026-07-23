import Foundation
import KeyboardShortcuts
import Observation
import OSLog
import ResponsayCore

@MainActor
@Observable
final class ShortcutSettingsStore {
    static let shared = ShortcutSettingsStore()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: AppBrand.loggerSubsystem, category: "shortcut-settings")

    enum Keys {
        static let fnHotkeyEnabled = "fnHotkeyEnabled"
        static let rightOptionHotkeyEnabled = "rightOptionHotkeyEnabled"
        static let snapshot = "shortcutSettings.v1"
        static let didMigrate = "shortcutSettings.didMigrate.v1"
    }

    /// Suppresses the `didSet` write-back while we're *loading* from defaults, so
    /// `UserDefaults.didChangeNotification` → `refreshFromDefaults()` → set →
    /// write → notification can't recurse into a stack overflow (crash fix).
    @ObservationIgnored private var isApplyingDefaults = false
    @ObservationIgnored static let currentFnDefaults: [ShortcutBinding] = [
        .fn(action: .raw, chord: .fnOnly),
        .fn(action: .translate, chord: .fnShift),
        .fn(action: .askAnything, chord: .fnSpace),
        .fn(action: .expressInEnglish, chord: .fnE),
        .fn(action: .selectionMenu, chord: .fnV),
    ]
    @ObservationIgnored private static let snapshotVersionTwoAdditions: [ShortcutBinding] = [
        .fn(action: .translate, chord: .fnShift),
        .fn(action: .askAnything, chord: .fnSpace),
    ]

    var fnHotkeyEnabled: Bool {
        didSet {
            guard fnHotkeyEnabled != oldValue, !isApplyingDefaults else { return }
            defaults.set(fnHotkeyEnabled, forKey: Keys.fnHotkeyEnabled)
        }
    }

    var rightOptionHotkeyEnabled: Bool {
        didSet {
            guard rightOptionHotkeyEnabled != oldValue, !isApplyingDefaults else { return }
            defaults.set(rightOptionHotkeyEnabled, forKey: Keys.rightOptionHotkeyEnabled)
        }
    }

    private(set) var fnBindings: [ShortcutBinding]
    private(set) var normalRevision: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.fnHotkeyEnabled = defaults.object(forKey: Keys.fnHotkeyEnabled) as? Bool ?? true
        self.rightOptionHotkeyEnabled = Self.initialRightOptionEnabled(defaults: defaults)
        self.fnBindings = []
        self.normalRevision = 0
        loadOrMigrate()
    }

    func refreshFromDefaults() {
        let refreshedFnHotkeyEnabled = defaults.object(forKey: Keys.fnHotkeyEnabled) as? Bool ?? true
        if fnHotkeyEnabled != refreshedFnHotkeyEnabled {
            isApplyingDefaults = true
            fnHotkeyEnabled = refreshedFnHotkeyEnabled
            isApplyingDefaults = false
        }
        let refreshedRightOptionHotkeyEnabled = Self.initialRightOptionEnabled(defaults: defaults)
        if rightOptionHotkeyEnabled != refreshedRightOptionHotkeyEnabled {
            isApplyingDefaults = true
            rightOptionHotkeyEnabled = refreshedRightOptionHotkeyEnabled
            isApplyingDefaults = false
        }
        if let snapshot = loadSnapshot() {
            let migratedBindings = snapshot.schemaVersion < ShortcutSettingsSnapshot.currentVersion
                ? migratedSnapshotBindings(snapshot.fnBindings)
                : snapshot.fnBindings
            let refreshedBindings = Self.sanitizedBindings(migratedBindings)
            if fnBindings != refreshedBindings {
                fnBindings = refreshedBindings
            }
        }
    }

    func bindings(for action: ShortcutAction) -> [ShortcutBinding] {
        _ = normalRevision

        let normalBindings = NormalShortcutSlot.slots(for: action)
            .filter { $0.name.shortcut != nil }
            .map { ShortcutBinding.normal(action: action, slotIndex: $0.index) }
        let fnBindingsForAction = fnBindings
            .filter { $0.action == action && $0.isEnabled }

        return normalBindings + fnBindingsForAction
    }

    func firstEmptyNormalSlot(for action: ShortcutAction) -> NormalShortcutSlot? {
        NormalShortcutSlot.slots(for: action)
            .first { $0.name.shortcut == nil }
    }

    func normalShortcutDidChange() {
        normalRevision += 1
    }

    func action(for chord: FnChord) -> ShortcutAction? {
        guard isAnchorEnabled(chord.anchor) else {
            return nil
        }

        let matches = fnBindings.filter {
            $0.isEnabled && $0.family == .fn && $0.fnChord == chord
        }

        guard matches.count == 1 else {
            if matches.count > 1 {
                logger.error("Conflicting Fn chord ignored: \(chord.id, privacy: .public)")
            }
            return nil
        }

        return matches[0].action
    }

    func addFnBinding(action: ShortcutAction, chord: FnChord) throws {
        if let existing = fnBindings.first(where: {
            $0.isEnabled && $0.fnChord == chord && $0.action != action
        }) {
            throw ShortcutSettingsError.conflict(existingAction: existing.action)
        }

        guard !fnBindings.contains(where: { $0.action == action && $0.fnChord == chord }) else {
            return
        }

        fnBindings.append(.fn(action: action, chord: chord))
        save()
    }

    func isAnchorEnabled(_ anchor: ShortcutAnchor) -> Bool {
        switch anchor {
        case .fn:
            fnHotkeyEnabled
        case .rightOption:
            rightOptionHotkeyEnabled
        }
    }

    func setAnchorEnabled(_ isEnabled: Bool, anchor: ShortcutAnchor) {
        switch anchor {
        case .fn:
            fnHotkeyEnabled = isEnabled
        case .rightOption:
            rightOptionHotkeyEnabled = isEnabled
        }
    }

    func remove(_ binding: ShortcutBinding) {
        switch binding.family {
        case .normal:
            guard let index = binding.normalSlotIndex else {
                return
            }
            let slot = NormalShortcutSlot(action: binding.action, index: index)
            KeyboardShortcuts.setShortcut(nil, for: slot.name)
            normalShortcutDidChange()
        case .fn:
            fnBindings.removeAll { $0.id == binding.id }
            save()
        }
    }

    /// Reset to the Fn-centered default: clear every normal binding and leave the out-of-the-box
    /// shortcuts `Fn → 语音输入`, `Fn Shift → 听写翻译`, and `Fn Space → 任意提问`.
    /// The user assigns any further Fn+letter shortcuts themselves via each function's
    /// 「添加另一个」recorder — we don't prescribe a letter scheme. Lets a machine that ran an older build (whose
    /// complex `⌃⌥⌘` defaults `KeyboardShortcuts` persisted) return to the clean
    /// default without a fresh install. See ADR-0018.
    func resetToFnDefault() {
        resetToAnchorDefault(.fn, clearNormalBindings: true)
    }

    func resetToRightOptionDefault() {
        resetToAnchorDefault(.rightOption, clearNormalBindings: false)
    }

    func resetToAnchorDefault(_ anchor: ShortcutAnchor, clearNormalBindings: Bool = false) {
        if clearNormalBindings {
            for action in ShortcutAction.visibleInShortcutSettings {
                for slot in NormalShortcutSlot.slots(for: action) {
                    KeyboardShortcuts.setShortcut(nil, for: slot.name)
                }
            }
        }
        fnBindings.removeAll { $0.fnChord?.anchor == anchor }
        fnBindings.append(contentsOf: Self.resetBindings(for: anchor, defaults: defaults))
        setAnchorEnabled(true, anchor: anchor)
        save()
        if clearNormalBindings { normalShortcutDidChange() }
        logger.info("Shortcuts reset for anchor \(anchor.rawValue, privacy: .public)")
    }

    /// Reset to the non-Fn 「其他组合」 scheme: classic `⌃⌥⌘` combos on the slot-0
    /// normal shortcuts, Fn family off. The second of the two selectable shortcut
    /// schemes (Settings: 围绕 Fn vs 其他组合).
    func resetToNormalDefault() {
        fnBindings = []
        if fnHotkeyEnabled { fnHotkeyEnabled = false }
        if rightOptionHotkeyEnabled { rightOptionHotkeyEnabled = false }
        let combos: [(ShortcutAction, KeyboardShortcuts.Shortcut)] = [
            (.raw, .init(.y, modifiers: [.control, .option, .command])),
            (.polish, .init(.y, modifiers: [.control, .option, .command, .shift])),
            (.expressInEnglish, .init(.e, modifiers: [.control, .option, .command])),
            (.rewriteSelection, .init(.r, modifiers: [.option])),
            // .legalPalette retired (划词技能互动) — no ⌥L seed; selection skills live in the 划词菜单.
        ]
        for (action, shortcut) in combos {
            KeyboardShortcuts.setShortcut(shortcut, for: NormalShortcutSlot(action: action, index: 0).name)
        }
        save()
        normalShortcutDidChange()
        logger.info("Shortcuts reset to non-Fn combo default")
    }

    private func loadOrMigrate() {
        if let snapshot = loadSnapshot() {
            let migratedBindings = snapshot.schemaVersion < ShortcutSettingsSnapshot.currentVersion
                ? migratedSnapshotBindings(snapshot.fnBindings)
                : snapshot.fnBindings
            fnBindings = Self.sanitizedBindings(migratedBindings)
            if snapshot.schemaVersion < ShortcutSettingsSnapshot.currentVersion
                || fnBindings != snapshot.fnBindings {
                save()
            }
            return
        }

        fnBindings = Self.sanitizedBindings(migrateLegacyFnBindings())
        seedMissingAnchorDefaults(in: &fnBindings)
        save()
        defaults.set(true, forKey: Keys.didMigrate)
    }

    private func loadSnapshot() -> ShortcutSettingsSnapshot? {
        guard
            let data = defaults.data(forKey: Keys.snapshot),
            let snapshot = try? JSONDecoder().decode(ShortcutSettingsSnapshot.self, from: data),
            (1...ShortcutSettingsSnapshot.currentVersion).contains(snapshot.schemaVersion)
        else {
            return nil
        }

        let migrated = migrateSnapshotIfNeeded(snapshot)
        if migrated != snapshot {
            saveSnapshot(migrated)
        }
        return migrated
    }

    private func migrateLegacyFnBindings() -> [ShortcutBinding] {
        var result: [ShortcutBinding] = []
        var used = Set<FnChord>()

        for action in ShortcutAction.visibleInShortcutSettings {
            let hasLegacyValue = FnComboSettings.legacyHasStoredCombo(for: action, defaults: defaults)
            let chord = hasLegacyValue
                ? FnComboSettings.legacyStoredCombo(for: action, defaults: defaults)
                : FnComboSettings.legacyDefaultCombo(for: action)

            guard let chord else {
                continue
            }

            guard !used.contains(chord) else {
                logger.warning("Skipped duplicated legacy Fn chord \(chord.id, privacy: .public)")
                continue
            }

            used.insert(chord)
            result.append(.fn(action: action, chord: chord))
        }

        if !result.contains(where: { $0.action == .raw }),
           !used.contains(.fnOnly),
           !FnComboSettings.legacyHasStoredCombo(for: .raw, defaults: defaults) {
            result.append(.fn(action: .raw, chord: .fnOnly))
        }

        return result
    }

    private func migratedSnapshotBindings(_ bindings: [ShortcutBinding]) -> [ShortcutBinding] {
        var result = Self.sanitizedBindings(bindings)
        seedRightOptionDefaultsIfMissing(in: &result)
        return result
    }

    private func seedMissingAnchorDefaults(in bindings: inout [ShortcutBinding]) {
        for anchor in ShortcutAnchor.allCases {
            guard !bindings.contains(where: { $0.fnChord?.anchor == anchor }) else {
                continue
            }
            bindings.append(contentsOf: Self.defaultBindings(for: anchor, defaults: defaults))
        }
    }

    private func seedRightOptionDefaultsIfMissing(in bindings: inout [ShortcutBinding]) {
        guard !bindings.contains(where: { $0.fnChord?.anchor == .rightOption }) else {
            return
        }
        bindings.append(contentsOf: Self.defaultBindings(for: .rightOption, defaults: defaults))
    }

    private func save() {
        let snapshot = ShortcutSettingsSnapshot(
            schemaVersion: ShortcutSettingsSnapshot.currentVersion,
            fnBindings: fnBindings
        )
        saveSnapshot(snapshot)
    }

    private func saveSnapshot(_ snapshot: ShortcutSettingsSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: Keys.snapshot)
        } catch {
            logger.error("Failed to save shortcut settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func migrateSnapshotIfNeeded(_ snapshot: ShortcutSettingsSnapshot) -> ShortcutSettingsSnapshot {
        guard snapshot.schemaVersion < ShortcutSettingsSnapshot.currentVersion else {
            return snapshot
        }

        var bindings = Self.sanitizedBindings(snapshot.fnBindings)
        if snapshot.schemaVersion < 3 {
            Self.migrateOldFnShiftDefaultToDictationTranslate(in: &bindings)
        }
        for defaultBinding in Self.snapshotVersionTwoAdditions {
            guard let chord = defaultBinding.fnChord else { continue }
            let actionAlreadyHasFnBinding = bindings.contains {
                $0.isEnabled && $0.family == .fn && $0.action == defaultBinding.action
            }
            let chordIsOccupied = bindings.contains {
                $0.isEnabled && $0.family == .fn && $0.fnChord == chord
            }
            if !actionAlreadyHasFnBinding && !chordIsOccupied {
                bindings.append(defaultBinding)
            }
        }
        // v4: seed the 划词菜单 default (Fn+V) for users upgrading from an earlier snapshot,
        // unless they already bound 划词菜单 or took Fn+V for something else.
        if !bindings.contains(where: { $0.isEnabled && $0.family == .fn && $0.action == .selectionMenu }),
           !bindings.contains(where: { $0.isEnabled && $0.family == .fn && $0.fnChord == .fnV }) {
            bindings.append(.fn(action: .selectionMenu, chord: .fnV))
        }
        // v5: seed the 地道外文 default (Fn+E) for users upgrading from an earlier snapshot,
        // unless they already bound 地道外文 or took Fn+E for something else. (Fn+E shipped as a
        // fresh-install default in 1.3.3 but existing users had no migration → it showed 未设置.)
        if !bindings.contains(where: { $0.isEnabled && $0.family == .fn && $0.action == .expressInEnglish }),
           !bindings.contains(where: { $0.isEnabled && $0.family == .fn && $0.fnChord == .fnE }) {
            bindings.append(.fn(action: .expressInEnglish, chord: .fnE))
        }
        seedRightOptionDefaultsIfMissing(in: &bindings)

        return ShortcutSettingsSnapshot(
            schemaVersion: ShortcutSettingsSnapshot.currentVersion,
            fnBindings: bindings
        )
    }

}
