import Foundation
import ResponsayCore

/// The default 改写风格 (RewriteTone) applied to 重改写 (改写选中文本). The Layer-2 axis —
/// set in the 改写设置 screen, read here by `CaptureController` and passed to the VM.
/// 如实 / 轻改写 never take a style; only 重改写 does.
enum RewriteStyleSettings {
    /// UserDefaults key shared with the 改写设置 picker (`@AppStorage`).
    static let key = "rewrite.defaultTone"
    static func selectedTone() -> RewriteTone {
        let raw = UserDefaults.standard.string(forKey: key) ?? RewriteTone.natural.rawValue
        return RewriteTone(rawValue: raw) ?? .natural
    }

    /// Resolve the active style for one lane as ONE `ActiveStyleResolver` decision. 听写 reads
    /// `.dictation` (legacy everyday key), 写作 reads `.writing`. Take `.polishHint` for dictation
    /// polish and `.heavyRewriteStyle` for selection rewrite — the two lanes never cross.
    static func activeStyle(
        lane: StyleLaneSettings.Lane,
        availablePacks packs: [StylePack] = availablePacks(),
        defaults: UserDefaults = .standard
    ) -> ActiveStyle {
        ActiveStyleResolver.resolve(
            availablePacks: packs,
            activeID: StyleLaneSettings.activeID(lane, defaults: defaults),
            storedToneRaw: defaults.string(forKey: key))
    }

    /// Built-in (bundled `style.*`) + user-imported rewrite packs offered by the
    /// 重改写风格 picker. Bundled failures degrade to an empty list rather than
    /// blocking the picker (tones still work).
    static func availablePacks() -> [StylePack] {
        let bundled = (try? StylePackRegistry.bundled())?.packs ?? []
        let imported = ((try? FileImportedLegalSkillStore().loadAllRawMarkdown()) ?? [])
            .compactMap { try? LegalSkillCompiler().compile($0) }
            .filter { $0.metadata.kind == .rewrite }
            .map { StylePack.from($0, origin: .localImport) }
        // Imported overrides a bundled pack of the same id (user's own wins).
        var byID = [String: StylePack]()
        for pack in bundled + imported { byID[pack.id] = pack }
        return Array(byID.values).sorted { $0.id < $1.id }
    }
}
