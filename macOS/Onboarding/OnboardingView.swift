import SwiftUI

/// First-run onboarding wizard content: left step rail + scrolling stage + footer. Hosted by an
/// AppKit window (`OnboardingWindowController`, to come) like `MacSettingsWindowController`.
/// Reads the active `Skin` from `AppearanceStore` in the environment.
struct OnboardingView: View {
    @Environment(AppearanceStore.self) private var appearance
    @State private var model = OnboardingModel()
    var onFinish: () -> Void = {}

    var body: some View {
        let p = appearance.palette
        HStack(spacing: 0) {
            OBStepRail(model: model)
            VStack(spacing: 0) {
                ScrollView {
                    stage
                        .id(model.step)
                        .padding(EdgeInsets(top: 34, leading: 40, bottom: 28, trailing: 40))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                OBFooter(model: model, onFinish: onFinish)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(p.card)
        }
        .frame(width: 860, height: 620)
        .background(p.bg)
        .animation(.easeInOut(duration: 0.4), value: appearance.skin)
        .onAppear {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["RESPONSAY_OB_STEP"],
               let n = Int(raw), let s = OnboardingStep(rawValue: n) {
                model.go(to: s)
            }
            #endif
        }
    }

    @ViewBuilder private var stage: some View {
        switch model.step {
        case .skin:        SkinStepView(model: model)
        case .engine:      EngineStepView(model: model)
        case .snapOCR:     SnapOCRStepView(model: model)
        case .permissions: PermissionsStepView(model: model)
        case .hotkey:      HotkeyStepView(model: model)
        case .autoLearn:   AutoLearnStepView(model: model)
        case .demo:        FeatureDemoStepView(model: model)
        case .sandbox:     SandboxStepView(model: model)
        case .basicsLayer: BasicsLayerStepView(model: model)
        case .done:        DoneStepView(model: model)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppearanceStore())
}
