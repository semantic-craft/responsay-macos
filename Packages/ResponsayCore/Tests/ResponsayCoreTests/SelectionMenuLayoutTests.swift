import XCTest
@testable import ResponsayCore

final class SelectionMenuLayoutTests: XCTestCase {
    private let allActions: [SelectionAction] = [.verify, .assistedSearch, .translate, .readAloud, .ask, .addToDictionary]

    func testDefaultIncludesTranslateReadAloudFirstThenLegal() {
        // 翻译/朗读 are now configurable (the icon row is dynamic) → first, then legal/research.
        XCTAssertEqual(SelectionMenuLayout.default.entries.map(\.id), [
            "translate", "readAloud", "verify", "assistedSearch", "normalizeTypography", "ask", "addToDictionary",
        ])
        XCTAssertTrue(SelectionMenuLayout.default.entries.allSatisfy(\.visible))
    }

    func testResolveKeepsVisibleEntriesInLayoutOrder() {
        let layout = SelectionMenuLayout(entries: [
            .init(id: "translate"), .init(id: "verify"), .init(id: "readAloud"),
        ])
        let items = layout.resolve(availableActions: [.verify, .translate, .readAloud], availableSkills: [])
        XCTAssertEqual(items.map(\.id), ["translate", "verify", "readAloud"])
    }

    func testHiddenEntryIsDropped() {
        // Complete layout (all actions present), readAloud hidden → dropped, nothing appended.
        let layout = SelectionMenuLayout(entries: [
            .init(id: "verify"), .init(id: "assistedSearch"), .init(id: "translate"),
            .init(id: "readAloud", visible: false), .init(id: "ask"), .init(id: "addToDictionary"),
        ])
        let items = layout.resolve(availableActions: allActions, availableSkills: [])
        XCTAssertEqual(items.map(\.id), ["verify", "assistedSearch", "translate", "ask", "addToDictionary"])
    }

    func testEntryNotCurrentlyAvailableIsSkippedButLayoutUnchanged() {
        // addToDictionary in the layout but NOT offered for this selection (a sentence) → skipped.
        let layout = SelectionMenuLayout(entries: [.init(id: "verify"), .init(id: "addToDictionary"), .init(id: "translate")])
        let items = layout.resolve(availableActions: [.verify, .translate], availableSkills: [])
        XCTAssertEqual(items.map(\.id), ["verify", "translate"])
        XCTAssertTrue(layout.contains("addToDictionary"))   // kept for when it returns
    }

    func testNewSkillNotYetInLayoutIsAppendedVisible() {
        let layout = SelectionMenuLayout.default   // no skill ids
        let items = layout.resolve(
            availableActions: [.verify, .translate],
            availableSkills: [(id: "academic.counterargument.cn", title: "反方观点")])
        XCTAssertEqual(items.last?.id, "academic.counterargument.cn")
        XCTAssertEqual(items.last?.title, "反方观点")
    }

    func testSkillInLayoutRendersAtItsPosition() {
        let layout = SelectionMenuLayout(entries: [
            .init(id: "verify"), .init(id: "practice.x"), .init(id: "translate"),
        ])
        let items = layout.resolve(
            availableActions: [.verify, .translate],
            availableSkills: [(id: "practice.x", title: "技能X")])
        XCTAssertEqual(items.map(\.id), ["verify", "practice.x", "translate"])
    }

    func testGenericSkillIcon() {
        XCTAssertEqual(SelectionMenuItem.skill(id: "x", title: "技能X").systemImage, "wand.and.stars")
        XCTAssertEqual(SelectionMenuItem.action(.verify).systemImage, SelectionAction.verify.systemImage)
    }

    func testDefaultMatchesConfigurableActions() {
        XCTAssertEqual(SelectionMenuLayout.default.entries.map(\.id),
                       SelectionMenuLayout.configurableActions.map(\.rawValue))
    }

    // MARK: - Editor

    func testEditorRowsKeepHiddenEntriesSoTheyCanBeToggledBack() {
        // Unlike resolve(), the editor must SHOW a hidden row (with visible == false).
        let layout = SelectionMenuLayout(entries: [
            .init(id: "verify"), .init(id: "ask", visible: false),
        ])
        let rows = layout.editorRows(availableActions: [.verify, .ask], availableSkills: [])
        XCTAssertEqual(rows.map(\.id), ["verify", "ask"])
        XCTAssertEqual(rows.map(\.visible), [true, false])
    }

    func testEditorRowsAppendNewlyAvailableItems() {
        let layout = SelectionMenuLayout(entries: [.init(id: "verify")])
        let rows = layout.editorRows(
            availableActions: [.verify, .addToDictionary],
            availableSkills: [(id: "practice.x", title: "技能X")])
        XCTAssertEqual(rows.map(\.id), ["verify", "addToDictionary", "practice.x"])
        XCTAssertTrue(rows.allSatisfy(\.visible))   // appended items default visible
    }

    func testEditorRowsSkipDisabledSkillEntries() {
        // A skill in the layout but no longer enabled → not shown in the editor.
        let layout = SelectionMenuLayout(entries: [.init(id: "verify"), .init(id: "practice.gone")])
        let rows = layout.editorRows(availableActions: [.verify], availableSkills: [])
        XCTAssertEqual(rows.map(\.id), ["verify"])
    }

    func testFromRowsRoundTripsThroughEditorRows() {
        let layout = SelectionMenuLayout(entries: [
            .init(id: "ask"), .init(id: "verify", visible: false), .init(id: "practice.x"),
        ])
        let rows = layout.editorRows(
            availableActions: [.verify, .ask],
            availableSkills: [(id: "practice.x", title: "技能X")])
        XCTAssertEqual(SelectionMenuLayout.from(rows: rows), layout)
    }
}
