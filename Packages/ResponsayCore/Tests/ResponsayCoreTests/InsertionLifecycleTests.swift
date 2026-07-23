import Testing
@testable import ResponsayCore

/// 509 — insertion auto-learn lifecycle state machine. Pure logic, headless.
struct InsertionLifecycleTests {
    @Test func startsInserted() {
        let lc = InsertionLifecycle()
        #expect(lc.state == .inserted)
        #expect(lc.attempts == 0)
        #expect(lc.isTerminal == false)
    }

    @Test func recordEditBumpsAttemptsRepeatably() {
        var lc = InsertionLifecycle()
        lc.recordEdit()
        #expect(lc.state == .edited)
        #expect(lc.attempts == 1)
        lc.recordEdit()
        #expect(lc.attempts == 2)
        #expect(lc.isTerminal == false)
    }

    @Test func learnedIsTerminalAndKeepsAttempts() {
        var lc = InsertionLifecycle()
        lc.recordEdit()
        lc.recordLearned()
        #expect(lc.state == .learned)
        #expect(lc.isTerminal)
        #expect(lc.attempts == 1)
    }

    @Test func expiredAbandonedRevertedAreTerminal() {
        var e = InsertionLifecycle(); e.recordExpired()
        #expect(e.state == .expired); #expect(e.isTerminal)
        var a = InsertionLifecycle(); a.recordAbandoned()
        #expect(a.state == .abandoned); #expect(a.isTerminal)
        var r = InsertionLifecycle(); r.recordReverted()
        #expect(r.state == .reverted); #expect(r.isTerminal)
    }

    @Test func firstTerminalWins() {
        var lc = InsertionLifecycle()
        lc.recordLearned()
        lc.recordExpired()   // ignored — already terminal
        lc.recordEdit()      // ignored
        #expect(lc.state == .learned)
        #expect(lc.attempts == 0)
    }

    @Test func editAfterTerminalIgnored() {
        var lc = InsertionLifecycle()
        lc.recordExpired()
        lc.recordEdit()
        #expect(lc.state == .expired)
        #expect(lc.attempts == 0)
    }

    @Test func diagnosticFieldsCarryStateAndAttempts() {
        var lc = InsertionLifecycle()
        lc.recordEdit(); lc.recordEdit(); lc.recordLearned()
        #expect(lc.diagnosticFields["state"] == "learned")
        #expect(lc.diagnosticFields["attempts"] == "2")
    }
}
