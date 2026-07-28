import Foundation
import OSLog
import ResponsayCore

/// 434 — drives the auto-learn flywheel on the macOS side. Holds the cross-edit
/// processor (the learn half) and a `PostInsertEditWatcher` (the detect half), reading the
/// focused field via an injected snapshot reader (Accessibility).
///
/// Lifecycle, wired from `CaptureController`:
/// - `noteInsertion()` right after Responsay inserts dictation text → snapshot the field.
/// - `checkForCorrection()` at the start of the next capture → re-read the field; if the user
///   edited what we inserted, feed the (inserted, final) pair to the learner and persist any
///   promoted term to the auto recognition dictionary.
///
/// The snapshot READER (AX) is injected, so the orchestration is unit-tested via
/// `PostInsertEditWatcher` / `AutoLearnHotwordProcessor`; only the live AX timing needs a real
/// device.
@MainActor
final class HotwordAutoLearnController {
    private var watcher = PostInsertEditWatcher()
    private let snapshotReader: () -> (text: String, app: String, sceneID: String?, windowTitle: String?)?
    private let processor: AutoLearnHotwordProcessor
    private let isEnabled: () -> Bool
    private let notify: (String) -> Void
    private var observationTask: Task<Void, Never>?
    private var lastObservedSnapshot: (text: String, app: String, sceneID: String?, windowTitle: String?)?
    private var stableSnapshotPolls = 0
    // 509 — observable lifecycle of the in-flight insertion (terminal state + edit attempts).
    // Pure observability: it never gates whether learning fires.
    private var lifecycle: InsertionLifecycle?
    private var insertedText: String?
    private var insertedApp: String?
    private var lastCountedEdit: String?
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "auto-learn")

    /// `isEnabled` and `notify` are injected for the same reason the snapshot reader is: the
    /// defaults read and the toast post are the two places this controller reaches outside the
    /// process. Left hardcoded, a test could only exercise the flywheel by flipping the real
    /// `AutoLearnHotwordSettings` key and firing a real toast at whoever is at the keyboard —
    /// tests run inside the app (`TEST_HOST`), so that notification is a live one.
    init(
        snapshotReader: @escaping () -> (text: String, app: String, sceneID: String?, windowTitle: String?)?,
        processor: AutoLearnHotwordProcessor = .live(),
        isEnabled: @escaping () -> Bool = { AutoLearnHotwordSettings.isEnabled },
        notify: @escaping (String) -> Void = { term in
            NotificationCenter.default.post(
                name: .autoLearnHotwordDidAdd, object: nil, userInfo: ["term": term])
        }
    ) {
        self.snapshotReader = snapshotReader
        self.processor = processor
        self.isEnabled = isEnabled
        self.notify = notify
    }

    /// Snapshot the focused field right after Responsay inserted into it. No-op when disabled
    /// or the field can't be read (e.g. AX untrusted, non-text field).
    func noteInsertion() {
        guard isEnabled() else { return }
        guard let snap = snapshotReader() else {
            log.info("Auto-learn skipped post-insert snapshot; readable false")
            return
        }
        log.info("Auto-learn noted post-insert snapshot; chars \(snap.text.count, privacy: .public); app \(snap.app, privacy: .public); scene \(String(describing: snap.sceneID != nil), privacy: .public)")
        lastObservedSnapshot = nil
        stableSnapshotPolls = 0
        watcher.noteInsertion(fieldText: snap.text, app: snap.app, sceneID: snap.sceneID)
        lifecycle = InsertionLifecycle()   // 509
        insertedText = snap.text
        insertedApp = snap.app
        lastCountedEdit = nil
        startObservationWindow()
    }

    /// Re-read the focused field before the next capture; learn from any edit to the snapshot.
    @discardableResult
    func checkForCorrection() -> Bool {
        guard isEnabled() else { return false }
        guard let snap = snapshotReader() else {
            log.info("Auto-learn correction check cleared; readable false")
            lastObservedSnapshot = nil
            stableSnapshotPolls = 0
            _ = watcher.observeEdit(fieldText: nil, app: nil, sceneID: nil)
            finishLifecycle(.abandoned)   // 509: field unreadable → learn path is dead
            return false
        }
        guard snapshotIsStable(snap) else { return false }
        // 509: count distinct post-insert edits for the lifecycle (observability only).
        if let insertedText, snap.text != insertedText, snap.text != lastCountedEdit {
            lifecycle?.recordEdit()
            lastCountedEdit = snap.text
        }
        guard let edit = watcher.observeEdit(
            fieldText: snap.text,
            app: snap.app,
            sceneID: snap.sceneID
        ) else {
            log.debug("Auto-learn stable snapshot yielded no correction; chars \(snap.text.count, privacy: .public); app \(snap.app, privacy: .public); scene \(String(describing: snap.sceneID != nil), privacy: .public); stablePolls \(self.stableSnapshotPolls, privacy: .public)")
            return false
        }
        log.info("Auto-learn observed correction; insertedChars \(edit.inserted.count, privacy: .public); finalChars \(edit.userFinal.count, privacy: .public); app \(snap.app, privacy: .public); scene \(String(describing: snap.sceneID != nil), privacy: .public)")
        finishLifecycle(.learned)   // 509
        processEdit(
            inserted: edit.inserted,
            userFinal: edit.userFinal,
            app: snap.app,
            windowTitle: snap.windowTitle)
        return true
    }

    /// Feed one (inserted, userFinal) pair to the learner; persist + return any promoted terms.
    /// No-op when the 自动学习热词 toggle is off.
    @discardableResult
    func recordEdit(inserted: String, userFinal: String) -> [String] {
        processEdit(inserted: inserted, userFinal: userFinal, app: nil, windowTitle: nil)
        return []
    }

    private func startObservationWindow() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            // 444 — 18s observation window (36 × 500ms): 15s to edit + ~3s stable debounce.
            // The watcher keeps the window
            // open across benign edits, so delayed corrections inside the window can
            // still be learned without observing the field indefinitely.
            for _ in 0..<36 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                if self.checkForCorrection() { return }
            }
            guard let self else { return }
            self.log.info("Auto-learn observation expired; lastChars \(self.lastObservedSnapshot?.text.count ?? -1, privacy: .public); stablePolls \(self.stableSnapshotPolls, privacy: .public); app \(self.lastObservedSnapshot?.app ?? "none", privacy: .public); scene \(String(describing: self.lastObservedSnapshot?.sceneID != nil), privacy: .public)")
            self.finishLifecycle(.expired)   // 509
        }
    }

    /// 509 — record the insertion's terminal state (first terminal wins), emit one autolearn
    /// diagnostic, and clear the lifecycle. Observability only.
    private func finishLifecycle(_ terminal: InsertionState) {
        guard var lifecycle, !lifecycle.isTerminal else { self.lifecycle = nil; return }
        switch terminal {
        case .learned: lifecycle.recordLearned()
        case .expired: lifecycle.recordExpired()
        case .abandoned: lifecycle.recordAbandoned()
        case .reverted: lifecycle.recordReverted()
        case .inserted, .edited: return
        }
        var fields = lifecycle.diagnosticFields
        if let insertedApp { fields["app"] = insertedApp }
        log.info("Auto-learn lifecycle \(lifecycle.state.rawValue, privacy: .public); attempts \(lifecycle.attempts, privacy: .public)")
        Diag.autolearn(.info, "插入生命周期", fields: fields)
        self.lifecycle = nil
        insertedText = nil
        insertedApp = nil
        lastCountedEdit = nil
    }

    private func processEdit(inserted: String, userFinal: String, app: String?, windowTitle: String?) {
        observationTask?.cancel()
        lastObservedSnapshot = nil
        stableSnapshotPolls = 0
        log.info("Auto-learn processing correction; insertedChars \(inserted.count, privacy: .public); finalChars \(userFinal.count, privacy: .public); app \(String(describing: app != nil), privacy: .public); window \(String(describing: windowTitle != nil), privacy: .public)")
        let context = HotwordCorrectionContext(
            insertedText: inserted,
            userFinalText: userFinal,
            appName: app,
            windowTitle: windowTitle)
        Task { @MainActor [processor, notify] in
            let result = await processor.process(context)
            // Toast only for specialized terms; ordinary terms are added silently (PRD §3 Tier 1/2).
            for term in result.notifiedTerms {
                notify(term)
            }
        }
    }

    private func snapshotIsStable(_ snap: (text: String, app: String, sceneID: String?, windowTitle: String?)) -> Bool {
        if let lastObservedSnapshot,
           lastObservedSnapshot.text == snap.text,
           lastObservedSnapshot.app == snap.app,
           lastObservedSnapshot.sceneID == snap.sceneID {
            stableSnapshotPolls += 1
        } else {
            // ponytail: ~3s debounce avoids learning partial multi-step edits like "Clou".
            lastObservedSnapshot = snap
            stableSnapshotPolls = 0
        }
        return stableSnapshotPolls >= 6
    }
}
