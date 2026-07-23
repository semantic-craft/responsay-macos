import AppKit
import OSLog
import ResponsayCore

@MainActor
final class CaptureDiagnosticsController {
    static let insertProbeMarker = "SIRINSERTPROBE"
    static let autoLearnProbeText = "I USE CLOUD Xcode EVERY DAY。"

    private let vm: QuickCaptureViewModel
    private let targetTracker: TargetAppTracker
    private let contextReader: AccessibilityContextReader
    private let selectionReader: SelectionTextReader
    private let log: Logger
    private let noteAutoLearnInsertion: () -> Void

    init(
        vm: QuickCaptureViewModel,
        targetTracker: TargetAppTracker,
        contextReader: AccessibilityContextReader,
        selectionReader: SelectionTextReader,
        log: Logger,
        noteAutoLearnInsertion: @escaping () -> Void = {}
    ) {
        self.vm = vm
        self.targetTracker = targetTracker
        self.contextReader = contextReader
        self.selectionReader = selectionReader
        self.log = log
        self.noteAutoLearnInsertion = noteAutoLearnInsertion
    }

    func probeContext() {
        targetTracker.capture()
        let context = contextReader.readContext(from: targetTracker.target)
        let diag = contextReader.lastDiagnostics
        log.info("Context probe requested; target \(context.appName ?? "unknown", privacy: .public); bundle \(context.bundleIdentifier ?? "unknown", privacy: .public); window \(String(describing: context.windowTitle != nil), privacy: .public); selected \(String(describing: context.selectedText != nil), privacy: .public); before \(String(describing: context.textBeforeCursor != nil), privacy: .public); after \(String(describing: context.textAfterCursor != nil), privacy: .public); hotwords \(context.hotwords.count, privacy: .public); role \(diag.role ?? "none", privacy: .public); hasText \(diag.hasTextElement, privacy: .public); markerCapable \(diag.markerCapable, privacy: .public)")
    }

    func probeInsert() {
        targetTracker.capture()
        let target = targetTracker.target
        let inserter = CGEventTextInserter(targetProvider: { target })
        Task {
            var inserted = false
            do {
                try await inserter.insert(Self.insertProbeMarker)
                inserted = true
            } catch {
                log.error("Insert probe failed: \(error.localizedDescription, privacy: .public)")
            }
            log.info("Insert probe requested; target \(target?.localizedName ?? "unknown", privacy: .public); bundle \(target?.bundleIdentifier ?? "unknown", privacy: .public); inserted \(inserted, privacy: .public)")
        }
    }

    #if DEBUG
    func probeAutoLearnSeed() {
        targetTracker.capture()
        let target = targetTracker.target
        let inserter = CGEventTextInserter(targetProvider: { target })
        Task { @MainActor in
            var inserted = false
            do {
                try await inserter.insert(Self.autoLearnProbeText)
                inserted = true
                for _ in 0..<10 {
                    try? await Task.sleep(for: .milliseconds(200))
                    if contextReader.readFocusedFieldSnapshot(from: target)?.text.contains(Self.autoLearnProbeText) == true {
                        break
                    }
                }
                noteAutoLearnInsertion()
            } catch {
                log.error("Auto-learn probe failed: \(error.localizedDescription, privacy: .public)")
            }
            log.info("Auto-learn probe requested; target \(target?.localizedName ?? "unknown", privacy: .public); bundle \(target?.bundleIdentifier ?? "unknown", privacy: .public); inserted \(inserted, privacy: .public)")
        }
    }
    #endif

    func probeSelection() {
        targetTracker.capture()
        let target = targetTracker.target
        Task {
            let text = await selectionReader.readSelectedText(from: target)
            let read = text != nil && !text!.isEmpty
            let chars = text?.count ?? 0
            log.info("Selection probe requested; target \(target?.localizedName ?? "unknown", privacy: .public); bundle \(target?.bundleIdentifier ?? "unknown", privacy: .public); selectionRead \(read, privacy: .public); chars \(chars, privacy: .public)")
        }
    }

    #if DEBUG
    func showDesignReviewFixture() {
        vm.loadDesignReviewFixture()
    }

    func showCapsuleListeningFixture() {
        vm.loadCapsuleListeningFixture()
    }

    func showCapsuleFinalizingFixture() {
        vm.loadCapsuleFinalizingFixture()
    }

    func showCapsuleErrorFixture() {
        vm.loadCapsuleErrorFixture()
    }

    func clearDesignFixture() {
        vm.clearDesignFixture()
    }
    #endif
}
