import SwiftUI
import AppKit
import ResponsayCore

struct LegalSkillVerificationAnchorsView: View {
    let anchors: [VerificationAnchor]
    let searchPermission: SearchPrivacyGate.SearchPermission
    /// 引注源验: auto-fire 联网核验 on all pending anchors once the card appears (instead of
    /// waiting for a click). Off by default — only the fact-check skill opts in.
    var autoVerify: Bool = false
    @Binding var searchStates: [String: AnchorSearchState]
    @Binding var copiedAnchorId: String?
    var onSearchVerify: (VerificationAnchor) async throws -> VerifiedSource?
    var onConfirmBeforeSearch: ((VerificationAnchor, @escaping () -> Void) -> Void)?
    var onAnchorConfirmed: (VerificationAnchor, VerifiedSource) -> Void

    private let launcher = VerificationSearchLauncher()
    private let router = VerificationQueryRouter()

    /// In-flight verify tasks per anchor, so a long (up to ~90s) call can be
    /// cancelled — by the user, or on panel teardown — instead of leaking and
    /// writing a stale result into a view the user already left.
    @State private var searchTasks: [String: Task<Void, Never>] = [:]
    /// 引注源验 auto-verify fires once (guard against re-entry on re-render).
    @State private var autoVerifyFired = false

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetrics.s) {
            HStack(spacing: MacMetrics.xs) {
                Image(systemName: "checkmark.shield").font(.callout).foregroundStyle(MacPalette.accent)
                Text("待核清单").font(.callout.weight(.semibold)).foregroundStyle(MacPalette.accent)
                Spacer(minLength: 0)
                if searchPermission.isSearchEnabled {
                    Text("联网核验 · 右键更多源").font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text("点击核验 · 右键更多源").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            ForEach(anchors) { anchor in
                anchorRow(anchor)
            }
            if anchors.count > 1 {
                if searchPermission.isSearchEnabled {
                    Button { verifyAllOnline() } label: {
                        Label("一键联网核验全部", systemImage: "globe")
                    }
                    .controlSize(.small).buttonStyle(.bordered).tint(MacPalette.accent)
                    .disabled(isAnyLoading)
                }
                Button { verifyAll() } label: {
                    Label("一键打开核验（百度学术 + 北大法宝）", systemImage: "safari")
                }
                .controlSize(.small).buttonStyle(.bordered).tint(MacPalette.accent)
            }
        }
        .padding(MacMetrics.m).frame(maxWidth: .infinity, alignment: .leading)
        .background(MacPalette.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MacMetrics.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MacMetrics.radiusSmall, style: .continuous)
            .strokeBorder(MacPalette.accent.opacity(0.15), lineWidth: 0.5))
        .onDisappear { cancelAllSearches() }
        .task {
            guard autoVerify, !autoVerifyFired, searchPermission.isSearchEnabled else { return }
            autoVerifyFired = true
            verifyAllOnline()
        }
    }

    private func anchorRow(_ anchor: VerificationAnchor) -> some View {
        let state = displayState(for: anchor)
        return VStack(alignment: .leading, spacing: MacMetrics.xs) {
            HStack(spacing: MacMetrics.xs) {
                statusBadge(state, anchor: anchor)
                Text(anchor.label).font(.callout).foregroundStyle(.primary)
                kindBadge(anchor.kind)
                Spacer(minLength: 0)
                if copiedAnchorId == anchor.id {
                    Text("已复制").font(.caption2).foregroundStyle(MacPalette.accent)
                        .transition(.opacity)
                }
                if searchPermission.isSearchEnabled && state.isPending {
                    Button { startSearch(anchor) } label: {
                        Label(searchPermission.requiresConfirmation ? "联网核验…" : "联网核验",
                              systemImage: "globe")
                    }
                    .controlSize(.mini).buttonStyle(.bordered).tint(MacPalette.accent)
                    .disabled(state == .loading)
                } else if searchPermission == .disabled && state.isPending {
                    Image(systemName: "globe").font(.caption).foregroundStyle(.quaternary)
                        .help("当前隐私路由或模型设置不支持联网核验；可用右键手动查验")
                }
                Button { copyWithFeedback(anchor) } label: {
                    Image(systemName: "doc.on.doc").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
                .help("复制检索词到剪贴板")
            }
            if case .loading = state {
                HStack(spacing: MacMetrics.xs) {
                    ProgressView().controlSize(.small)
                    Text("正在联网核验…").font(.caption).foregroundStyle(.secondary)
                    Button("取消") { cancelSearch(anchor) }
                        .controlSize(.mini).buttonStyle(.bordered)
                }
                .padding(.leading, MacMetrics.m)
            }
            if case .success(let source) = state {
                searchResultCard(source, anchor: anchor)
            }
            if case .notFound = state {
                notFoundCard(anchor)
            }
            if case .error(let msg) = state {
                errorCard(msg, anchor: anchor)
            }
        }
        .padding(.vertical, MacMetrics.hairline)
        .contextMenu {
            if searchPermission.isSearchEnabled {
                Button("联网核验") { startSearch(anchor) }
                Divider()
            }
            Button("打开搜索核验") { openSearch(anchor) }
            Divider()
            // 法规 / 案例（付费/JS 站经必应 site: 落结果页，无需粘贴）
            Button("北大法宝") { openRoute(anchor, .pkulaw) }
            Button("无讼") { openRoute(anchor, .itslaw) }
            Button("裁判文书网") { openRoute(anchor, .wenshu) }
            Button("人民法院案例库") { openRoute(anchor, .rmfyalk) }
            Button("国家法规库") { openRoute(anchor, .govLaw) }
            Divider()
            // 文献
            Button("知网") { openRoute(anchor, .cnki) }
            Button("维普") { openRoute(anchor, .vip) }
            Button("万方") { openRoute(anchor, .wanfang) }
            Button("百度学术") { openRoute(anchor, .baiduScholar) }
            Divider()
            Button("必应") { openRoute(anchor, .bing) }
            Button("复制检索词") { copyWithFeedback(anchor) }
        }
        .help(searchPermission.isSearchEnabled ? "联网核验 · 右键选择单一来源" : "点击打开核验 · 右键选择单一来源")
    }

    private func displayState(for anchor: VerificationAnchor) -> AnchorSearchState {
        if let state = searchStates[anchor.id] { return state }
        if let source = anchor.source { return .success(source) }
        return .idle
    }

    // MARK: - Search state views

    @ViewBuilder
    private func statusBadge(_ state: AnchorSearchState, anchor: VerificationAnchor) -> some View {
        switch state {
        case .success:
            Text("[已核]")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, MacMetrics.xs).padding(.vertical, 1)
                .background(Capsule().fill(.green))
        default:
            Button { onlineVerify(anchor) } label: {
                Text("[待核]")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, MacMetrics.xs).padding(.vertical, 1)
                    .background(Capsule().fill(MacPalette.accent))
            }
            .buttonStyle(.plain)
        }
    }

    private func searchResultCard(_ source: VerifiedSource, anchor: VerificationAnchor) -> some View {
        VStack(alignment: .leading, spacing: MacMetrics.xs) {
            HStack(spacing: MacMetrics.xs) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                Text(source.title).font(.caption.weight(.medium)).lineLimit(2)
            }
            if let snippet = source.snippet, !snippet.isEmpty {
                Text(snippet).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            }
            // 联网核验返回的 URL 来自模型/搜索结果（可被注入内容影响）。只有标准 http(s)
            // 链接才做成可点击；javascript:/file:/自定义 scheme 等一律降级为不可点文字。
            if let url = ExternalLinkPolicy.safeWebURL(source.url) {
                Link(destination: url) {
                    Text(source.url).font(.caption2).foregroundStyle(.blue).lineLimit(1)
                }
            } else if !source.url.isEmpty {
                Text(source.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    .help("该链接不是标准网址，已禁用点击")
            }
            Text("来源：\(source.provider)").font(.caption2).foregroundStyle(.tertiary)
            HStack(spacing: MacMetrics.s) {
                Button("确认[已核]") { confirmAnchor(anchor, source: source) }
                    .controlSize(.mini).buttonStyle(.borderedProminent).tint(.green)
                Button("不对，手动查") { dismissAndFallback(anchor) }
                    .controlSize(.mini).buttonStyle(.bordered)
            }
        }
        .padding(MacMetrics.s)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: MacMetrics.radiusSmall, style: .continuous))
        .padding(.leading, MacMetrics.m)
    }

    private func notFoundCard(_ anchor: VerificationAnchor) -> some View {
        // 法条权威齐全：搜不到该条号高度可疑（常见于 AI 杜撰）→ 红色「疑似杜撰」。
        // 文献/案例搜不到可能只是库未收录 → 橙色中性提示。
        let isLaw = anchor.kind == .law
        return VStack(alignment: .leading, spacing: MacMetrics.xs) {
            HStack(spacing: MacMetrics.xs) {
                Image(systemName: isLaw ? "exclamationmark.triangle.fill" : "questionmark.circle")
                    .foregroundStyle(isLaw ? .red : .orange).font(.caption)
                Text(isLaw ? "疑似杜撰 · 待核" : "未能通过联网核实")
                    .font(.caption.weight(.medium)).foregroundStyle(isLaw ? .red : .secondary)
            }
            Text(isLaw
                 ? "法条权威齐全，联网搜不到该条号——高度可疑（常见于 AI 杜撰）。请右键手动核对国家法规库。"
                 : "搜不到 ≠ 不存在。建议使用右键菜单手动查验来源。")
                .font(.caption2).foregroundStyle(.tertiary)
            Button("手动查验") { dismissAndFallback(anchor) }
                .controlSize(.mini).buttonStyle(.bordered)
        }
        .padding(MacMetrics.s)
        .background((isLaw ? Color.red : Color.orange).opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: MacMetrics.radiusSmall, style: .continuous))
        .padding(.leading, MacMetrics.m)
    }

    private func errorCard(_ message: String, anchor: VerificationAnchor) -> some View {
        VStack(alignment: .leading, spacing: MacMetrics.xs) {
            HStack(spacing: MacMetrics.xs) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.red).font(.caption)
                Text("联网核验暂不可用").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(message).font(.caption2).foregroundStyle(.tertiary)
            Button("打开搜索核验") { openSearch(anchor) }
                .controlSize(.mini).buttonStyle(.bordered)
        }
        .padding(MacMetrics.s)
        .background(Color.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: MacMetrics.radiusSmall, style: .continuous))
        .padding(.leading, MacMetrics.m)
    }

    private func kindBadge(_ kind: VerificationKind) -> some View {
        Text(kindLabel(kind))
            .font(.system(.caption2, design: .default))
            .foregroundStyle(.secondary)
            .padding(.horizontal, MacMetrics.xs).padding(.vertical, 1)
            .background(Capsule().fill(.primary.opacity(0.06)))
    }

    private func kindLabel(_ kind: VerificationKind) -> String {
        switch kind {
        case .law: return "法条"
        case .caseLaw: return "案例"
        case .scholarlyArticle: return "文献"
        case .officialDocument: return "文件"
        case .standard: return "标准"
        case .administrativeRule: return "法规"
        case .date: return "日期"
        case .money: return "金额"
        case .other: return "其他"
        }
    }

    private func openSearch(_ anchor: VerificationAnchor) {
        copyWithFeedback(anchor)
        if let url = launcher.primaryURL(for: anchor) { NSWorkspace.shared.open(url) }
    }

    private func openRoute(_ anchor: VerificationAnchor, _ source: VerificationSourcePreference) {
        if let url = router.route(for: anchor, source: source).url { NSWorkspace.shared.open(url) }
    }

    private func onlineVerify(_ anchor: VerificationAnchor) {
        copyWithFeedback(anchor)
        openRoute(anchor, .baiduScholar)
        openRoute(anchor, .pkulaw)
    }

    private func verifyAll() {
        for anchor in anchors { onlineVerify(anchor) }
    }

    // MARK: - LLM search actions

    private func startSearch(_ anchor: VerificationAnchor) {
        guard searchStates[anchor.id] != .loading else { return }
        if searchPermission.requiresConfirmation, let confirm = onConfirmBeforeSearch {
            confirm(anchor) { executeSearch(anchor) }
        } else {
            executeSearch(anchor)
        }
    }

    private func executeSearch(_ anchor: VerificationAnchor) {
        searchTasks[anchor.id]?.cancel()          // supersede any prior run for this anchor
        searchStates[anchor.id] = .loading
        searchTasks[anchor.id] = Task {
            let result: Result<VerifiedSource?, Error>
            do { result = .success(try await onSearchVerify(anchor)) }
            catch { result = .failure(error) }
            // Discard the result if the run was cancelled / the panel is gone —
            // a stale 90s answer must not overwrite a view the user already left.
            if let next = AnchorVerifyCommit.resolve(cancelled: Task.isCancelled, result: result) {
                searchStates[anchor.id] = next
            }
        }
    }

    private func cancelSearch(_ anchor: VerificationAnchor) {
        searchTasks[anchor.id]?.cancel()
        searchTasks[anchor.id] = nil
        searchStates[anchor.id] = .idle
    }

    private func cancelAllSearches() {
        for task in searchTasks.values { task.cancel() }
        searchTasks = [:]
    }

    private func verifyAllOnline() {
        let pending = anchors.filter { anchor in
            let state = searchStates[anchor.id] ?? .idle
            return state.isPending
        }
        for anchor in pending { startSearch(anchor) }
    }

    private func confirmAnchor(_ anchor: VerificationAnchor, source: VerifiedSource) {
        onAnchorConfirmed(anchor, source)
    }

    private func dismissAndFallback(_ anchor: VerificationAnchor) {
        searchStates[anchor.id] = .idle
        openSearch(anchor)
    }

    private var isAnyLoading: Bool {
        searchStates.values.contains(.loading)
    }

    private func copyWithFeedback(_ anchor: VerificationAnchor) {
        copy(router.query(for: anchor))
        withAnimation(.easeInOut(duration: 0.2)) { copiedAnchorId = anchor.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { if copiedAnchorId == anchor.id { copiedAnchorId = nil } }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
