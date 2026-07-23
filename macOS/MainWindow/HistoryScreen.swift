import SwiftUI
import ResponsayCore
import AppKit

/// 历史 — usage stats + a ruled list of captures, read live from the **same
/// `CaptureStore` the capture flow actually writes to** (review.sqlite). The old
/// `HistoryMediaStore` (history.sqlite) had no live producer — it froze on
/// 2026-06-10 while every real capture went to the review store — so History was
/// stuck weeks behind. Reading the capture store fixes that (one source of truth).
/// Config-free; nothing leaves the machine.
struct HistoryScreen: View {
    @State private var items: [HistoryItem] = []
    @State private var filter = "all"
    @State private var query = ""
    @State private var loaded = false
    @State private var selection: HistoryItem.ID?
    @State private var store: CaptureStore?

    private var filtered: [HistoryItem] {
        var rows = items
        if filter != "all" {
            rows = rows.filter { $0.actionKind.rawValue == filter }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            rows = rows.filter { $0.matchesSearch(q) }
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: 14) {
                statsStrip
                toolbar
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            
            Divider()

            // A plain two-column layout — NOT a nested NavigationSplitView. This view already lives
            // in the main window's split-view detail pane; nesting a second split view rendered as a
            // cramped, mis-aligned floating list (the "sticking out" bug). A fixed-width list + a
            // filling detail column fills the pane cleanly.
            HStack(spacing: 0) {
                listView
                    .frame(width: 340)
                Divider()
                Group {
                    if let selection, let item = items.first(where: { $0.id == selection }) {
                        detailView(item)
                    } else {
                        emptyDetail
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .background(SettingsTheme.bg)
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("历史").font(.system(size: SkinMetrics.fsTitle, weight: .semibold)).foregroundStyle(SettingsTheme.ink)
                Text("本机保存 · 默认 30 天后自动清理")
                    .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(SettingsTheme.ink2)
            }
            Spacer()
            Button { clearAll() } label: { Label("清空", systemImage: "trash") }
                .controlSize(.small)
            Button { exportHistory() } label: { Label("导出", systemImage: "square.and.arrow.up") }
                .controlSize(.small)
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(SettingsTheme.hair).frame(height: 1) }
    }

    // MARK: Stats

    private var statsStrip: some View {
        let chars = items.reduce(0) { $0 + ($1.resultText ?? $1.transcript ?? "").count }
        let hours = Double(chars) / (40.0 * 60.0)
        let today = items.filter { Calendar.current.isDateInToday($0.createdAt) }.count
        return HStack(spacing: 10) {
            statCard("\(chars)", "字", "累计听写")
            statCard("\(items.count)", "段", "累计转写")
            statCard(String(format: "%.1f", hours), "小时", "省下打字")
            statCard("\(today)", "条", "今天")
        }
    }

    private func statCard(_ value: String, _ unit: LocalizedStringKey, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: SkinMetrics.fsTitle, weight: .semibold)).foregroundStyle(SettingsTheme.ink)
                Text(unit).font(.system(size: SkinMetrics.fsLabel)).foregroundStyle(SettingsTheme.ink3)
            }
            Text(label).font(.system(size: SkinMetrics.fsLabel)).foregroundStyle(SettingsTheme.ink2)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCardSurface()
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // 381 — the capture store now records the exact transform per row, so the
            // filter is precise again (see `historyItem(from:)` reading `c.actionKind`).
            Picker("", selection: $filter) {
                Text("全部").tag("all")
                Text("听写").tag(TextActionKind.dictation.rawValue)
                Text("润色").tag(TextActionKind.polish.rawValue)
                Text("重写").tag(TextActionKind.rewrite.rawValue)
                Text("翻译").tag(TextActionKind.translate.rawValue)
                Text("地道表达").tag(TextActionKind.coach.rawValue)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 460)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(SettingsTheme.ink3).font(.system(size: 12))
                TextField("搜索转写历史", text: $query).textFieldStyle(.plain).font(.system(size: SkinMetrics.fsFoot))
            }
            .padding(.horizontal, 10).frame(height: 30).frame(maxWidth: 280)
            .background(RoundedRectangle(cornerRadius: 8).fill(SettingsTheme.field))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SettingsTheme.fieldBorder, lineWidth: 1))
            Spacer()
        }
    }

    // MARK: List

    private var listView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if filtered.isEmpty {
                    emptyState
                } else {
                    ForEach(grouped(filtered), id: \.0) { day, rows in
                        Text(day)
                            .font(.system(size: SkinMetrics.fsCaption, weight: .bold)).foregroundStyle(SettingsTheme.ink3)
                            .textCase(.uppercase).kerning(0.6).padding(.leading, 2)
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, item in
                                if idx > 0 { Rectangle().fill(SettingsTheme.hair2).frame(height: 1) }
                                Button { selection = item.id } label: {
                                    entryRow(item, isSelected: selection == item.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .warmCardSurface()
                    }
                }
            }
            .padding(14)
        }
    }

    private func entryRow(_ item: HistoryItem, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(SettingsTheme.card2)
                Text(actionBadge(item.actionKind)).font(.system(size: SkinMetrics.fsCaption, weight: .semibold)).foregroundStyle(SettingsTheme.ink2)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(actionLabel(item.actionKind)).font(.system(size: SkinMetrics.fsLabel, weight: .semibold)).foregroundStyle(SettingsTheme.ink2)
                    Circle().fill(SettingsTheme.ink3).frame(width: 3, height: 3)
                    Text(relative(item.createdAt)).font(.system(size: SkinMetrics.fsLabel)).foregroundStyle(SettingsTheme.ink3)
                }
                Text(item.displayText)
                    .font(.system(size: 14, weight: .regular)).foregroundStyle(SettingsTheme.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(time(item.createdAt)).font(SettingsTheme.mono).foregroundStyle(SettingsTheme.ink3)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 28)).foregroundStyle(SettingsTheme.ink3)
            Text(query.isEmpty ? "还没有历史。按热键说一句试试。" : "没有匹配的记录。")
                .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(SettingsTheme.ink2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    // MARK: Detail View
    
    private func detailView(_ item: HistoryItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(actionLabel(item.actionKind))
                        .font(.system(size: SkinMetrics.fsBody, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(SettingsTheme.card2)
                        .cornerRadius(6)

                    // 565: 校验成稿记录标注可见 route + 粗粒度 outcome（原口述未保存已在下方明示）。
                    if let badge = item.intentBadge {
                        Text(badge)
                            .font(.system(size: SkinMetrics.fsLabel, weight: .medium))
                            .foregroundStyle(SettingsTheme.ink2)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(SettingsTheme.card2)
                            .cornerRadius(6)
                    }

                    if let d = item.duration {
                        Text(String(format: "%.1f 秒", d))
                            .font(.system(size: SkinMetrics.fsLabel))
                            .foregroundStyle(SettingsTheme.ink3)
                    }
                    Spacer()
                    Button { copy(item.displayText) } label: { Label("复制", systemImage: "doc.on.clipboard") }
                    Button { delete(item.id) } label: { Label("删除", systemImage: "trash") }
                        .foregroundStyle(.red)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("原口述").font(.system(size: SkinMetrics.fsLabel, weight: .bold)).foregroundStyle(SettingsTheme.ink3)
                    Text(item.sourceDisplayText).font(.system(size: 15, weight: .regular))
                        .foregroundStyle(item.transcript == nil ? SettingsTheme.ink3 : SettingsTheme.ink)
                        .textSelection(.enabled)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .warmCardSurface()

                if let res = item.resultText, !res.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(actionLabel(item.actionKind)).font(.system(size: SkinMetrics.fsLabel, weight: .bold)).foregroundStyle(SettingsTheme.ink3)
                        Text(res).font(.system(size: 15, weight: .regular))
                            .foregroundStyle(SettingsTheme.ink)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .warmCardSurface()
                }
                
                Spacer(minLength: 40)
            }
            .padding(22)
        }
    }
    
    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "sidebar.right").font(.system(size: 28)).foregroundStyle(SettingsTheme.ink3)
            Text("选择一条记录查看对比")
                .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(SettingsTheme.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsTheme.bg)
    }


    // MARK: Data + helpers

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        store = Self.makeStore()
        items = ((try? store?.recent(500)) ?? []).map(Self.historyItem(from:))
    }

    private static func makeStore() -> CaptureStore {
        if let sqlite = try? SQLiteReviewStore.defaultStore() {
            return ReviewCaptureStore(reviewStore: sqlite)
        }
        return FileCaptureStore.defaultStore()
    }

    /// Adapt a `CaptureItem` (source + idiomatic + reasons) to the History row model.
    /// `actionKind` is read straight off the capture (381) — the exact transform is now
    /// persisted per row, so no more guessing from the `language` tag.
    private static func historyItem(from c: CaptureItem) -> HistoryItem {
        HistoryItem(
            id: c.id,
            createdAt: c.createdAt,
            actionKind: c.actionKind,
            transcript: c.sourceText,
            resultText: c.idiomatic,
            privacyMode: .unknown,
            intentRoute: c.intentRoute,
            intentOutcome: c.intentOutcome)
    }

    private func delete(_ id: UUID) {
        try? store?.delete(id: id)
        items.removeAll(where: { $0.id == id })
        if selection == id { selection = nil }
    }

    private func clearAll() {
        try? store?.deleteAll()
        items.removeAll()
        selection = nil
    }

    private func grouped(_ rows: [HistoryItem]) -> [(String, [HistoryItem])] {
        let today = rows.filter { Calendar.current.isDateInToday($0.createdAt) }
        let earlier = rows.filter { !Calendar.current.isDateInToday($0.createdAt) }
        var out: [(String, [HistoryItem])] = []
        if !today.isEmpty { out.append((String(localized: "今天"), today)) }
        if !earlier.isEmpty { out.append((String(localized: "更早"), earlier)) }
        return out
    }

    private func actionBadge(_ kind: TextActionKind) -> String {
        switch kind {
        case .dictation: return String(localized: "原")
        case .polish: return String(localized: "润")
        case .rewrite: return String(localized: "写")
        case .translate: return String(localized: "译")
        case .coach: return String(localized: "教")
        case .feedback: return String(localized: "评")
        case .other: return String(localized: "其")
        }
    }

    private func actionLabel(_ kind: TextActionKind) -> String {
        switch kind {
        case .dictation: return String(localized: "原文")
        case .polish: return String(localized: "意图成稿")
        case .rewrite: return String(localized: "重写")
        case .translate: return String(localized: "翻译")
        case .coach: return String(localized: "地道表达")
        case .feedback: return String(localized: "发音反馈")
        case .other: return String(localized: "其他")
        }
    }

    private func relative(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 60 { return String(localized: "刚刚") }
        if s < 3600 { return String(localized: "\(Int(s / 60)) 分钟前") }
        if Calendar.current.isDateInToday(d) { return String(localized: "\(Int(s / 3600)) 小时前") }
        let f = DateFormatter(); f.dateFormat = "M月d日"
        return f.string(from: d)
    }
    private func time(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
    private func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "responsay-history.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = items.map {
            "- **\(actionLabel($0.actionKind))** · \(time($0.createdAt))\n  \($0.exportText)"
        }.joined(separator: "\n\n")
        try? ("# Responsay 历史\n\n" + md).write(to: url, atomically: true, encoding: .utf8)
    }
}
