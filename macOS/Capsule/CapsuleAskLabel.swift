import SwiftUI
import ResponsayCore

// MARK: - Floating ask-identity label (pulse dot + soft accent halo)

struct CapsuleAskLabel: View {
    let text: String
    var source: CapsuleSearchSource? = nil
    let tokens: CapsuleTokens
    let skin: CapsuleSkin
    let reduceMotion: Bool
    @State private var glow = false

    var body: some View {
        HStack(spacing: 6) {
            CapsulePulseDot(tint: tokens.accentText, reduceMotion: reduceMotion)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tokens.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 220, alignment: .leading)
            if let source { CapsuleSourceChip(source: source, tokens: tokens) }
        }
        .padding(.horizontal, 13)
        .frame(height: 26)
        .background(Capsule(style: .continuous).fill(tokens.surface))
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .clipShape(Capsule(style: .continuous))   // clip frost to the pill — no rectangular frame
        .background(CapsuleSkinChrome(skin: skin).clipShape(Capsule(style: .continuous)))
        .overlay(Capsule(style: .continuous).strokeBorder(tokens.line, lineWidth: 1.5))
        .shadow(color: tokens.shadow, radius: CapsuleSystemTheme.shadowRadius, y: CapsuleSystemTheme.shadowY)
        .shadow(color: tokens.glow.opacity(glow ? 0.7 : 0.4), radius: glow ? 16 : 11)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: glow)
        .onAppear { if !reduceMotion { glow = true } }
        .fixedSize()
    }
}

/// 联网搜索模型署名 chip(设计稿 ask-anything-capsule · Variant B):9pt 单字纹章 + 模型名,
/// 嵌在浮标签里,让用户一眼看出是哪个 AI 在联网搜索。取色随当前胶囊外观。
struct CapsuleSourceChip: View {
    let source: CapsuleSearchSource
    let tokens: CapsuleTokens

    var body: some View {
        HStack(spacing: 4) {
            Text(source.monogram)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(tokens.accentInk)
                .frame(width: 9, height: 9)
                .background(RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(tokens.accentText))
            Text(source.name)
                .font(.system(size: 10))
                .foregroundStyle(tokens.ink)
                .lineLimit(1)
        }
        .padding(.leading, 5).padding(.trailing, 6).padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tokens.accentSoft))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("联网模型 \(source.name)")
    }
}

// MARK: - Accent pulse dot (ask label)

struct CapsulePulseDot: View {
    let tint: Color
    let reduceMotion: Bool
    @State private var big = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 6, height: 6)
            .shadow(color: tint.opacity(0.6), radius: 4)
            .scaleEffect(big ? 1.12 : 0.8)
            .opacity(big ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: big)
            .onAppear { if !reduceMotion { big = true } }
            .accessibilityHidden(true)
    }
}
