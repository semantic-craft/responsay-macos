import Foundation

extension QwenRunTaskSession {
    /// Per-attempt task state. A reconnect creates a fresh instance and task ID while the outer
    /// session retains the logical capture's replay and callback-deduplication state.
    actor Attempt {
        enum Outcome: Sendable {
            case final(String)
            case failed(String?)
        }

        private enum StartState: Equatable {
            case waiting
            case started
            case terminated
        }

        private let transport: any QwenRunTaskTransport
        private let taskID: String
        private var finalsByID: [Int: String] = [:]
        private var finalOrder: [Int] = []
        private var pendingPartial = ""
        private var finishSent = false
        private var startState: StartState = .waiting
        private var startWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

        init(transport: any QwenRunTaskTransport, taskID: String) {
            self.transport = transport
            self.taskID = taskID
        }

        func sendRunTask(_ options: Wire.RunTaskOptions) async throws {
            try await transport.send(.text(Wire.runTask(
                taskID: taskID,
                options: options)))
        }

        func sendContinueTask(context: [String]) async throws {
            guard !finishSent, !context.isEmpty else { return }
            try await transport.send(.text(Wire.continueTask(taskID: taskID, context: context)))
        }

        func awaitStarted() async -> Bool {
            switch startState {
            case .started:
                return true
            case .terminated:
                return false
            case .waiting:
                let waiterID = UUID()
                return await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        if Task.isCancelled {
                            continuation.resume(returning: false)
                        } else {
                            startWaiters[waiterID] = continuation
                        }
                    }
                } onCancel: {
                    Task { await self.cancelStartWaiter(waiterID) }
                }
            }
        }

        func sendAudio(_ pcm: Data) async throws {
            try await transport.send(.data(pcm))
        }

        func finish() async throws {
            finishSent = true
            try await transport.send(.text(Wire.finishTask(taskID: taskID)))
        }

        func receive() async throws -> Wire.ServerEvent {
            Wire.decode(try await transport.receive())
        }

        func handle(_ event: Wire.ServerEvent) -> Outcome? {
            switch event {
            case .started:
                resolveStart(.started)
                return nil
            case let .sentence(id, text, isFinal):
                if isFinal {
                    if finalsByID.updateValue(text, forKey: id) == nil {
                        finalOrder.append(id)
                    }
                    pendingPartial = ""
                } else {
                    pendingPartial = text
                }
                return nil
            case .finished:
                resolveStart(.terminated)
                return .final(transcript)
            case let .failure(message):
                resolveStart(.terminated)
                return .failed(message.isEmpty ? nil : message)
            case .ignored:
                return nil
            }
        }

        private var transcript: String {
            var segments = finalOrder.compactMap { finalsByID[$0] }
            if !pendingPartial.isEmpty { segments.append(pendingPartial) }
            return TranscriptJoiner.mergeSegments(segments)
        }

        private func resolveStart(_ state: StartState) {
            guard startState == .waiting else { return }
            startState = state
            let waiters = Array(startWaiters.values)
            startWaiters.removeAll()
            for waiter in waiters { waiter.resume(returning: state == .started) }
        }

        private func cancelStartWaiter(_ id: UUID) {
            startWaiters.removeValue(forKey: id)?.resume(returning: false)
        }
    }
}
