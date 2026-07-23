// 并行全量 swift test 下 MainActor 被其它套件争用,固定 sleep 不保证 VM 的消费 Task
// 已被调度过;改为轮询条件,每次轮询挂起让出 MainActor 给消费 Task 调度窗口。
@MainActor
func waitUntil(
    _ what: String,
    timeout: Duration = .seconds(5),
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else { throw WaitUntilTimeout(what: what) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

struct WaitUntilTimeout: Error, CustomStringConvertible {
    let what: String
    var description: String { "waitUntil 超时:\(what)" }
}
