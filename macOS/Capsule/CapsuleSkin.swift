import SwiftUI

/// **录音胶囊外观** — the capsule's own appearance axis, deliberately independent of the app-wide
/// `Skin`.
///
/// `Skin` is a *colour world* that tints the whole app; every one of its nine members shares one
/// silhouette and one rhythm. This axis is different in kind: each non-default member is a whole
/// visual identity — its own palette, its own chrome, and its own **phase choreography** (how the
/// pill behaves outside 录音中). That is why it is a separate enum and a separate defaults key
/// rather than three more `Skin` cases.
///
/// Default is `.followSkin`, which reproduces the pre-existing behaviour byte for byte: paper and
/// accent derive from `Skin.current`, so 珞珈青 still shows a green pill. The two 高达 skins opt
/// **out** of the skin system entirely — armour and psychoframe are their own colour worlds and
/// would be incoherent re-tinted nine ways.
///
/// Scope: the floating capsule and the dictation-side pills/cards that share `CapsuleSystemTheme`.
/// The main window, settings and onboarding stay on `Skin`.
enum CapsuleSkin: String, CaseIterable, Identifiable, Sendable {
    /// 跟随皮肤 — the original behaviour: every token derives from `Skin.current`.
    case followSkin
    /// 单眼 · 夏亚红 — MS-06S armour; a mono-eye replaces the waveform.
    case zaku
    /// 光之骨架 — psychoframe; translucent, glowing, and the only skin whose hue tracks the mode.
    case psychoFrame

    var id: String { rawValue }

    /// Persisted choice; first-run default.
    static let `default`: CapsuleSkin = .followSkin
    static let defaultsKey = "appearance.capsuleSkin"

    /// The active capsule skin resolved from the persisted choice. Non-isolated (like
    /// `Skin.current`) so the static colour tokens can read it at render time; `AppearanceStore`
    /// is the reactive holder over the same key.
    static var current: CapsuleSkin {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(CapsuleSkin.init(rawValue:)) ?? .default
    }

    var displayName: String {
        switch self {
        case .followSkin:  "跟随皮肤"
        case .zaku:        "单眼 · 夏亚红"
        case .psychoFrame: "光之骨架"
        }
    }

    var tagline: String {
        switch self {
        case .followSkin:  "纸面 + 当前配色方案"
        case .zaku:        "酒红装甲 + 巡视单眼"
        case .psychoFrame: "半透明晶格 + 外溢辉光"
        }
    }

    /// How the pill behaves in the phases **other than** 录音中 — the axis's second half, settled
    /// in the 第 2 轮 grilling. Colour alone would have left 待机/思考/结果/出错 looking generic.
    var choreography: CapsulePhaseChoreography {
        switch self {
        case .followSkin:  .fillSweep
        case .zaku:        .signature
        case .psychoFrame: .edgeArc
        }
    }

    /// Whether the accent hue tracks 听写 vs 提问. Only psychoframe does (青 / 粉) — for the others
    /// the mode is told apart by the floating label alone, as before.
    var accentTracksMode: Bool { self == .psychoFrame }

    /// How far the resting pill recedes.
    ///
    /// A skin property, not a choreography one: what governs it is whether the surface is dark.
    /// `.followSkin` is a pale paper pill, so fading it to 62% on a bright desktop is paper on
    /// paper and stays readable. The two 高达 skins are dark objects carrying near-white ink —
    /// fading *them* toward a bright desktop composites the surface up into mid-grey and the ink
    /// contrast collapses (caught in the light-appearance snapshots). They dim only slightly and
    /// let their own resting cues (a lens pulled down to 28%, an unlit ring) say "asleep".
    var idleOpacity: Double {
        switch self {
        case .followSkin:          0.62
        case .zaku, .psychoFrame:  0.85
        }
    }

    func tokens(mode: CapsuleMode) -> CapsuleTokens {
        switch self {
        case .followSkin:  CapsuleTokens.followingSkin()
        case .zaku:        CapsuleTokens.zaku
        case .psychoFrame: mode == .ask ? CapsuleTokens.psychoAsk : CapsuleTokens.psychoVoice
        }
    }
}

/// How the capsule expresses the phases outside 录音中.
enum CapsulePhaseChoreography: Sendable {
    /// 现状：思考态左→右 accent 填充；待机压到 62% 透明；结果 ✓ 徽章；出错 ⚠ 徽章。
    case fillSweep
    /// 签名元件贯穿：单眼在**所有**相位都在（思考=呼吸 / 待机=暗 / 结果=眯 / 出错=琥珀急闪），
    /// 顶掉 ✓ 与 ⚠ 徽章，且不用填充条 —— 装甲是实心的，填充没损失，单眼消失才是损失。
    case signature
    /// 边缘能量环：亮弧沿描边跑，结果定格成整圈实线，出错转红双闪。内部完全不遮 ——
    /// 半透明的光之骨架一旦被填充条盖住就毁了通透。
    case edgeArc
}

/// One capsule skin's colour world. Mirrors the token set `CapsuleSystemTheme` used to derive
/// from `SkinPalette`, so the 8 dictation-side consumers keep reading the same names.
struct CapsuleTokens: Sendable {
    /// Sits over an `.ultraThinMaterial`; the alpha is what lets the backdrop through.
    let surface: Color
    let ink: Color
    let ink2: Color
    let line: Color
    let chip: Color

    let accent: Color
    /// Waveform / pulse dot — brighter than `accent` where the skin wants the stroke to sing.
    let accentText: Color
    /// Glyph colour on top of `accent`.
    let accentInk: Color
    let accentSoft: Color
    let glow: Color
    /// Left→right progress fill. Unused by `.signature` / `.edgeArc`, kept so the token set is total.
    let fill: Color

    let err: Color
    let errSoft: Color
    let shadow: Color

    // MARK: - 跟随皮肤

    /// The pre-existing recipe, unchanged: which token carries which alpha, wash-in-light vs
    /// near-solid-in-dark, all sourced from `Skin.current`. 永不纯黑 / 蓝.
    static func followingSkin() -> CapsuleTokens {
        let p = Skin.current.palette
        let hx = Skin.current.capsuleHex
        return CapsuleTokens(
            surface:    p.card.opacity(0.96),
            ink:        p.ink,
            ink2:       p.ink.opacity(0.55),
            line:       p.ink.opacity(0.125),
            chip:       p.ink.opacity(0.085),
            accent:     p.accent,
            accentText: p.accent,
            accentInk:  p.onAccent,
            accentSoft: DynamicColor.make(hx.accentLight, hx.accentDark, lightA: 0.13, darkA: 0.16),
            glow:       DynamicColor.make(hx.accentLight, hx.accentLight, lightA: 0.4, darkA: 0.55),
            fill:       DynamicColor.make(hx.accentLight, hx.accentLight, lightA: 0.2, darkA: 0.85),
            err:        Self.semanticErr,
            errSoft:    Self.semanticErrSoft,
            shadow:     DynamicColor.make(hx.inkLight, 0x000000, lightA: 0.38, darkA: 0.6)
        )
    }

    /// Error red stays semantic across the skin system — it is not a brand colour.
    static let semanticErr = DynamicColor.make(0xB23A2E, 0xE0796B)
    static let semanticErrSoft = DynamicColor.make(0xB23A2E, 0xE0796B, lightA: 0.12, darkA: 0.16)

    // MARK: - 单眼 · 夏亚红 (MS-06S)

    /// Armour reads as armour on **both** desktops, so the surface does not flip light/dark — only
    /// the drop shadow does (a dark pill on a bright desktop needs less shadow to separate).
    ///
    /// One consequence worth naming: the semantic error red is unreadable on this wine armour, so
    /// this skin's `err` is **琥珀** instead. That is a legibility fix, not a brand choice — the
    /// glyph still means "出错".
    static let zaku = CapsuleTokens(
        surface:    DynamicColor.make(0x52222F, 0x52222F, lightA: 0.97, darkA: 0.97),
        ink:        DynamicColor.make(0xF6E6EA, 0xF6E6EA),
        // 0.70, not the paper skins' 0.55: the resting status line sits on wine armour, and 55%
        // of a near-white on that ground failed the light-appearance snapshot.
        ink2:       DynamicColor.make(0xF6E6EA, 0xF6E6EA, lightA: 0.70, darkA: 0.70),
        line:       DynamicColor.make(0xFF96AF, 0xFF96AF, lightA: 0.28, darkA: 0.28),
        chip:       DynamicColor.make(0x0C0609, 0x0C0609, lightA: 0.55, darkA: 0.55),
        accent:     DynamicColor.make(0xFF6B84, 0xFF6B84),
        accentText: DynamicColor.make(0xFF6B84, 0xFF6B84),
        accentInk:  DynamicColor.make(0x2B0B14, 0x2B0B14),
        accentSoft: DynamicColor.make(0xFF6B84, 0xFF6B84, lightA: 0.18, darkA: 0.18),
        glow:       DynamicColor.make(0xFF506E, 0xFF506E, lightA: 0.60, darkA: 0.60),
        fill:       DynamicColor.make(0xFF6B84, 0xFF6B84, lightA: 0.42, darkA: 0.42),
        err:        DynamicColor.make(0xFFB44A, 0xFFB44A),
        errSoft:    DynamicColor.make(0xFFB44A, 0xFFB44A, lightA: 0.18, darkA: 0.18),
        shadow:     DynamicColor.make(0x3A101C, 0x000000, lightA: 0.45, darkA: 0.60)
    )

    // MARK: - 光之骨架 (Psycho-Frame)

    /// Light, not matter: the surface is barely there and the identity is carried by the ring, the
    /// glow and the lattice.
    ///
    /// The core is **much denser in light appearance** (.86 vs .45). A translucent dark core over a
    /// *bright* backdrop composites to mid-grey, which is the worst possible ground for near-white
    /// ink — the light snapshot came back a flat grey lozenge with an unreadable status line. The
    /// skin stays a dark glowing object on a bright desktop, exactly as armour does; translucency
    /// is its texture, not a requirement to be pale. On dark it can stay thin and let the lattice
    /// read through.
    ///
    /// The only skin whose hue tracks the mode: 听写 is 青, 提问 is 粉. `UnifiedCapsule` is the
    /// single view rendered in both modes, so it is the only place that has to resolve this.
    static let psychoVoice = CapsuleTokens(
        surface:    DynamicColor.make(0x061A16, 0x061A16, lightA: 0.86, darkA: 0.45),
        ink:        DynamicColor.make(0xE6FFF7, 0xE6FFF7),
        ink2:       DynamicColor.make(0xE6FFF7, 0xE6FFF7, lightA: 0.72, darkA: 0.72),
        line:       DynamicColor.make(0x4DFBC0, 0x4DFBC0, lightA: 0.55, darkA: 0.55),
        chip:       DynamicColor.make(0x4DFBC0, 0x4DFBC0, lightA: 0.12, darkA: 0.12),
        accent:     DynamicColor.make(0x4DFBC0, 0x4DFBC0),
        accentText: DynamicColor.make(0xB6FFF0, 0xB6FFF0),
        accentInk:  DynamicColor.make(0x012019, 0x012019),
        accentSoft: DynamicColor.make(0x4DFBC0, 0x4DFBC0, lightA: 0.16, darkA: 0.16),
        glow:       DynamicColor.make(0x4DFBC0, 0x4DFBC0, lightA: 0.75, darkA: 0.75),
        fill:       DynamicColor.make(0x4DFBC0, 0x4DFBC0, lightA: 0.28, darkA: 0.28),
        err:        DynamicColor.make(0xFF9D7A, 0xFF9D7A),
        errSoft:    DynamicColor.make(0xFF9D7A, 0xFF9D7A, lightA: 0.16, darkA: 0.16),
        shadow:     DynamicColor.make(0x001E18, 0x000000, lightA: 0.45, darkA: 0.55)
    )

    static let psychoAsk = CapsuleTokens(
        surface:    DynamicColor.make(0x18041A, 0x18041A, lightA: 0.86, darkA: 0.45),
        ink:        DynamicColor.make(0xFFEAF8, 0xFFEAF8),
        ink2:       DynamicColor.make(0xFFEAF8, 0xFFEAF8, lightA: 0.72, darkA: 0.72),
        line:       DynamicColor.make(0xFF7AD0, 0xFF7AD0, lightA: 0.55, darkA: 0.55),
        chip:       DynamicColor.make(0xFF7AD0, 0xFF7AD0, lightA: 0.12, darkA: 0.12),
        accent:     DynamicColor.make(0xFF7AD0, 0xFF7AD0),
        accentText: DynamicColor.make(0xFFD0EE, 0xFFD0EE),
        accentInk:  DynamicColor.make(0x24041A, 0x24041A),
        accentSoft: DynamicColor.make(0xFF7AD0, 0xFF7AD0, lightA: 0.16, darkA: 0.16),
        glow:       DynamicColor.make(0xFF7AD0, 0xFF7AD0, lightA: 0.75, darkA: 0.75),
        fill:       DynamicColor.make(0xFF7AD0, 0xFF7AD0, lightA: 0.28, darkA: 0.28),
        err:        DynamicColor.make(0xFF9D7A, 0xFF9D7A),
        errSoft:    DynamicColor.make(0xFF9D7A, 0xFF9D7A, lightA: 0.16, darkA: 0.16),
        shadow:     DynamicColor.make(0x1E0018, 0x000000, lightA: 0.45, darkA: 0.55)
    )
}
