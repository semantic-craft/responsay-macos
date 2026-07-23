import Testing
import Foundation
@testable import ResponsayCore

/// 169 — Selection-Ask privacy truncation. Verification: truncation boundary; log redaction.
struct SelectionAskPolicyTests {
    @Test func underLimit_isNotTruncated() {
        let text = String(repeating: "a", count: 100)
        let t = SelectionAskPolicy.truncate(text)
        #expect(t.wasTruncated == false)
        #expect(t.text.count == 100)
    }

    @Test func atLimit_isNotTruncated() {
        let text = String(repeating: "a", count: SelectionAskPolicy.defaultLimit)
        #expect(SelectionAskPolicy.truncate(text).wasTruncated == false)
    }

    @Test func overLimit_truncatesToDefault() {
        let text = String(repeating: "a", count: SelectionAskPolicy.defaultLimit + 1)
        let t = SelectionAskPolicy.truncate(text)
        #expect(t.wasTruncated)
        #expect(t.text.count == SelectionAskPolicy.defaultLimit)
        #expect(t.originalLength == SelectionAskPolicy.defaultLimit + 1)
    }

    @Test func confirmedExpansion_allowsHigherCap() {
        let text = String(repeating: "a", count: 6000)
        let t = SelectionAskPolicy.confirmedExpansion(text, confirmedLimit: 8000)
        #expect(t.wasTruncated == false)        // 6000 < 8000
        #expect(t.text.count == 6000)
    }

    @Test func confirmedExpansion_neverBelowDefault() {
        let text = String(repeating: "a", count: 5000)
        // A bogus lower cap can't shrink below the 4000 default.
        let t = SelectionAskPolicy.confirmedExpansion(text, confirmedLimit: 10)
        #expect(t.text.count == SelectionAskPolicy.defaultLimit)
    }

    @Test func redactedLog_omitsRawText() {
        let secret = "我的身份证号 " + String(repeating: "x", count: 5000)
        let t = SelectionAskPolicy.truncate(secret)
        let line = SelectionAskPolicy.redactedLog(t)
        #expect(line.contains("身份证") == false)
        #expect(line.contains("truncated=true"))
    }
}

/// 155 — Selection-Ask core (bounded multi-turn). Verification: truncation; session turns; legal [待核].
struct SelectionAskSessionTests {
    @Test func init_appliesTruncation() {
        let raw = String(repeating: "字", count: SelectionAskPolicy.defaultLimit + 50)
        let session = SelectionAskSession(rawSelection: raw)
        #expect(session.wasTruncated)
        #expect(session.selection.count == SelectionAskPolicy.defaultLimit)
        #expect(session.originalLength == SelectionAskPolicy.defaultLimit + 50)
    }

    @Test func multiTurn_appendsQuestionsAndAnswers() {
        let session = SelectionAskSession(rawSelection: "some clause")
            .asking("这条是什么意思？")
            .answeringLast("它表示……")
            .asking("有例外吗？")
        #expect(session.turns.count == 2)
        #expect(session.turns[0].answer == "它表示……")
        #expect(session.turns[1].question == "有例外吗？")
        #expect(session.turns[1].answer == nil)
    }

    @Test func turns_areBounded() {
        var session = SelectionAskSession(rawSelection: "x")
        for i in 0..<(SelectionAskSession.maxTurns + 3) {
            session = session.asking("q\(i)")
        }
        #expect(session.turns.count == SelectionAskSession.maxTurns)
        #expect(session.reachedTurnLimit)
    }

    @Test func pinnedFlag_toggles() {
        let session = SelectionAskSession(rawSelection: "x").settingPinned(true)
        #expect(session.pinned)
        #expect(session.settingPinned(false).pinned == false)
    }

    @Test func legalMode_preservesPendingOnNewCoordinates() {
        let session = SelectionAskSession(rawSelection: "某合同条款", mode: .legal)
        let anchors = session.guardedLegalAnchors(for: "应适用《民法典》第577条。")
        #expect(anchors.count == 1)
        #expect(anchors[0].status == .pending)     // [待核] preserved
    }

    @Test func generalMode_doesNotEmitLegalAnchors() {
        let session = SelectionAskSession(rawSelection: "just text", mode: .general)
        #expect(session.guardedLegalAnchors(for: "依据《民法典》第577条。").isEmpty)
    }

    // Multi-turn context (openless parity): a follow-up must carry the prior
    // Q&A to the model, not re-ask the bare selection.
    @Test func conversationContext_firstTurn_isJustTheSelection() {
        // No answered turns yet → byte-identical to the selection, so the
        // single-turn path is unchanged.
        let session = SelectionAskSession(rawSelection: "some clause")
            .asking("这条是什么意思？")          // asked, not yet answered
        #expect(session.conversationContext() == "some clause")
    }

    @Test func conversationContext_threadsAnsweredTurns() {
        let session = SelectionAskSession(rawSelection: "some clause")
            .asking("这条是什么意思？")
            .answeringLast("它表示甲方负责。")
            .asking("那乙方呢？")               // current turn — its question goes via `question`
        let ctx = session.conversationContext()
        #expect(ctx.contains("some clause"))               // selection retained
        #expect(ctx.contains("这条是什么意思？"))            // prior question
        #expect(ctx.contains("它表示甲方负责。"))            // prior answer
        #expect(ctx.contains("那乙方呢？") == false)         // current question excluded
    }
}
