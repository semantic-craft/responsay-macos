import ResponsayCore
import XCTest
@testable import ResponsayMac

final class LegalSkillLibraryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var directory: URL!
    private let compiler = LegalSkillCompiler()

    override func setUp() {
        super.setUp()
        suiteName = "LegalSkillLibraryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("responsay-legal-library-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        defaults = nil
        suiteName = nil
        directory = nil
        super.tearDown()
    }

    func testInventorySplitsBundledAndImportedSkills() throws {
        let localPractice = try compiler.compile(generationSkill(id: "practice.local.cn"))
        let verification = try compiler.compile(generationSkill(id: "verification.fact_check.cn"))
        let research = try compiler.compile(generationSkill(id: "research.search_strategy.cn"))
        let everyday = try compiler.compile(rewriteSkill(id: "rewrite.office.cn"))
        let importedStore = FileImportedLegalSkillStore(directory: directory)
        try importedStore.save(rawMarkdown: generationSkill(id: "practice.imported.cn"), id: "practice.imported.cn")

        let library = makeLibrary(
            importedStore: importedStore,
            bundled: [localPractice, verification, research, everyday])
        let inventory = library.loadInventory()

        XCTAssertEqual(inventory.bundledEverydaySkills.map(\.id), ["rewrite.office.cn"])
        XCTAssertEqual(inventory.verificationSkills.map(\.id), ["verification.fact_check.cn"])
        XCTAssertEqual(inventory.retrievalSkills.map(\.id), ["research.search_strategy.cn"])
        XCTAssertEqual(inventory.selectionGenerationSkills.map(\.id), ["practice.local.cn"])
        XCTAssertEqual(inventory.importedSkills.map(\.id), ["practice.imported.cn"])
    }

    func testEnabledPracticeSkillsUseInventoryAndEnabledStore() throws {
        defaults.set([], forKey: EnabledLegalSkillStore.defaultsKey)
        let localPractice = try compiler.compile(generationSkill(id: "practice.local.cn"))
        let importedStore = FileImportedLegalSkillStore(directory: directory)
        try importedStore.save(rawMarkdown: generationSkill(id: "practice.imported.cn"), id: "practice.imported.cn")

        let library = makeLibrary(importedStore: importedStore, bundled: [localPractice])
        library.setLegalSkillEnabled(true, id: "practice.imported.cn")

        XCTAssertEqual(library.enabledSelectionGenerationSkills().map(\.id), ["practice.imported.cn"])
    }

    func testInteractionForSkillIdReadsMetadataWithOneShotDefault() throws {
        // 划词技能互动: routing reads each skill's declared interaction. Unknown id → oneShot
        // (safe default: a card path, never an unexpected multi-turn).
        let conversational = try compiler.compile(
            generationSkill(id: "practice.case_strategy.cn", interaction: "conversation"))
        let plain = try compiler.compile(generationSkill(id: "practice.local.cn"))
        let library = makeLibrary(
            importedStore: FileImportedLegalSkillStore(directory: directory),
            bundled: [conversational, plain])

        XCTAssertEqual(library.interaction(forSkillId: "practice.case_strategy.cn"), .conversation)
        XCTAssertEqual(library.interaction(forSkillId: "practice.local.cn"), .oneShot)
        XCTAssertEqual(library.interaction(forSkillId: "nonexistent"), .oneShot)
    }

    func testStyleLaneActivationRoundTripsAndIsLaneScoped() throws {
        let rewrite = try compiler.compile(rewriteSkill(id: "rewrite.office.cn"))
        let library = makeLibrary(
            importedStore: FileImportedLegalSkillStore(directory: directory),
            bundled: [rewrite])

        XCTAssertNil(library.activeStyleID(.writing))
        XCTAssertEqual(library.toggleStyleLane("rewrite.office.cn", lane: .writing), "rewrite.office.cn")
        XCTAssertEqual(library.activeStyleID(.writing), "rewrite.office.cn")
        // Writing activation must NOT leak into the dictation lane.
        XCTAssertNil(library.activeStyleID(.dictation))
        // Toggling the active id off clears it.
        XCTAssertNil(library.toggleStyleLane("rewrite.office.cn", lane: .writing))
        XCTAssertNil(library.activeStyleID(.writing))
    }

    func testGenerationSkillCannotBeActivatedAsStyle() throws {
        let generation = try compiler.compile(generationSkill(id: "verification.fact_check.cn"))
        let rewrite = try compiler.compile(rewriteSkill(id: "rewrite.office.cn"))
        let library = makeLibrary(
            importedStore: FileImportedLegalSkillStore(directory: directory),
            bundled: [generation, rewrite])

        // A generation skill is not a style → toggling it on the dictation lane is a no-op.
        XCTAssertNil(library.toggleStyleLane("verification.fact_check.cn", lane: .dictation))
        XCTAssertNil(library.activeStyleID(.dictation))
        // A rewrite pack on the same lane still works.
        XCTAssertEqual(library.toggleStyleLane("rewrite.office.cn", lane: .dictation), "rewrite.office.cn")

        // Guard with a pre-existing active style: an ineligible toggle leaves it untouched and the
        // no-op return is the still-active id (so a UI syncing on the return value stays correct).
        let stillActive = library.toggleStyleLane("verification.fact_check.cn", lane: .dictation)
        XCTAssertEqual(stillActive, "rewrite.office.cn")
        XCTAssertEqual(library.activeStyleID(.dictation), "rewrite.office.cn")
    }

    private func makeLibrary(
        importedStore: FileImportedLegalSkillStore,
        bundled: [LegalSkillCompiled]
    ) -> LegalSkillLibrary {
        LegalSkillLibrary(
            importedStore: importedStore,
            enabledStore: EnabledLegalSkillStore(defaults: defaults),
            activeDefaults: defaults,
            bundledLoader: { bundled })
    }

    private func generationSkill(id: String, interaction: String? = nil) -> String {
        let interactionLine = interaction.map { #""interaction":"\#($0)","# } ?? ""
        return """
        ```legal-skill
        {
          "schemaVersion":"LEGAL_SKILL/v1","id":"\(id)","title":"生成技能","domain":"litigation","language":"zh",\(interactionLine)
          "triggers":{"keywords":["证据"],"appHints":[],"windowTitleHints":[],"minSelectedTextLength":0},
          "inputs":["selectedText"],
          "sceneLayer":{"scene":"litigation","applicableStages":["briefDrafting"],"preconditions":[],"nextActionCandidates":[]},
          "reasoningKernel":{"mandatoryMapping":["主张→证据"],"forbidden":[]},
          "outputCards":["evidenceArgumentMatrix"],
          "risk":{"level":"high","disclaimer":"辅助分析，需核验。"}
        }
        ```
        ## Skill Instructions
        x
        """
    }

    private func rewriteSkill(id: String) -> String {
        """
        ```legal-skill
        {"schemaVersion":"LEGAL_SKILL/v1","id":"\(id)","title":"改写技能","domain":"litigation","language":"zh","kind":"rewrite","prompt":"改写。","examples":[],"tags":[]}
        ```
        ## Skill Instructions
        """
    }
}
