import SwiftUI
import ResponsayCore

/// Phase 2 (#400) — browse the GitHub legal-skill catalog and install entries through the
/// existing `LegalSkillImporter` (same dedup / consent / [待核] / privacy path). Read-only:
/// no publish, no server. The client is injected so the index/download is testable in Core.
struct LegalSkillCatalogSheet: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    let client: LegalSkillCatalogClient
    /// imported skill id → its version (may be nil) — drives the 已安装/有新版 state.
    let installedVersions: [String: String?]
    let onChanged: () -> Void
    let onClose: () -> Void

    @State private var index: LegalSkillCatalogIndex?
    @State private var loading = true
    @State private var loadError: String?
    @State private var search = ""
    @State private var installing: Set<String> = []
    @State private var rowError: [String: String] = [:]
    @State private var pendingConsent: LegalSkillCatalogEntry?

    private var entries: [LegalSkillCatalogEntry] {
        let all = index?.skills ?? []
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.title.lowercased().contains(q)
                || ($0.description ?? "").lowercased().contains(q)
                || $0.id.lowercased().contains(q)
                || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(appearanceStore.palette.hair).frame(height: 1)
            content
        }
        .frame(width: 700, height: 580)
        .background(appearanceStore.palette.bg)
        .task { await load() }
        .alert("从目录安装第三方技能", isPresented: Binding(
            get: { pendingConsent != nil },
            set: { if !$0 { pendingConsent = nil } })) {
            Button("继续安装") {
                guard let entry = pendingConsent else { return }
                UserDefaults.standard.set(true, forKey: "legal.thirdPartyConsentShown")
                pendingConsent = nil
                perform(entry)
            }
            Button("取消", role: .cancel) { pendingConsent = nil }
        } message: {
            Text("目录里的技能是第三方写的提示词，可能不准确。安装后默认关闭；启用后未核验的法条 / 案号仍标 [待核]，发送范围仍由隐私门把关。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("技能目录")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(appearanceStore.palette.ink)
                Text("从公开目录浏览并安装社区法律技能（只读）。")
                    .font(.system(size: SkinMetrics.fsFoot))
                    .foregroundStyle(appearanceStore.palette.ink3)
            }
            Spacer()
            TextField("搜索", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button("刷新") { Task { await load() } }
            Button("关闭") { onClose() }
        }
        .padding(16)
    }

    @ViewBuilder private var content: some View {
        if loading {
            centered { ProgressView("加载目录…") }
        } else if let loadError {
            centered {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(SettingsTheme.amber)
                    Text(loadError)
                        .font(.system(size: SkinMetrics.fsFoot))
                        .foregroundStyle(appearanceStore.palette.ink2)
                        .multilineTextAlignment(.center)
                    Button("重试") { Task { await load() } }
                }
                .padding(24)
            }
        } else if entries.isEmpty {
            centered {
                Text(search.isEmpty ? "目录暂时为空。" : "没有匹配的技能。")
                    .foregroundStyle(appearanceStore.palette.ink3)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(entries) { row($0) }
                }
                .padding(16)
            }
        }
    }

    private func centered<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        VStack { Spacer(); inner(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ entry: LegalSkillCatalogEntry) -> some View {
        let state = entry.installState(installedVersions: installedVersions)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.system(size: SkinMetrics.fsBody, weight: .semibold))
                        .foregroundStyle(appearanceStore.palette.ink)
                    if let v = entry.version {
                        Text("v\(v)")
                            .font(.system(size: SkinMetrics.fsCaption))
                            .foregroundStyle(appearanceStore.palette.ink3)
                    }
                }
                if let d = entry.description {
                    Text(d)
                        .font(.system(size: SkinMetrics.fsFoot))
                        .foregroundStyle(appearanceStore.palette.ink2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    ForEach(entry.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: SkinMetrics.fsCaption))
                            .foregroundStyle(SettingsTheme.cLegal)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(SettingsTheme.cLegal.opacity(0.1)))
                    }
                    if let author = entry.author {
                        Text("· \(author)")
                            .font(.system(size: SkinMetrics.fsCaption))
                            .foregroundStyle(appearanceStore.palette.ink3)
                    }
                }
                if let err = rowError[entry.id] {
                    Text(err).font(.system(size: SkinMetrics.fsCaption)).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            installControl(entry, state: state)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(appearanceStore.palette.card))
        .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(appearanceStore.palette.hair, lineWidth: 1))
    }

    @ViewBuilder private func installControl(_ entry: LegalSkillCatalogEntry, state: LegalSkillCatalogInstallState) -> some View {
        if installing.contains(entry.id) {
            ProgressView().controlSize(.small).frame(width: 64)
        } else {
            switch state {
            case .installed:
                Text("已安装")
                    .font(.system(size: SkinMetrics.fsLabel))
                    .foregroundStyle(appearanceStore.palette.ink3)
            case .notInstalled:
                Button("安装") { install(entry) }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .tint(appearanceStore.palette.accent)
                    .controlSize(.small)
            case .updateAvailable:
                Button("更新") { install(entry) }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)
            }
        }
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            index = try await client.loadIndex()
        } catch {
            loadError = "无法加载技能目录：\(error.localizedDescription)"
        }
        loading = false
    }

    private func install(_ entry: LegalSkillCatalogEntry) {
        if UserDefaults.standard.bool(forKey: "legal.thirdPartyConsentShown") {
            perform(entry)
        } else {
            pendingConsent = entry
        }
    }

    private func perform(_ entry: LegalSkillCatalogEntry) {
        installing.insert(entry.id)
        rowError[entry.id] = nil
        Task {
            defer { installing.remove(entry.id) }
            do {
                let markdown = try await client.downloadSkillMarkdown(entry)
                switch LegalSkillImporter(store: FileImportedLegalSkillStore()).importSkill(markdown: markdown) {
                case .failed(let error):
                    rowError[entry.id] = LegalSkillImportErrorText.message(for: error)
                case .rewrite, .generation:
                    onChanged()
                }
            } catch {
                rowError[entry.id] = "下载失败：\(error.localizedDescription)"
            }
        }
    }
}
