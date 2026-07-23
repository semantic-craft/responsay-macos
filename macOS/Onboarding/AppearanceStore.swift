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

    init() {
        skin = Skin.current
    }

    var palette: SkinPalette { skin.palette }
}
