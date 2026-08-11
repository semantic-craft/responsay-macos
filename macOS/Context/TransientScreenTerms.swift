import AppKit
import Foundation
import ResponsayCore
import os

/// 517 — this capture's transient ASR bias terms, harvested from the visible screen at capture
/// start (真·屏幕感知辅助识别). Weak-prompt lane ONLY: the terms never touch the dictionary,
/// hard-match or disk — they live in memory for one capture and are
/// replaced at the next `prepareCapture`, so screen noise can never be "learned". Each speech
/// router owns one instance; Quick Capture and Voice Assistant cannot clear or reuse each other's
/// screen text.
final class TransientScreenTerms: @unchecked Sendable {
    struct CaptureGeneration: Sendable {
        fileprivate let value: UInt64
    }

    private struct State {
        var generation: UInt64 = 0
        var terms: [String] = []
        var harvestWasScheduled = true
        var harvestTask: Task<Void, Never>?
    }

    private let store = OSAllocatedUnfairLock<State>(initialState: State())

    /// The current capture's harvested terms (empty when 屏幕上下文 is off or nothing landed yet).
    var current: [String] { store.withLock { $0.terms } }

    /// Starts one capture generation before the adapter starts. Async config preparation may wait
    /// for the corresponding harvest decision; the actual AX read is not scheduled until the
    /// adapter has started successfully.
    @discardableResult
    func prepareCapture() -> CaptureGeneration {
        let (task, generation) = store.withLock { state in
            let priorTask = state.harvestTask
            state.generation &+= 1
            state.terms = []
            state.harvestWasScheduled = false
            state.harvestTask = nil
            return (priorTask, CaptureGeneration(value: state.generation))
        }
        task?.cancel()
        return generation
    }

    /// Replaces the current value and invalidates any older detached harvest still in flight.
    func set(_ terms: [String]) {
        let task = store.withLock { state in
            let priorTask = state.harvestTask
            state.generation &+= 1
            state.terms = terms
            state.harvestWasScheduled = true
            state.harvestTask = nil
            return priorTask
        }
        task?.cancel()
    }

    func finishCapture() { set([]) }

    /// Called after a prepared adapter start to harvest OFF the hot path. Returns synchronously —
    /// the Fn→录音 path never waits on AX. Fail-open: a slow or failed collect
    /// just means this capture gets no transient terms. Returns the spawned task (nil when
    /// 屏幕上下文 is off) so tests can await the landing deterministically.
    @discardableResult
    func beginHarvest(
        isEnabled: Bool = ScreenContextSettings.isEnabled,
        gateDecision: CaptureGateDecision = .allowed,
        targetProcessIdentifier: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier,
        dictionaryTerms: @escaping @Sendable () -> [String] = { ContextHotwordSettings.biasingSets().weakPrompt },
        collect: @escaping @Sendable (pid_t) async -> String? = {
            VisibleTextCollector.collect(processIdentifier: $0)
        }
    ) -> Task<Void, Never>? {
        let generation = store.withLock { $0.generation }
        guard isEnabled, gateDecision.isAllowed, let targetProcessIdentifier else {
            publish(task: nil, generation: generation)
            return nil
        }
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let text = await collect(targetProcessIdentifier), !text.isEmpty else { return }
            let harvested = ScreenTermHarvester.harvest(text, excluding: dictionaryTerms())
            self?.store.withLock {
                guard $0.generation == generation, !Task.isCancelled else { return }
                $0.terms = harvested
            }
        }
        publish(task: task, generation: generation)
        return task
    }

    /// Waits for the harvest that belongs to this capture, but never holds up Qwen/Volc request
    /// preparation beyond the bounded budget. A timeout yields no transient terms; a late task is
    /// still generation-guarded and may help stop-time HTTP providers in the same capture.
    func awaitCurrentHarvest(
        for captureGeneration: CaptureGeneration? = nil,
        timeoutNanoseconds: UInt64 = 400_000_000
    ) async -> [String] {
        let generation = captureGeneration?.value ?? store.withLock { $0.generation }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let deadline = startedAt.addingReportingOverflow(timeoutNanoseconds)
        let expiresAt = deadline.overflow ? UInt64.max : deadline.partialValue
        let task: Task<Void, Never>?
        while true {
            let scheduled = store.withLock { state -> (matches: Bool, ready: Bool, task: Task<Void, Never>?) in
                (state.generation == generation, state.harvestWasScheduled, state.harvestTask)
            }
            guard scheduled.matches else { return [] }
            if scheduled.ready {
                task = scheduled.task
                break
            }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < expiresAt, !Task.isCancelled else { return [] }
            do {
                try await Task.sleep(nanoseconds: min(1_000_000, expiresAt - now))
            } catch {
                return []
            }
        }

        guard let task else { return terms(for: generation) }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < expiresAt else { return [] }
        let remainingNanoseconds = expiresAt - now
        return await withCheckedContinuation { continuation in
            let gate = HarvestWaitGate(continuation: continuation)
            Task {
                await task.value
                gate.resume(terms(for: generation))
            }
            Task {
                do {
                    try await Task.sleep(nanoseconds: remainingNanoseconds)
                    gate.resume([])
                } catch {
                    gate.resume([])
                }
            }
        }
    }

    private func publish(task: Task<Void, Never>?, generation: UInt64) {
        store.withLock { state in
            guard state.generation == generation else {
                task?.cancel()
                return
            }
            state.harvestWasScheduled = true
            state.harvestTask = task
        }
    }

    private func terms(for generation: UInt64) -> [String] {
        store.withLock { $0.generation == generation ? $0.terms : [] }
    }
}

private final class HarvestWaitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String], Never>?

    init(continuation: CheckedContinuation<[String], Never>) {
        self.continuation = continuation
    }

    func resume(_ terms: [String]) {
        let continuation = lock.withLock { () -> CheckedContinuation<[String], Never>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: terms)
    }
}
