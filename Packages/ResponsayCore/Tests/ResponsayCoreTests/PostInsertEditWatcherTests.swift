import Testing
import Foundation
@testable import ResponsayCore

/// 434 — the post-insertion edit detector. After Responsay inserts text, it snapshots the
/// field; before the next capture it re-reads the same field and, if the user edited what we
/// inserted, hands the (inserted, userFinal) pair to the learn flywheel. Pure value type —
/// the macOS layer supplies the AX field reads.
@Suite struct PostInsertEditWatcherTests {
    @Test func detectsAnEditToInsertedTextInTheSameField() {
        var watcher = PostInsertEditWatcher()
        watcher.noteInsertion(fieldText: "把 cloud Xcode 装好", app: "com.apple.dt.Xcode")
        let edit = watcher.observeEdit(fieldText: "把 Claude Code 装好", app: "com.apple.dt.Xcode")
        #expect(edit?.inserted == "把 cloud Xcode 装好")
        #expect(edit?.userFinal == "把 Claude Code 装好")
    }

    @Test func unchangedFieldIsNotAnEdit() {
        var watcher = PostInsertEditWatcher()
        watcher.noteInsertion(fieldText: "Claude Code", app: "app1")
        #expect(watcher.observeEdit(fieldText: "Claude Code", app: "app1") == nil)
    }

    @Test func unchangedPollKeepsWindowOpenForLaterEdit() {
        var watcher = PostInsertEditWatcher()
        watcher.noteInsertion(fieldText: "cloud Xcode", app: "app1")
        #expect(watcher.observeEdit(fieldText: "cloud Xcode", app: "app1") == nil)

        let edit = watcher.observeEdit(fieldText: "Claude Code", app: "app1")

        #expect(edit?.inserted == "cloud Xcode")
        #expect(edit?.userFinal == "Claude Code")
    }

    @Test func differentSceneIsNotAttributed() {
        var watcher = PostInsertEditWatcher()
        watcher.noteInsertion(fieldText: "cloud Xcode", app: "app1", sceneID: "window-a")

        #expect(watcher.observeEdit(fieldText: "Claude Code", app: "app1", sceneID: "window-b") == nil)
    }

    @Test func editInADifferentAppIsNotAttributed() {
        var watcher = PostInsertEditWatcher()
        watcher.noteInsertion(fieldText: "cloud Xcode", app: "app1")
        // Focus moved to another app before the re-read → don't cross-attribute the change.
        #expect(watcher.observeEdit(fieldText: "something else entirely", app: "app2") == nil)
    }

    @Test func snapshotIsConsumedAfterOneObservation() {
        var watcher = PostInsertEditWatcher()
        watcher.noteInsertion(fieldText: "cloud Xcode", app: "app1")
        _ = watcher.observeEdit(fieldText: "Claude Code", app: "app1")
        // A second re-read with no fresh insertion must not re-fire.
        #expect(watcher.observeEdit(fieldText: "Claude Code again", app: "app1") == nil)
    }

    @Test func unreadableFieldYieldsNothing() {
        var watcher = PostInsertEditWatcher()
        watcher.noteInsertion(fieldText: "cloud Xcode", app: "app1")
        #expect(watcher.observeEdit(fieldText: nil, app: "app1") == nil)
    }

    // 444 — only a genuine word replacement learns; benign edits keep the window open.

    @Test func pureAppendDoesNotLearnAndKeepsWindowOpen() {
        var watcher = PostInsertEditWatcher()
        watcher.noteInsertion(fieldText: "我在用 cloud Xcode 写代码", app: "app1")
        // User keeps typing after the dictation — pure addition, nothing to learn.
        #expect(watcher.observeEdit(fieldText: "我在用 cloud Xcode 写代码。", app: "app1") == nil)
        // The window survived: a real correction a poll later is still caught.
        let edit = watcher.observeEdit(fieldText: "我在用 Claude Code 写代码", app: "app1")
        #expect(edit?.inserted == "我在用 cloud Xcode 写代码")
        #expect(edit?.userFinal == "我在用 Claude Code 写代码")
    }

    @Test func transientDeletionKeepsWindowOpenThenLearnsTheRetype() {
        var watcher = PostInsertEditWatcher()
        watcher.noteInsertion(fieldText: "我在用 cloud Xcode 写代码", app: "app1")
        // Poll lands while the user has deleted the wrong term but not yet retyped it —
        // a large removal that must NOT end the window.
        #expect(watcher.observeEdit(fieldText: "我在用  写代码", app: "app1") == nil)
        // Next poll: the corrected term is in place → a clean from→to substitution fires.
        let edit = watcher.observeEdit(fieldText: "我在用 Claude Code 写代码", app: "app1")
        #expect(edit?.userFinal == "我在用 Claude Code 写代码")
    }

    @Test func pureDeletionWithoutReplacementDoesNotLearn() {
        var watcher = PostInsertEditWatcher()
        watcher.noteInsertion(fieldText: "我在用 cloud Xcode 写代码", app: "app1")
        // Deleted the term, never typed a replacement → no from→to pair to learn.
        #expect(watcher.observeEdit(fieldText: "我在用  写代码", app: "app1") == nil)
    }

    @Test func wholesaleRewriteIsNotLearned() {
        var watcher = PostInsertEditWatcher()
        watcher.noteInsertion(fieldText: "the quick brown fox", app: "app1")
        // Reworking the whole sentence is a transcription edit, not a term fix.
        #expect(watcher.observeEdit(fieldText: "a completely different sentence entirely", app: "app1") == nil)
    }

    @Test func vanishedInsertedTextIsNotLearned() {
        // The rebuild false-positive: after a short dictation, the focused field re-reads a
        // TUI's own chrome (e.g. a terminal sitting on "Claude Code …" mid-rebuild). Churn
        // stays under the large-modify floor and a from→to substitution exists, so the
        // legacy guards would learn it — but our inserted text has largely vanished, so the
        // retained-ratio guard rejects it. The window stays open for a real later edit.
        var watcher = PostInsertEditWatcher()
        watcher.noteInsertion(fieldText: "abcdefgh", app: "com.apple.Terminal")
        #expect(watcher.observeEdit(fieldText: "abcZZ", app: "com.apple.Terminal") == nil)
        // A genuine in-place fix landing later (most of the insert preserved) still fires.
        let edit = watcher.observeEdit(fieldText: "abcdefXY", app: "com.apple.Terminal")
        #expect(edit?.userFinal == "abcdefXY")
    }
}
