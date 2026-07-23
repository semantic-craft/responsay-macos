import SwiftUI

struct DemoResultPanel: View {
    @Environment(AppearanceStore.self) private var appearance
    let script: FeatureDemoScript
    let state: DemoFrameState

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: SkinMetrics.sp2) {
            Text(script.resultLabel)
                .font(.system(size: SkinMetrics.fsLabel, weight: .bold)).tracking(1.2)
                .foregroundStyle(p.accent)

            switch script.resultContent {
            case .standard:
                standardContent(p)
            case let .anchors(items):
                anchorsContent(items, p)
            case let .keywords(groups, cnkiQuery):
                keywordsContent(groups, cnkiQuery, p)
            case let .webResults(items):
                webResultsContent(items, p)
            }

            HStack(spacing: SkinMetrics.sp2) {
                Spacer(minLength: 0)
                action(key: "⏎", label: script.primaryAction, primary: true,
                       active: state.panelPrimaryActive, p)
                action(key: "esc", label: "关闭", primary: false, active: false, p)
            }
            .padding(.top, SkinMetrics.sp1)
        }
        .padding(SkinMetrics.sp3)
        .frame(maxWidth: 430, alignment: .leading)
        .background(p.card.opacity(0.96), in: RoundedRectangle(cornerRadius: SkinMetrics.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.hair, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    // MARK: - Standard (existing demos)

    @ViewBuilder private func standardContent(_ p: SkinPalette) -> some View {
        Text(script.target)
            .font(.system(size: SkinMetrics.fsBody, weight: .semibold))
            .foregroundStyle(p.ink)
            .fixedSize(horizontal: false, vertical: true)

        if !script.diffDeleted.isEmpty || !script.diffInserted.isEmpty {
            Text(diffLine(p))
                .font(.system(size: SkinMetrics.fsFoot))
                .fixedSize(horizontal: false, vertical: true)
        }

        if !script.reason.isEmpty {
            reasonBullet(script.reason, p)
        }
    }

    // MARK: - Anchors (来源核验)

    @ViewBuilder private func anchorsContent(_ items: [DemoAnchorItem], _ p: SkinPalette) -> some View {
        if state.verifiedSourceRevealCount > 0 {
            HStack(spacing: SkinMetrics.sp2) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(p.accent)
                Text("已找到可打开来源，并把题名、作者、期刊等核对字段带回。")
                    .font(.system(size: SkinMetrics.fsLabel))
                    .foregroundStyle(p.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let verified = Array(items.prefix(state.verifiedSourceRevealCount))
            ForEach(Array(verified.enumerated()), id: \.offset) { _, item in
                sourceEvidenceCard(item, p)
            }
        } else {
            let visible = Array(items.prefix(state.anchorRevealCount))
            ForEach(Array(visible.enumerated()), id: \.offset) { idx, item in
                HStack(spacing: SkinMetrics.sp2) {
                    Text("[待核]")
                        .font(.system(size: SkinMetrics.fsLabel, weight: .bold))
                        .foregroundStyle(p.onAccent)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(p.accent))
                    Text(item.label)
                        .font(.system(size: SkinMetrics.fsFoot, weight: .semibold))
                        .foregroundStyle(p.ink)
                    Text(item.kind)
                        .font(.system(size: SkinMetrics.fsLabel))
                        .foregroundStyle(p.ink3)
                    Spacer(minLength: 0)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(p.ink3)
                }
                .padding(.vertical, 4)
                .scaleEffect(state.anchorFlashIndex == idx ? 1.03 : 1.0)
                .background(
                    RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall)
                        .fill(state.anchorFlashIndex == idx ? p.accent.opacity(0.1) : .clear)
                )
            }
        }
    }

    private func sourceEvidenceCard(_ item: DemoAnchorItem, _ p: SkinPalette) -> some View {
        VStack(alignment: .leading, spacing: SkinMetrics.sp1) {
            HStack(alignment: .firstTextBaseline, spacing: SkinMetrics.sp1) {
                Text("已命中来源")
                    .font(.system(size: SkinMetrics.fsLabel, weight: .bold))
                    .foregroundStyle(p.onAccent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(p.accent))
                Text(item.sourceTitle)
                    .font(.system(size: SkinMetrics.fsFoot, weight: .semibold))
                    .foregroundStyle(p.ink)
                    .lineLimit(1)
                Text(item.kind)
                    .font(.system(size: SkinMetrics.fsLabel))
                    .foregroundStyle(p.ink3)
                Spacer(minLength: 0)
            }
            Text("\(item.evidence) · \(item.sourceURL)")
                .font(.system(size: SkinMetrics.fsLabel))
                .foregroundStyle(p.ink2)
                .lineLimit(1)
            if !item.matchFields.isEmpty {
                Text(item.matchFields.joined(separator: " · "))
                    .font(.system(size: SkinMetrics.fsLabel))
                    .foregroundStyle(p.ink3)
                    .lineLimit(2)
            }
            Text("仍需打开原文人工确认，不自动判定真伪。")
                .font(.system(size: SkinMetrics.fsCaption))
                .foregroundStyle(p.ink3)
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).fill(p.card2))
        .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).strokeBorder(p.accentLine, lineWidth: 0.75))
    }

    // MARK: - Keywords (检索关键词)

    @ViewBuilder private func keywordsContent(_ groups: [DemoKeywordGroup], _ cnkiQuery: String,
                                              _ p: SkinPalette) -> some View {
        let visible = Array(groups.prefix(state.keywordRevealCount))
        ForEach(Array(visible.enumerated()), id: \.offset) { _, group in
            HStack(alignment: .firstTextBaseline, spacing: SkinMetrics.sp2) {
                Text(group.category)
                    .font(.system(size: SkinMetrics.fsLabel, weight: .bold))
                    .foregroundStyle(p.onAccent)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(p.accent.opacity(0.8)))
                Text(group.terms.joined(separator: "、"))
                    .font(.system(size: SkinMetrics.fsFoot))
                    .foregroundStyle(p.ink2)
                    .lineLimit(1)
            }
        }

        if state.queryOpacity > 0.01 {
            Text(cnkiQuery)
                .font(.system(size: SkinMetrics.fsLabel, design: .monospaced))
                .foregroundStyle(p.ink)
                .padding(SkinMetrics.sp2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall)
                        .fill(p.card2)
                )
                .opacity(state.queryOpacity)
        }
    }

    // MARK: - Web Results (联网检索)

    @ViewBuilder private func webResultsContent(_ items: [DemoWebResultItem], _ p: SkinPalette) -> some View {
        let visible = Array(items.prefix(state.urlRevealCount))
        ForEach(Array(visible.enumerated()), id: \.offset) { _, item in
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: SkinMetrics.fsFoot, weight: .semibold))
                    .foregroundStyle(p.accent)
                    .lineLimit(1)
                Text(item.url)
                    .font(.system(size: SkinMetrics.fsLabel, design: .monospaced))
                    .foregroundStyle(p.ink3)
                    .lineLimit(1)
                Text(item.snippet)
                    .font(.system(size: SkinMetrics.fsLabel))
                    .foregroundStyle(p.ink2)
                    .lineLimit(2)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Shared helpers

    private func reasonBullet(_ text: String, _ p: SkinPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SkinMetrics.sp1) {
            Circle().fill(p.accent.opacity(0.65)).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func diffLine(_ p: SkinPalette) -> AttributedString {
        var del = AttributedString(script.diffDeleted)
        del.foregroundColor = MacPalette.deleted
        del.strikethroughStyle = .single
        var arrow = AttributedString("  →  ")
        arrow.foregroundColor = p.ink3
        var ins = AttributedString(script.diffInserted)
        ins.foregroundColor = MacPalette.inserted
        return del + arrow + ins
    }

    @ViewBuilder
    private func action(key: String, label: String, primary: Bool, active: Bool, _ p: SkinPalette) -> some View {
        HStack(spacing: 6) {
            Text(key).font(.system(size: SkinMetrics.fsLabel, weight: .bold, design: .monospaced))
            Text(label).font(.system(size: SkinMetrics.fsLabel, weight: .semibold))
        }
        .foregroundStyle(primary ? p.onAccent : p.ink2)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Capsule().fill(primary ? (active ? p.accentDeep : p.accent) : p.card2))
        .overlay {
            if !primary { Capsule().strokeBorder(p.hair, lineWidth: 0.5) }
        }
        .scaleEffect(primary && active ? 0.965 : 1)
    }
}
