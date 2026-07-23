import SwiftUI

// Shared, skin-driven building blocks for the onboarding wizard. Every view reads the active
// `SkinPalette` from `AppearanceStore` in the environment, so a skin change re-tints all of them.

// MARK: - Step header (kicker · serif title · lede)

struct OBStepHeader: View {
    @Environment(AppearanceStore.self) private var appearance
    let kicker: String
    let title: Text
    var lede: String = ""

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Text(kicker)
                    .font(.system(size: SkinMetrics.fsLabel, weight: .bold))
                    .tracking(2.1)
                    .foregroundStyle(p.accent)
                Rectangle().fill(p.hair).frame(maxWidth: 200, maxHeight: 1)
            }
            title
                // sans (PingFang/SF) — the Charter serif has no CJK glyphs, so a
                // Chinese title fell back to a heavy Songti that read "off" as UI chrome.
                .font(.system(size: SkinMetrics.fsTitle, weight: .semibold))
                .foregroundStyle(p.ink)
                .padding(.top, 6)
            if !lede.isEmpty {
                Text(lede)
                    .font(.system(size: SkinMetrics.fsBody))
                    .foregroundStyle(p.ink2)
                    .lineSpacing(3)
                    .frame(maxWidth: 460, alignment: .leading)
            }
        }
    }
}

// MARK: - Skin swatch card (step 1 signature)

struct OBSkinCard: View {
    @Environment(AppearanceStore.self) private var appearance
    let skin: Skin
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let active = appearance.palette
        let sp = skin.palette               // preview uses the *card's own* world
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    sp.bg
                    RoundedRectangle(cornerRadius: 8).fill(sp.card)
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                        .padding(14)
                    RoundedRectangle(cornerRadius: 4).fill(sp.accent)
                        .frame(width: 64, height: 7)
                        .padding(.leading, 26).padding(.top, 28)
                    Text("Aa").font(SkinMetrics.serif(46, weight: .light)).foregroundStyle(sp.ink)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 24).padding(.top, 14)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5).fill(sp.accent)
                        RoundedRectangle(cornerRadius: 5).fill(sp.accentDeep)
                        RoundedRectangle(cornerRadius: 5).fill(sp.card)
                    }
                    .frame(width: 56, height: 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 22).padding(.bottom, 18)
                }
                .frame(height: 128)
                .overlay(Rectangle().fill(active.hair).frame(height: 1), alignment: .bottom)

                HStack(spacing: 11) {
                    ZStack {
                        Circle().strokeBorder(isSelected ? active.accent : active.hairStrong, lineWidth: 1.5)
                        if isSelected {
                            Circle().fill(active.accent)
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(active.onAccent)
                        }
                    }
                    .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(skin.displayName).font(.system(size: SkinMetrics.fsCard, weight: .semibold)).foregroundStyle(active.ink)
                        Text(skin.tagline).font(.system(size: 11.5)).foregroundStyle(active.ink2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .background(active.card2)
            .clipShape(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: SkinMetrics.radiusCard)
                    .strokeBorder(isSelected ? active.accent : active.hair, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Single-select option card (route / engine)

struct OBOptionCard: View {
    @Environment(AppearanceStore.self) private var appearance
    let title: String
    let detail: String
    var meta: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let p = appearance.palette
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().strokeBorder(isSelected ? p.accent : p.hairStrong, lineWidth: 1.5)
                    if isSelected { Circle().fill(p.accent).frame(width: 8, height: 8) }
                }
                .frame(width: 20, height: 20)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: SkinMetrics.fsCard, weight: .semibold)).foregroundStyle(p.ink)
                    Text(detail).font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    if let meta {
                        Text(meta).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.ink3).padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? p.accentWash : p.card2)
            .clipShape(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(isSelected ? p.accent : p.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Left step rail

struct OBStepRail: View {
    @Environment(AppearanceStore.self) private var appearance
    let model: OnboardingModel

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [p.accent, p.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Responsay").font(SkinMetrics.serif(16, weight: .semibold)).foregroundStyle(p.ink)
                    Text("法言输入法").font(.system(size: 10.5, weight: .semibold)).tracking(1.6).foregroundStyle(p.ink3)
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 22)

            VStack(spacing: 1) {
                ForEach(Array(model.steps.enumerated()), id: \.element) { idx, s in stepRow(s, idx + 1, p) }
            }
            Spacer()
            Text("这些设置随时可在\n偏好设置里修改。")
                .font(.system(size: 11)).foregroundStyle(p.ink3).lineSpacing(2).padding(.horizontal, 8)
        }
        .padding(EdgeInsets(top: 26, leading: 18, bottom: 18, trailing: 18))
        .frame(width: 236, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(p.sidebar)
    }

    @ViewBuilder private func stepRow(_ s: OnboardingStep, _ number: Int, _ p: SkinPalette) -> some View {
        let isCurrent = model.step == s
        let isDone = model.isDone(s)
        Button { model.go(to: s) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(isCurrent ? p.accent : p.card)
                        .overlay(Circle().strokeBorder(isDone ? p.accent : p.hairStrong, lineWidth: 1.5))
                    if isDone {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(p.accent)
                    } else {
                        Text("\(number)").font(.system(size: 11, weight: .bold)).foregroundStyle(isCurrent ? p.onAccent : p.ink3)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.label).font(.system(size: 13.5, weight: isCurrent ? .semibold : .medium)).foregroundStyle(isCurrent ? p.ink : p.ink2)
                    Text(s.sub).font(.system(size: 11)).foregroundStyle(p.ink3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Footer (progress · 返回 / 继续)

struct OBFooter: View {
    @Environment(AppearanceStore.self) private var appearance
    let model: OnboardingModel
    let onFinish: () -> Void

    var body: some View {
        let p = appearance.palette
        HStack(spacing: 16) {
            HStack(spacing: 13) {
                Text("第 \(model.currentIndex + 1) / \(model.steps.count) 步")
                    .font(.system(size: SkinMetrics.fsFoot)).monospacedDigit().foregroundStyle(p.ink3)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(p.hairStrong)
                        Capsule().fill(p.accent).frame(width: geo.size.width * model.progress)
                    }
                }
                .frame(width: 170, height: 3)
            }
            Spacer()
            Button {
                // On 实操体验 / 看演示, 返回 steps back *within* the sub-sequence first.
                if model.step == .sandbox && model.sandboxSequence.index > 0 {
                    model.sandboxSequence.back()
                } else if model.step == .demo && model.demoIndex > 0 {
                    model.demoIndex -= 1
                } else {
                    model.back()
                }
            } label: {
                Text("返回").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.ink2)
                    .padding(.horizontal, 20).padding(.vertical, 9)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(p.hairStrong, lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(model.isFirst).opacity(model.isFirst ? 0.4 : 1)
            Button {
                // On 实操体验, 继续 advances the next sandbox flow until all are done — only
                // then does it leave the step (fixes the 继续→skip-sandbox走查 bug).
                if model.sandboxInProgress { model.sandboxSequence.advance() }
                else if model.demoInProgress { model.demoIndex += 1 }
                else if model.isLast { model.commit(); onFinish() }
                else { model.next() }
            } label: {
                Text(model.isLast ? "开始使用" : "继续").font(.system(size: 14, weight: .semibold)).foregroundStyle(p.onAccent)
                    .padding(.horizontal, 20).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(p.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 26)
        .frame(height: 66)
        .overlay(Rectangle().fill(p.hair).frame(height: 0.5), alignment: .top)
    }
}
