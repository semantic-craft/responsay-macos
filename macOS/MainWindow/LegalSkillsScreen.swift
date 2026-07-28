import SwiftUI
import ResponsayCore

/// Redesigned Legal Skills Platform UI inspired by Openless Style Packs.
/// Lives in the main window sidebar (.legal).
struct LegalSkillsScreen: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    @State private var inventory: LegalSkillInventory = .empty
    @State private var enabledSkillIDs: Set<String> = LegalSkillLibrary().enabledSkillIDs
    @State private var enabledTools: Set<SelectionTool> = EnabledSelectionToolStore().enabledTools
    private let skillLibrary = LegalSkillLibrary()
    private let toolStore = EnabledSelectionToolStore()

    // Filled by loadSkills() on appear — avoid building throwaway LegalSkillLibrary() instances in
    // the @State defaults (those expressions re-run on every parent render).
    @State private var dictationStyleID: String? = nil
    @State private var writingStyleID: String? = nil

    @State private var skillImportError: String?
    @State private var showImportConsent = false

    /// Raw-markdown editor (Phase 1 authoring) — imported skills only.
    @State private var editingSkill: LegalSkillCompiled?
    @State private var editingText: String = ""
    @State private var editError: String?

    /// Phase 2 — browse / install from the GitHub legal-skill catalog.
    @State private var showCatalog = false
    private var importedVersions: [String: String?] {
        Dictionary(inventory.importedSkills.map { ($0.id, $0.metadata.version) }, uniquingKeysWith: { first, _ in first })
    }

    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 16, alignment: .top)]
    
    // 416 — bundled skills split by the shared categorizer: the 3 rewrite style packs
    // (清晰结构 / 正式表达 / 轻度润色) are 日常办公; the generation skills are 法律技能.
    private var bundledEverydaySkills: [LegalSkillCompiled] {
        inventory.bundledEverydaySkills
    }

    private var verificationSkills: [LegalSkillCompiled] {
        inventory.verificationSkills
    }
    private var retrievalSkills: [LegalSkillCompiled] {
        inventory.retrievalSkills
    }
    /// 划词生成 — 内置生成技能里 来源核验 / 来源检索 之外的那些（脚注排版 / 反方观点 / 目标七问 /
    /// 思路推演 / 提示词优化）。分区旧名「实务辅助」是法律实务时代的遗名，与内容对不上：这 5 个的
    /// `domain` 全是 academicWriting，共性是就着选区产出新内容（`outputCards`），而不是改写选区。
    private var practicalSkills: [LegalSkillCompiled] {
        inventory.practicalSkills
    }

    /// Imported rewrite packs — selectable as a style on either lane (alongside the bundled ones).
    private var importedRewritePacks: [LegalSkillCompiled] {
        inventory.importedSkills.filter { SkillCategorizer.category(for: $0) == .everydayOffice }
    }
    /// Imported generation skills — multi-toggle, live under 写作技能 › 划词技能.
    private var importedGenerationSkills: [LegalSkillCompiled] {
        inventory.importedSkills.filter { SkillCategorizer.category(for: $0) == .legal }
    }
    /// Per-lane candidate pool. The bundled 听写 flavors (清晰结构 / 正式表达) are written for 语音转写
    /// input and 精简压缩 for text already on screen, so each declares its lane and the two pools are
    /// disjoint. Imported packs declare nothing → they show on both lanes, exactly as before.
    private func styleCards(for lane: SkillLane) -> [LegalSkillCompiled] {
        (bundledEverydaySkills + importedRewritePacks).filter { $0.metadata.lanes.contains(lane) }
    }

    /// 表达升级 — the writing lane's built-in default. It backs the 改写 behaviour when no pack is
    /// picked, so the lane shows it as a read-only「内置默认」card rather than a peer choice:
    /// selecting it would be indistinguishable from selecting nothing.
    private var writingDefaultPack: LegalSkillCompiled? {
        inventory.bundledSkills.first { $0.id == SkillCategorizer.expressionUpgradeSkillID }
    }
    /// Imported vs bundled is identity by list membership (LegalSkillCompiled carries no origin flag).
    private func isImported(_ skill: LegalSkillCompiled) -> Bool {
        inventory.importedSkills.contains { $0.id == skill.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(appearanceStore.palette.hair).frame(height: 1)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ===== 听写技能 — drives 意图成稿 only =====
                    categoryHeader("听写技能",
                                   subtitle: "选一个风格包，听写的「意图成稿」就照它整理；没选就用内置默认。")
                    styleGrid(activeID: dictationStyleID, lane: .dictation)

                    // ===== 写作技能 — selection 改写 + 划词生成 =====
                    categoryHeader("写作技能",
                                   subtitle: "选中文字后的改写与生成 · 跟着选区走，不影响听写。")
                    sectionHeader(title: "划词改写 · 与听写各自独立", count: styleCards(for: .writing).count + 1)
                    styleGrid(activeID: writingStyleID, lane: .writing)

                    typographySection
                    skillSection(title: "来源核验", skills: verificationSkills, isBuiltin: true)
                    skillSection(title: "来源检索", skills: retrievalSkills, isBuiltin: true)
                    skillSection(title: "划词生成", skills: practicalSkills, isBuiltin: true)
                    if !importedGenerationSkills.isEmpty {
                        sectionHeader(title: "第三方生成技能", count: importedGenerationSkills.count)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(importedGenerationSkills) { skill in
                                LegalSkillCardView(
                                    skill: skill, isBuiltin: false,
                                    isActive: enabledSkillIDs.contains(skill.id),
                                    onToggle: { toggleSkill(skill.id) },
                                    onExport: { exportSkill(skill) },
                                    onEdit: { beginEdit(skill) })
                            }
                        }
                        .padding(.horizontal, 24).padding(.bottom, 32)
                    }
                }
                .padding(.top, 8)
            }
        }
        .background(appearanceStore.palette.bg)
        .onAppear { loadSkills() }
        .alert("导入失败", isPresented: Binding(
            get: { skillImportError != nil },
            set: { if !$0 { skillImportError = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(skillImportError ?? "") }
        .alert("导入第三方技能", isPresented: $showImportConsent) {
            Button("继续导入") {
                UserDefaults.standard.set(true, forKey: "legal.thirdPartyConsentShown")
                importSkillFromDisk()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("第三方技能是别人写的提示词，可能给出不准确的法律分析。导入后默认关闭；启用后未核验的法条/案号仍会标 [待核]，发送范围仍由隐私门把关。请只导入你信任来源的技能。")
        }
        .sheet(item: $editingSkill) { _ in editorSheet }
        .sheet(isPresented: $showCatalog) {
            LegalSkillCatalogSheet(
                client: .live(),
                installedVersions: importedVersions,
                onChanged: { loadSkills() },
                onClose: { showCatalog = false })
            .environment(appearanceStore)
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("技能平台")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(appearanceStore.palette.ink)
                Text("听写技能与写作技能 · 激活 / 导入 / 导出。")
                    .font(.system(size: SkinMetrics.fsFoot))
                    .foregroundStyle(appearanceStore.palette.ink3)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: loadSkills) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.large)

                Button { showCatalog = true } label: {
                    Label("浏览目录", systemImage: "square.grid.2x2")
                }
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.large)

                Button(action: beginImport) {
                    Label("导入技能", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .tint(appearanceStore.palette.accent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(appearanceStore.palette.bg)
    }
    
    /// 排版整理 — 规范排版 跟着选区走、就地替换，对用户就是写作技能的一种，所以列在「写作技能」下
    /// 与 划词改写 / 来源核验 同级（原先自成一个顶级分区的做法已撤销）。它只是实现上以确定性规则为主、
    /// 没有 `*.LEGAL_SKILL.md` 背书，激活开关另走 `SelectionTool`（见 `SelectionMenuGate`）。
    private var typographySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "排版整理 · 只动格式不改文字", count: SelectionTool.allCases.count)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(SelectionTool.allCases) { tool in
                    SelectionToolCardView(
                        tool: tool,
                        isActive: enabledTools.contains(tool),
                        onToggle: { toggleTool(tool) })
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    /// A titled grid of skill cards, rendered only when the section is non-empty.
    /// The three built-in generation-skill sections share this layout.
    @ViewBuilder
    private func skillSection(title: String, skills: [LegalSkillCompiled], isBuiltin: Bool) -> some View {
        if !skills.isEmpty {
            sectionHeader(title: title, count: skills.count)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(skills) { skill in
                    LegalSkillCardView(
                        skill: skill,
                        isBuiltin: isBuiltin,
                        isActive: enabledSkillIDs.contains(skill.id),
                        onToggle: { toggleSkill(skill.id) },
                        onExport: { exportSkill(skill) },
                        onEdit: nil
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    /// One lane's single-select style grid: that lane's bundled packs + imported rewrite packs.
    /// Tapping a card activates it for `lane` (radio); tapping the active one clears to default.
    ///
    /// The writing lane leads with 表达升级 as a read-only「内置默认」card: it is what 划词改写 runs
    /// when nothing is picked, so it shows as active while `activeID == nil` and tapping it clears
    /// the lane back to that default rather than storing a selection.
    private func styleGrid(activeID storedID: String?, lane: StyleLaneSettings.Lane) -> some View {
        // A stored id that isn't in THIS lane's pool reads as "none" — the writing lane can still
        // hold a dictation pack id copied by the one-time seed, and `ActiveStyleResolver` already
        // falls back to the default when it can't find the id. Mirroring that here keeps the UI
        // honest: otherwise no card looks active while the built-in default is what actually runs.
        let pool = styleCards(for: lane)
        let activeID = pool.contains { $0.id == storedID } ? storedID : nil
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            if lane == .writing, let fallback = writingDefaultPack {
                LegalSkillCardView(
                    skill: fallback,
                    isBuiltin: true,
                    isActive: activeID == nil,
                    isDefaultFallback: true,
                    onToggle: { clearStyle(lane: lane) },
                    onExport: { exportSkill(fallback) },
                    onEdit: nil)
            }
            ForEach(pool) { skill in
                LegalSkillCardView(
                    skill: skill,
                    isBuiltin: !isImported(skill),
                    isActive: activeID == skill.id,
                    onToggle: { toggleStyle(skill.id, lane: lane) },
                    onExport: { exportSkill(skill) },
                    onEdit: isImported(skill) ? { beginEdit(skill) } : nil)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    /// Back to the lane's built-in default (no pack stored).
    private func clearStyle(lane: StyleLaneSettings.Lane) {
        skillLibrary.setStyleLane(nil, lane: lane)
        switch lane {
        case .dictation: dictationStyleID = nil
        case .writing: writingStyleID = nil
        }
    }

    private func toggleStyle(_ id: String, lane: StyleLaneSettings.Lane) {
        let next = skillLibrary.toggleStyleLane(id, lane: lane)
        switch lane {
        case .dictation: dictationStyleID = next
        case .writing: writingStyleID = next
        }
    }

    /// 416 — a top-level category banner (日常办公 / 法律技能), heavier than the
    /// per-section `sectionHeader`. A hairline above sets the two categories apart.
    private func categoryHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(appearanceStore.palette.hair).frame(height: 1)
                .padding(.bottom, 12)
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(appearanceStore.palette.ink)
            Text(subtitle)
                .font(.system(size: SkinMetrics.fsFoot))
                .foregroundStyle(appearanceStore.palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: SkinMetrics.fsBody, weight: .semibold))
                .foregroundStyle(appearanceStore.palette.ink)
            Spacer()
            Text("\(count) 个技能")
                .font(.system(size: SkinMetrics.fsLabel))
                .foregroundStyle(appearanceStore.palette.ink3)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().stroke(appearanceStore.palette.hair, lineWidth: 1))
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    private func toggleSkill(_ id: String) {
        skillLibrary.setLegalSkillEnabled(!enabledSkillIDs.contains(id), id: id)
        enabledSkillIDs = skillLibrary.enabledSkillIDs
    }

    private func toggleTool(_ tool: SelectionTool) {
        toolStore.setEnabled(!enabledTools.contains(tool), tool: tool)
        enabledTools = toolStore.enabledTools
    }

    private func loadSkills() {
        dictationStyleID = skillLibrary.activeStyleID(.dictation)
        writingStyleID = skillLibrary.activeStyleID(.writing)
        enabledSkillIDs = skillLibrary.enabledSkillIDs
        enabledTools = toolStore.enabledTools
        inventory = skillLibrary.loadInventory()
    }
    
    private func beginImport() {
        if UserDefaults.standard.bool(forKey: "legal.thirdPartyConsentShown") {
            importSkillFromDisk()
        } else {
            showImportConsent = true
        }
    }
    
    private func importSkillFromDisk() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "导入"
        panel.message = "选择一个 *.LEGAL_SKILL.md 技能文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            skillImportError = "无法读取所选文件。"; return
        }
        let outcome = LegalSkillImporter(store: FileImportedLegalSkillStore()).importSkill(markdown: markdown)
        switch outcome {
        case .failed(let error):
            skillImportError = importErrorMessage(error)
        case .rewrite, .generation:
            loadSkills()
        }
    }
    
    private func importErrorMessage(_ error: LegalSkillCompileError) -> String {
        LegalSkillImportErrorText.message(for: error)
    }

    // MARK: - Export / Edit (Phase 1 本地创作闭环)

    /// 导出 a skill (built-in or imported) to a user-chosen `*.LEGAL_SKILL.md` — just its raw
    /// source, so it round-trips back through 导入 (fork a built-in, share, or back up).
    private func exportSkill(_ skill: LegalSkillCompiled) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = skill.suggestedFileName
        panel.canCreateDirectories = true
        panel.message = "导出技能为 *.LEGAL_SKILL.md 文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try skill.rawMarkdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            skillImportError = "导出失败：\(error.localizedDescription)"
        }
    }

    private func beginEdit(_ skill: LegalSkillCompiled) {
        editError = nil
        editingText = skill.rawMarkdown
        editingSkill = skill
    }

    /// Save the edited raw markdown back through the importer (compile + validate + persist,
    /// last-wins). On a clean compile we re-derive the id: if it changed, the old file is
    /// removed so the edit doesn't orphan a duplicate.
    private func saveEdit() {
        guard let original = editingSkill else { return }
        let outcome = LegalSkillImporter(store: FileImportedLegalSkillStore()).importSkill(markdown: editingText)
        switch outcome {
        case .failed(let error):
            editError = importErrorMessage(error)
        case .rewrite, .generation:
            let newID = (try? LegalSkillCompiler().compile(editingText))?.id ?? original.id
            if newID != original.id { try? FileImportedLegalSkillStore().delete(id: original.id) }
            editingSkill = nil
            loadSkills()
        }
    }

    private var editorSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑技能")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(appearanceStore.palette.ink)
            Text("直接改原始 *.LEGAL_SKILL.md。保存时会校验元数据与必填项；改 id 会另存为新技能。")
                .font(.system(size: SkinMetrics.fsFoot))
                .foregroundStyle(appearanceStore.palette.ink3)
            TextEditor(text: $editingText)
                .font(.system(size: 12, design: .monospaced))
                .frame(minWidth: 560, minHeight: 360)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(appearanceStore.palette.hair, lineWidth: 1))
            if let editError {
                Text(editError)
                    .font(.system(size: SkinMetrics.fsFoot))
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") { editingSkill = nil }
                    .controlSize(.large)
                Button("保存") { saveEdit() }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .tint(appearanceStore.palette.accent)
                    .controlSize(.large)
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
        .background(appearanceStore.palette.bg)
    }
}
