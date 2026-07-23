import Testing
import Foundation
@testable import ResponsayCore

/// 434 — the auto-learn flywheel coordinator: ties post-insertion edits to the
/// `HotwordLearner` judgment, gated by the user's toggle and deduped against hotwords
/// already in the store. The macOS layer feeds it (inserted, userFinal) pairs detected
/// via AX and persists the promoted terms.
@Suite struct HotwordAutoLearnCoordinatorTests {
    private let inserted = "个人信息处理着，原则"
    private let userFinal = "个人信息处理者，原则"

    @Test func repeatedFixPromotesWhenEnabled() {
        var coord = HotwordAutoLearnCoordinator()
        _ = coord.recordEdit(inserted: inserted, userFinal: userFinal, enabled: true, existingHotwords: [])
        let promoted = coord.recordEdit(inserted: inserted, userFinal: userFinal, enabled: true, existingHotwords: [])
        #expect(promoted == [HotwordCandidate(term: "个人信息处理者", occurrences: 2)])
    }

    @Test func disabledTogglePromotesNothing() {
        var coord = HotwordAutoLearnCoordinator()
        // Even a repeated fix learns nothing while the toggle is off — and the edit is
        // not silently accumulated either, so flipping it on later doesn't back-fill.
        _ = coord.recordEdit(inserted: inserted, userFinal: userFinal, enabled: false, existingHotwords: [])
        let promoted = coord.recordEdit(inserted: inserted, userFinal: userFinal, enabled: false, existingHotwords: [])
        #expect(promoted.isEmpty)
    }

    @Test func alreadyKnownTermIsNotReAdded() {
        var coord = HotwordAutoLearnCoordinator()
        let known: Set<String> = ["个人信息处理者"]
        _ = coord.recordEdit(inserted: inserted, userFinal: userFinal, enabled: true, existingHotwords: known)
        let promoted = coord.recordEdit(inserted: inserted, userFinal: userFinal, enabled: true, existingHotwords: known)
        #expect(promoted.isEmpty)   // already in the store → nothing new to add
    }
}
