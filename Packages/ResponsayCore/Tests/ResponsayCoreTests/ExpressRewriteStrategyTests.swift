import Testing
@testable import ResponsayCore

// 420 — 改写策略 resolves with a faithful default; the app's settings wrapper rides on this.
struct ExpressRewriteStrategyTests {
    @Test func resolve_defaultsToFaithful() {
        #expect(ExpressRewriteStrategy.resolve(stored: nil) == .faithful)
        #expect(ExpressRewriteStrategy.resolve(stored: "") == .faithful)
        #expect(ExpressRewriteStrategy.resolve(stored: "  ") == .faithful)
    }

    @Test func resolve_readsGuessIntent_caseTolerant() {
        #expect(ExpressRewriteStrategy.resolve(stored: "guess_intent") == .guessIntent)
        #expect(ExpressRewriteStrategy.resolve(stored: " Guess_Intent ") == .guessIntent)
        #expect(ExpressRewriteStrategy.resolve(stored: "faithful") == .faithful)
    }

    @Test func resolve_unknownFallsBackToFaithful() {
        #expect(ExpressRewriteStrategy.resolve(stored: "nonsense") == .faithful)
    }
}
