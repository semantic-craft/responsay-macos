import SwiftUI

/// 来源核验 demo 的「跳转知网」页。做成可辨认的浏览器窗口：地址栏 `kns.cnki.net`、检索框、
/// 命中的那一条**原文**（题名 / 作者 / 期刊·期号·页码 / 摘要）酒红高亮 + 「命中」徽标，
/// 核对字段逐条打勾。它逐个聚焦每条引用（`searchFocusIndex`），不是只闪一下浏览器。
struct DemoSearchPageOverlay: View {
    @Environment(AppearanceStore.self) private var appearance

    let items: [DemoAnchorItem]
    let state: DemoFrameState

    /// CNKI brand blue (not skinned — it's an external-site reference).
    private let cnkiBlue = Color(red: 0.10, green: 0.42, blue: 0.69)

    private var focusIndex: Int {
        guard !items.isEmpty else { return 0 }
        return max(0, min(items.count - 1, state.searchFocusIndex))
    }

    private var item: DemoAnchorItem {
        items.isEmpty ? DemoAnchorItem(label: "", kind: "") : items[focusIndex]
    }

    var body: some View {
        let p = appearance.palette
        VStack(spacing: 0) {
            addressBar(p)
            cnkiBody(p)
        }
        .background(p.field)
        .clipShape(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.hairStrong, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.24), radius: 20, y: 10)
    }

    // MARK: - Browser chrome

    private func addressBar(_ p: SkinPalette) -> some View {
        HStack(spacing: SkinMetrics.sp2) {
            Text("◁  ▷  ↻").font(.system(size: 11)).foregroundStyle(p.ink3)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(MacPalette.inserted)
                Text("kns.cnki.net")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(cnkiBlue)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(p.field, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(p.hair, lineWidth: 0.5))
        }
        .padding(.horizontal, SkinMetrics.sp3)
        .frame(height: 34)
        .background(p.card2)
        .overlay(Rectangle().fill(p.hair).frame(height: 0.5), alignment: .bottom)
    }

    // MARK: - CNKI search result

    private func cnkiBody(_ p: SkinPalette) -> some View {
        VStack(alignment: .leading, spacing: SkinMetrics.sp2) {
            HStack(spacing: SkinMetrics.sp2) {
                Text(item.searchQuery.isEmpty ? item.label : item.searchQuery)
                    .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(p.field, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(cnkiBlue.opacity(0.5), lineWidth: 1.2))
                Text("检索")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .background(cnkiBlue, in: RoundedRectangle(cornerRadius: 7))
            }

            Text("中国知网 · 找到 \(max(items.count, 1)) 条 · 按相关度排序")
                .font(.system(size: SkinMetrics.fsLabel)).foregroundStyle(p.ink3)

            hitCard(p)

            matchFields(p)
            Spacer(minLength: 0)
        }
        .padding(SkinMetrics.sp3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func hitCard(_ p: SkinPalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(item.resultTitle.isEmpty ? item.sourceTitle : item.resultTitle)
                    .font(.system(size: SkinMetrics.fsFoot, weight: .bold))
                    .foregroundStyle(cnkiBlue)
                    .lineLimit(2)
                Spacer(minLength: SkinMetrics.sp2)
                Text("命中")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(p.onAccent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(p.accent))
            }
            Text(item.resultMeta.isEmpty ? item.evidence : item.resultMeta)
                .font(.system(size: SkinMetrics.fsLabel, weight: .semibold)).foregroundStyle(p.ink)
                .lineLimit(2)
            if !item.resultSnippet.isEmpty {
                Text("摘要：" + item.resultSnippet)
                    .font(.system(size: SkinMetrics.fsLabel)).foregroundStyle(p.ink2)
                    .lineLimit(2)
            }
        }
        .padding(SkinMetrics.sp2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall)
            .fill(p.accent.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall)
            .strokeBorder(p.accent, lineWidth: 1))
    }

    private func matchFields(_ p: SkinPalette) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(item.matchFields.prefix(state.matchRevealCount).enumerated()), id: \.offset) { _, field in
                HStack(spacing: SkinMetrics.sp2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(MacPalette.inserted)
                    Text(field)
                        .font(.system(size: SkinMetrics.fsLabel, weight: .semibold)).foregroundStyle(p.ink)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
