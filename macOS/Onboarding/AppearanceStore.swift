import SwiftUI
import Observation

/// Runtime-selected active `Skin` for the macOS app, persisted across launches. `@Observable`,
/// so changing the skin live re-tints every view that reads `palette` (the onboarding's step-1
/// "signature moment"). App-wide adoption is the goal — see ADR-0026.
@MainActor
@Observable
final class AppearanceStore {
    static let shared = AppearanceStore()

    var skin: Skin {
        didSet { UserDefaults.standard.set(skin.rawValue, forKey: Skin.defaultsKey) }
    }

    /// 录音胶囊外观 — a separate axis from `skin` (see `CapsuleSkin`). Default `.followSkin`
    /// derives the capsule from `skin`, so this defaults to a no-op.
    var capsuleSkin: CapsuleSkin {
        didSet { UserDefaults.standard.set(capsuleSkin.rawValue, forKey: CapsuleSkin.defaultsKey) }
    }

    init() {
        skin = Skin.current
        capsuleSkin = CapsuleSkin.current
    }

    var palette: SkinPalette { skin.palette }
}
