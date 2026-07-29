import Foundation
import ResponsayCore

struct LegalSkillInventory {
    static let empty = LegalSkillInventory(bundledSkills: [], importedSkills: [])

    let bundledSkills: [LegalSkillCompiled]
    let importedSkills: [LegalSkillCompiled]

    var bundledEverydaySkills: [LegalSkillCompiled] {
        bundledSkills.filter { SkillCategorizer.category(for: $0) == .everydayOffice }
    }

    var bundledLegalSkills: [LegalSkillCompiled] {
        bundledSkills.filter { SkillCategorizer.category(for: $0) == .legal }
    }

    /// Style cards that still belong in 技能平台. Built-in dictation presets are selected beside
    /// 改写力度, so the dictation lane shows imported extensions only; the writing lane keeps its
    /// bundled choices and imported extensions.
    func platformStyleSkills(for lane: SkillLane) -> [LegalSkillCompiled] {
        let bundled = lane == .writing ? bundledEverydaySkills : []
        let imported = importedSkills.filter { SkillCategorizer.category(for: $0) == .everydayOffice }
        return (bundled + imported).filter { $0.metadata.lanes.contains(lane) }
    }

    var verificationSkills: [LegalSkillCompiled] {
        bundledLegalSkills.filter(Self.isVerificationSkill)
    }

    var retrievalSkills: [LegalSkillCompiled] {
        bundledLegalSkills.filter { $0.id.contains("research") }
    }

    /// 技能平台›写作技能›划词生成 — the bundled generation skills that get no dedicated 划词菜单
    /// entry of their own (i.e. everything except 来源核验 / 来源检索).
    var selectionGenerationSkills: [LegalSkillCompiled] {
        bundledLegalSkills.filter(Self.isSelectionGenerationSkill)
    }

    /// The same set as `selectionGenerationSkills` plus imported ones, narrowed to what the user
    /// has 激活 — one flat 划词菜单 row per skill.
    func enabledSelectionGenerationSkills(enabledIDs: Set<String>) -> [LegalSkillCompiled] {
        (bundledSkills + importedSkills)
            .filter { SkillCategorizer.category(for: $0) == .legal }
            .filter(Self.isSelectionGenerationSkill)
            .filter { enabledIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    private static func isVerificationSkill(_ skill: LegalSkillCompiled) -> Bool {
        skill.id.contains("verification")
    }

    /// Defined by exclusion on purpose: 来源核验 (`verification.*`) and 来源检索 (`research.*`) are
    /// the two generation skills with their own named 划词菜单 entries; every other generation skill
    /// — bundled or imported — belongs to 划词生成.
    private static func isSelectionGenerationSkill(_ skill: LegalSkillCompiled) -> Bool {
        !isVerificationSkill(skill) && !skill.id.contains("research")
    }
}

struct LegalSkillLibrary {
    private let importedStore: FileImportedLegalSkillStore
    private let enabledStore: EnabledLegalSkillStore
    private let activeDefaults: UserDefaults
    private let compiler: LegalSkillCompiler
    private let bundledLoader: () throws -> [LegalSkillCompiled]

    init(
        importedStore: FileImportedLegalSkillStore = FileImportedLegalSkillStore(),
        enabledStore: EnabledLegalSkillStore = EnabledLegalSkillStore(),
        activeDefaults: UserDefaults = .standard,
        compiler: LegalSkillCompiler = LegalSkillCompiler(),
        bundledLoader: @escaping () throws -> [LegalSkillCompiled] = {
            try LegalSkillRegistry.loadBundled().skills
        }
    ) {
        self.importedStore = importedStore
        self.enabledStore = enabledStore
        self.activeDefaults = activeDefaults
        self.compiler = compiler
        self.bundledLoader = bundledLoader
    }

    var enabledSkillIDs: Set<String> {
        enabledStore.enabledIDs
    }

    func loadInventory() -> LegalSkillInventory {
        // No visibility filter since 1.5.0: the bundle ships only the curated set, so
        // everything on disk (bundled or imported) is shown.
        let bundled = (try? bundledLoader()) ?? []
        let imported = ((try? importedStore.loadAllRawMarkdown()) ?? [])
            .compactMap { try? compiler.compile($0) }
        return LegalSkillInventory(bundledSkills: bundled, importedSkills: imported)
    }

    func enabledSelectionGenerationSkills() -> [LegalSkillCompiled] {
        loadInventory().enabledSelectionGenerationSkills(enabledIDs: enabledSkillIDs)
    }

    /// The interaction shape declared by the skill with this id (bundled or imported).
    /// Drives 划词菜单 routing: `.conversation` → multi-turn in the Voice Assistant,
    /// `.oneShot` → result card. Unknown id → `.oneShot` (safe default — a missing skill
    /// must never silently open a multi-turn session).
    func interaction(forSkillId id: String) -> SkillInteraction {
        let inventory = loadInventory()
        return (inventory.bundledSkills + inventory.importedSkills)
            .first { $0.id == id }?.metadata.interaction ?? .oneShot
    }

    func setLegalSkillEnabled(_ enabled: Bool, id: String) {
        enabledStore.setEnabled(enabled, id: id)
    }

    /// The active style id for a lane (听写 / 写作), or nil when none is active.
    func activeStyleID(_ lane: StyleLaneSettings.Lane) -> String? {
        StyleLaneSettings.activeID(lane, defaults: activeDefaults)
    }

    /// Clear a lane back to its built-in default (no pack stored). Distinct from `toggleStyleLane`,
    /// which needs an eligible id; the writing lane's「内置默认」card has no selection to store.
    func setStyleLane(_ id: String?, lane: StyleLaneSettings.Lane) {
        StyleLaneSettings.setActive(id, lane: lane, defaults: activeDefaults)
    }

    /// Toggle a style pack on one lane (single-select radio). Activating a new id replaces any
    /// active one; toggling the active id clears it. Generation skills are NOT styles — toggling a
    /// non-eligible id is a no-op so the dictation/writing axis can't be functionally violated.
    @discardableResult
    func toggleStyleLane(_ id: String, lane: StyleLaneSettings.Lane) -> String? {
        // Ineligible id (e.g. a generation skill) → no-op, returning the UNCHANGED active id. The
        // return is always "the active id after this call", so a caller syncing UI state stays
        // truthful; returning nil here would falsely read as "none active" when one still is.
        guard styleEligibleIDs().contains(id) else { return activeStyleID(lane) }
        let nextID = activeStyleID(lane) == id ? nil : id
        StyleLaneSettings.setActive(nextID, lane: lane, defaults: activeDefaults)
        return nextID
    }

    /// Ids selectable as a style on either lane = rewrite-kind packs only (bundled 日常办公 +
    /// imported rewrite packs). Generation / verification / retrieval skills are excluded.
    private func styleEligibleIDs() -> Set<String> {
        let inv = loadInventory()
        let importedRewrite = inv.importedSkills
            .filter { SkillCategorizer.category(for: $0) == .everydayOffice }
        return Set((inv.bundledEverydaySkills + importedRewrite).map(\.id))
    }

}
