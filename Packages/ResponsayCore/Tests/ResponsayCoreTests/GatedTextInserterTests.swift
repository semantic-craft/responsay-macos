import Testing
@testable import ResponsayCore

/// Pins the one-time insert gate (issue 087 item 9): a capture session inserts at
/// most once, a new session reopens the gate, and a *failed* insert leaves the
/// gate open so a genuine retry can still land.
@Suite @MainActor struct GatedTextInserterTests {
    @Test func insertsOncePerSession() async throws {
        let mock = MockTextInserter()
        let gate = GatedTextInserter(mock)
        try await gate.insert("a")
        try await gate.insert("b")          // blocked — same session
        #expect(mock.inserted == ["a"])
    }

    @Test func beginSessionReopensGate() async throws {
        let mock = MockTextInserter()
        let gate = GatedTextInserter(mock)
        try await gate.insert("a")
        gate.beginSession()
        try await gate.insert("b")
        #expect(mock.inserted == ["a", "b"])
    }

    @Test func failedInsertDoesNotConsumeGate() async {
        let mock = MockTextInserter()
        mock.error = .failed("boom")
        let gate = GatedTextInserter(mock)
        await #expect(throws: (any Error).self) { try await gate.insert("a") }
        #expect(gate.hasInserted == false)   // gate still open for retry
        mock.error = nil
        try? await gate.insert("a")
        #expect(mock.inserted == ["a"])
    }

    @Test func beginSessionRotatesSessionID() {
        let gate = GatedTextInserter(MockTextInserter())
        let first = gate.sessionID
        gate.beginSession()
        #expect(gate.sessionID != first)
    }
}
