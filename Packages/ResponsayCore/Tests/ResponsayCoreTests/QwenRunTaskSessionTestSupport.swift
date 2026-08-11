import Foundation
@testable import ResponsayCore

struct ScriptedTransportPlan: Sendable {
    var transcripts: [String]
    var failingRunOrdinals: Set<Int> = []
    var failingAfterFinalRunOrdinals: Set<Int> = []
    var hangsAfterStart = false
    var duplicateFinalSentence = false
    var emitsPartialBeforeFinal = false
    var automaticStart = true
    var framesAfterStart: [QwenRunTaskTransportMessage] = []
    var finishFrames: [QwenRunTaskTransportMessage]?
    var firstStartNanos: UInt64 = 0
    var reusedStartNanos: UInt64 = 0
    var clock: VirtualNanosecondClock?
}

struct RunTaskObservation: Sendable, Equatable {
    var taskID: String
    var streaming: String?
    var taskGroup: String?
    var task: String?
    var function: String?
    var model: String?
    var parameterKeys: Set<String>
    var format: String?
    var sampleRate: Int?
    var languageHints: [String]?
    var vocabulary: [String: Int]?
    var vocabularyID: String?
    var heartbeat: Bool?
    var context: [String]
}

struct FinishTaskObservation: Sendable, Equatable {
    var taskID: String
    var streaming: String?
    var hasEmptyInput: Bool
}

actor ScriptedQwenTransportFactory {
    private let plans: [ScriptedTransportPlan]
    private(set) var transports: [ScriptedQwenTransport] = []

    init(_ plans: [ScriptedTransportPlan]) { self.plans = plans }

    var makeCount: Int { transports.count }

    func make(_ request: URLRequest) throws -> any QwenRunTaskTransport {
        _ = request
        guard transports.count < plans.count else { throw ScriptedTransportError.noPlan }
        let transport = ScriptedQwenTransport(plan: plans[transports.count])
        transports.append(transport)
        return transport
    }

    func transport(at index: Int) -> ScriptedQwenTransport? {
        transports.indices.contains(index) ? transports[index] : nil
    }
}

actor ScriptedQwenTransport: QwenRunTaskTransport {
    private let plan: ScriptedTransportPlan
    private let continuation: AsyncThrowingStream<QwenRunTaskTransportMessage, Error>.Continuation
    private let receiver: ScriptedStreamReceiver
    private var currentTaskID: String?
    private var startedTaskIDs = Set<String>()
    private(set) var taskIDs: [String] = []
    private(set) var audioByTask: [String: [Data]] = [:]
    private(set) var vocabularyIDs: [String?] = []
    private(set) var vocabularies: [[String: Int]?] = []
    private(set) var runTasks: [RunTaskObservation] = []
    private(set) var finishTasks: [FinishTaskObservation] = []
    private(set) var continueContexts: [[String]] = []
    private(set) var isClosed = false

    init(plan: ScriptedTransportPlan) {
        self.plan = plan
        let pair = AsyncThrowingStream<QwenRunTaskTransportMessage, Error>.makeStream()
        continuation = pair.continuation
        receiver = ScriptedStreamReceiver(pair.stream)
    }

    var runCount: Int { taskIDs.count }
    var isViable: Bool { !isClosed }

    func send(_ message: QwenRunTaskTransportMessage) async throws {
        guard !isClosed else { throw ScriptedTransportError.closed }
        switch message {
        case let .data(data):
            guard let currentTaskID,
                  startedTaskIDs.contains(currentTaskID) else {
                throw ScriptedTransportError.audioBeforeStart
            }
            audioByTask[currentTaskID, default: []].append(data)
        case let .text(text):
            let root = try json(text)
            let header = root["header"] as? [String: Any]
            let action = header?["action"] as? String
            let taskID = header?["task_id"] as? String ?? ""
            switch action {
            case "run-task":
                currentTaskID = taskID
                taskIDs.append(taskID)
                let payload = root["payload"] as? [String: Any]
                let parameters = payload?["parameters"] as? [String: Any]
                vocabularyIDs.append(parameters?["vocabulary_id"] as? String)
                vocabularies.append(parameters?["vocabulary"] as? [String: Int])
                runTasks.append(.init(
                    taskID: taskID,
                    streaming: header?["streaming"] as? String,
                    taskGroup: payload?["task_group"] as? String,
                    task: payload?["task"] as? String,
                    function: payload?["function"] as? String,
                    model: payload?["model"] as? String,
                    parameterKeys: Set(parameters?.keys.map { $0 } ?? []),
                    format: parameters?["format"] as? String,
                    sampleRate: parameters?["sample_rate"] as? Int,
                    languageHints: parameters?["language_hints"] as? [String],
                    vocabulary: parameters?["vocabulary"] as? [String: Int],
                    vocabularyID: parameters?["vocabulary_id"] as? String,
                    heartbeat: parameters?["heartbeat"] as? Bool,
                    context: context(from: (payload?["input"] as? [String: Any])?["context"])))
                let ordinal = taskIDs.count
                if plan.failingRunOrdinals.contains(ordinal) {
                    continuation.yield(.text(serverEventMessage(
                        taskID: taskID,
                        event: "task-failed",
                        errorMessage: "rejected")))
                    return
                }
                if plan.automaticStart {
                    emitStart(taskID: taskID, ordinal: ordinal)
                }
            case "finish-task":
                let payload = root["payload"] as? [String: Any]
                let input = payload?["input"] as? [String: Any]
                finishTasks.append(.init(
                    taskID: taskID,
                    streaming: header?["streaming"] as? String,
                    hasEmptyInput: input?.isEmpty == true))
                if plan.hangsAfterStart { return }
                if let finishFrames = plan.finishFrames {
                    for frame in finishFrames { continuation.yield(frame) }
                    currentTaskID = nil
                    startedTaskIDs.remove(taskID)
                    return
                }
                let ordinal = taskIDs.count
                guard plan.transcripts.indices.contains(ordinal - 1) else {
                    throw ScriptedTransportError.noTranscript
                }
                let transcript = plan.transcripts[ordinal - 1]
                if plan.emitsPartialBeforeFinal {
                    continuation.yield(.text(sentenceEventMessage(
                        taskID: taskID, id: 1, text: "partial hypothesis", isFinal: false)))
                }
                continuation.yield(.text(sentenceEventMessage(
                    taskID: taskID, id: 1, text: transcript, isFinal: true)))
                if plan.duplicateFinalSentence {
                    continuation.yield(.text(sentenceEventMessage(
                        taskID: taskID, id: 1, text: transcript, isFinal: true)))
                }
                if plan.failingAfterFinalRunOrdinals.contains(ordinal) {
                    continuation.yield(.text(serverEventMessage(
                        taskID: taskID,
                        event: "task-failed",
                        errorMessage: "connection lost after final")))
                } else {
                    continuation.yield(.text(serverEventMessage(
                        taskID: taskID, event: "task-finished")))
                }
                currentTaskID = nil
                startedTaskIDs.remove(taskID)
            case "continue-task":
                let payload = root["payload"] as? [String: Any]
                let input = payload?["input"] as? [String: Any]
                continueContexts.append(context(from: input?["context"]))
            default:
                break
            }
        }
    }

    func emitStarted() {
        guard let taskID = currentTaskID else { return }
        emitStart(taskID: taskID, ordinal: taskIDs.count)
    }

    func receive() async throws -> QwenRunTaskTransportMessage {
        guard let message = try await receiver.next() else { throw ScriptedTransportError.closed }
        return message
    }

    func close() async {
        isClosed = true
        continuation.finish()
    }

    func simulateServerClose() {
        isClosed = true
        continuation.finish()
    }

    private func json(_ text: String) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw ScriptedTransportError.malformedJSON
        }
        return root
    }

    private func emitStart(taskID: String, ordinal: Int) {
        guard startedTaskIDs.insert(taskID).inserted else { return }
        if let clock = plan.clock {
            clock.advance(by: ordinal == 1 ? plan.firstStartNanos : plan.reusedStartNanos)
        }
        continuation.yield(.text(serverEventMessage(taskID: taskID, event: "task-started")))
        for frame in plan.framesAfterStart { continuation.yield(frame) }
    }

    private func context(from value: Any?) -> [String] {
        guard let messages = value as? [[String: Any]] else { return [] }
        return messages.compactMap { message in
            let content = message["content"] as? [[String: Any]]
            return content?.first?["text"] as? String
        }
    }
}

func serverEventMessage(
    taskID: String,
    event: String,
    errorMessage: String? = nil
) -> String {
    var header = ["task_id": taskID, "event": event]
    if let errorMessage {
        header["error_code"] = "TEST_ERROR"
        header["error_message"] = errorMessage
    }
    let root: [String: Any] = ["header": header, "payload": [:] as [String: Any]]
    let data = try! JSONSerialization.data(withJSONObject: root)
    return String(decoding: data, as: UTF8.self)
}

func sentenceEventMessage(
    taskID: String,
    id: Int,
    text: String,
    isFinal: Bool,
    heartbeat: Bool = false
) -> String {
    let root: [String: Any] = [
        "header": ["task_id": taskID, "event": "result-generated"],
        "payload": ["output": ["sentence": [
            "sentence_id": id,
            "text": text,
            "sentence_end": isFinal,
            "heartbeat": heartbeat,
        ]]],
    ]
    let data = try! JSONSerialization.data(withJSONObject: root)
    return String(decoding: data, as: UTF8.self)
}

private final class ScriptedStreamReceiver: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<QwenRunTaskTransportMessage, Error>.Iterator

    init(_ stream: AsyncThrowingStream<QwenRunTaskTransportMessage, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> QwenRunTaskTransportMessage? {
        try await iterator.next()
    }
}

private enum ScriptedTransportError: Error {
    case noPlan
    case closed
    case audioBeforeStart
    case noTranscript
    case malformedJSON
}

final class LockedTaskIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(_ values: [String]) { self.values = values }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty ? UUID().uuidString : values.removeFirst()
    }
}

final class VirtualNanosecondClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    var now: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by nanos: UInt64) {
        lock.lock()
        value += nanos
        lock.unlock()
    }
}

actor SentenceSink {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

actor MetricSink {
    private(set) var values: [QwenRunTaskStartMetric] = []
    func append(_ value: QwenRunTaskStartMetric) { values.append(value) }
}

actor ManualSleeper {
    private var continuation: CheckedContinuation<Void, Error>?
    var isWaiting: Bool { continuation != nil }

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func fire() {
        continuation?.resume()
        continuation = nil
    }
}

actor TimeoutOnCallsSleeper {
    private let timeoutCalls: Set<Int>
    private var callCount = 0

    init(timeoutCalls: Set<Int>) {
        self.timeoutCalls = timeoutCalls
    }

    func sleep() async throws {
        callCount += 1
        if timeoutCalls.contains(callCount) { return }
        try await Task.sleep(nanoseconds: .max)
    }
}

func waitUntilAsync(
    _ what: String,
    timeout: Duration = .seconds(5),
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw WaitUntilTimeout(what: what) }
        try await Task.sleep(for: .milliseconds(10))
    }
}
