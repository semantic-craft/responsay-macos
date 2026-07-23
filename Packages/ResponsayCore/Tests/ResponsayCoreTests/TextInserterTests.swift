import Testing
@testable import ResponsayCore

@Test @MainActor func mockInserter_recordsText() async throws {
    let ins = MockTextInserter()
    try await ins.insert("I want this bag.")
    #expect(ins.inserted == ["I want this bag."])
}

@Test @MainActor func mockInserter_throwsWhenSet() async {
    let ins = MockTextInserter(); ins.error = .notAuthorized
    await #expect(throws: InsertError.self) { try await ins.insert("x") }
}

@Test func insertError_notAuthorizedGuidesAccessibilitySetup() {
    #expect(InsertError.notAuthorized.localizedDescription.contains("辅助功能"))
    #expect(InsertError.notAuthorized.localizedDescription.contains(AppBrand.displayName))
}
