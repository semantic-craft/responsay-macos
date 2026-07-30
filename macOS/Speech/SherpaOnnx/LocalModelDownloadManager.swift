import Foundation
import Observation

/// Drives the native download UI for one local model: install state + actions.
/// Independent of the Node-backed model manager — this is the offline path.
@MainActor
@Observable
final class LocalModelDownloadManager: Identifiable {
    enum State: Equatable {
        case checking
        case notInstalled
        case downloading(Double)   // 0...1
        case verifying
        case extracting
        case installed
        case failed(String)
    }

    let spec: LocalModelSpec
    nonisolated var id: String { spec.id }
    private(set) var state: State = .checking
    private(set) var selfCheckSummary: String?
    private var task: Task<Void, Never>?

    init(spec: LocalModelSpec) {
        self.spec = spec
    }

    var displayName: String { spec.displayName }
    var sizeText: String {
        ByteCountFormatter.string(
            fromByteCount: spec.download?.byteSize ?? spec.expected.approxDiskBytes,
            countStyle: .file)
    }
    /// Self-check supports whole-utterance ASR families (SenseVoice, Qwen3-ASR).
    var supportsSelfCheck: Bool { LocalModelSelfCheck.supports(spec.family) }
    var isBusy: Bool {
        switch state {
        case .downloading, .verifying, .extracting: true
        default: false
        }
    }

    func refresh() {
        if isBusy { return }
        state = spec.isInstalled ? .installed : .notInstalled
    }

    func download() {
        guard task == nil else { return }
        state = .downloading(0)
        task = Task { [spec] in
            defer { self.task = nil }
            do {
                try await LocalModelDownloader.install(spec) { phase in
                    Task { @MainActor in self.apply(phase) }
                }
                self.state = .installed
                LocalModelInstallActions.onInstalled(spec)
            } catch is CancellationError {
                self.refresh()
            } catch {
                self.state = .failed(String(describing: error))
            }
        }
    }

    func cancel() { task?.cancel() }

    func delete() {
        guard !isBusy else { return }
        LocalModelInstallActions.beforeDelete(spec)
        do {
            try LocalModelDownloader.remove(spec)
        } catch {
            return
        }
        selfCheckSummary = nil
        refresh()
        LocalModelInstallActions.onDeleted()
    }

    /// Load & Test self-check (issue 162): measures real rtfX vs expected.
    func selfCheck() {
        guard state == .installed, supportsSelfCheck else { return }
        selfCheckSummary = "自检中…"
        let spec = spec
        Task {
            do {
                let report = try await Task.detached { try LocalModelSelfCheck.runASR(spec) }.value
                self.selfCheckSummary = report.summary
            } catch {
                self.selfCheckSummary = "自检失败：\(error)"
            }
        }
    }

    private func apply(_ phase: LocalModelDownloader.Phase) {
        switch phase {
        case .downloading(let fraction): state = .downloading(fraction)
        case .verifying: state = .verifying
        case .extracting: state = .extracting
        }
    }
}
