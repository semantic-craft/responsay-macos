import Foundation

/// The single decision behind the 日常办公 style seam: given the available packs and what the user
/// has stored, resolve the active pack ONCE and derive both outputs from it — the heavy-rewrite
/// style (重改写) and the 轻度润色 hint — with their distinct fallback rules side by side.
public struct ActiveStyle: Sendable, Equatable {
    /// The 改写风格 the heavy 重改写 path uses.
    public let heavyRewriteStyle: RewriteStyle
    /// The 轻度润色 nudge — the active pack's system prompt, or `nil` for plain polish.
    /// Deliberately carries NO fallback (see `ActiveStyleResolver`).
    public let polishHint: String?

    public init(heavyRewriteStyle: RewriteStyle, polishHint: String?) {
        self.heavyRewriteStyle = heavyRewriteStyle
        self.polishHint = polishHint
    }
}

public enum ActiveStyleResolver {
    /// Prefix marking a stored value as a `StylePack` id rather than a `RewriteTone` rawValue.
    public static let packPrefix = "pack:"

    /// Pure resolution. `activeID` = the explicitly-activated 日常办公 pack id (or nil); `storedToneRaw`
    /// = the legacy 重改写风格 picker value (a `RewriteTone` rawValue or a `pack:`-prefixed id).
    public static func resolve(
        availablePacks: [StylePack],
        activeID: String?,
        storedToneRaw: String?
    ) -> ActiveStyle {
        let activePack = activeID.flatMap { id in availablePacks.first { $0.id == id } }
        // The active pack is the ONLY source of the 轻度润色 hint — no fallback (else the heavy
        // 表达升级 default would flavour light polish). The heavy path keeps its own fallbacks.
        let polishHint = activePack?.systemPrompt
        return ActiveStyle(
            heavyRewriteStyle: heavyStyle(activePack: activePack, availablePacks: availablePacks, storedToneRaw: storedToneRaw),
            polishHint: polishHint)
    }

    private static func heavyStyle(
        activePack: StylePack?,
        availablePacks: [StylePack],
        storedToneRaw: String?
    ) -> RewriteStyle {
        if let activePack { return .pack(activePack) }
        // An explicit stored value (legacy 重改写风格 picker) wins next.
        if let raw = storedToneRaw, !raw.isEmpty {
            if raw.hasPrefix(packPrefix) {
                let id = String(raw.dropFirst(packPrefix.count))
                if let pack = availablePacks.first(where: { $0.id == id }) { return .pack(pack) }
                // stored pack uninstalled → fall through to the tier default
            } else if let tone = RewriteTone(rawValue: raw) {
                return .tone(tone)
            }
        }
        // No explicit pack → the 表达升级 tier default, so heavy reads as clearly heavy.
        if let upgrade = availablePacks.first(where: { $0.id == SkillCategorizer.expressionUpgradeSkillID }) {
            return .pack(upgrade)
        }
        return .default
    }
}
