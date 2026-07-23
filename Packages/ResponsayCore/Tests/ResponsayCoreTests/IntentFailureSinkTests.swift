import Foundation
import Testing
@testable import ResponsayCore

/// #574 — the pipeline's content-free failure categories: enum names only, emitted at every
/// safe-unavailable exit so Release logs can finally name the sub-reason behind a blocked card.
private struct StubCompiler: IntentPlanCompiler {
    let result: Result<Data, any Error>
    func compile(_ input: IntentCompilerInput) async throws -> Data {
        try result.get()
    }
}

private func run(_ compiler: StubCompiler?) async -> [String] {
    final class Box: @unchecked Sendable { var values = [String]() }
    let box = Box()
    _ = await IntentCompilationPipeline(
        compiler: compiler,
        failureSink: { box.values.append($0) }
    ).compile(
        finalTranscript: "给同事写一句话",
        locale: .chinese,
        allowedContext: nil,
        routePolicy: compiler == nil ? .unavailable : .injectedCompiler)
    return box.values
}

@Test func failureSink_badJSONReportsDecodeCategory() async {
    let categories = await run(StubCompiler(result: .success(Data("not json".utf8))))
    #expect(categories == ["decode-dataCorrupted"])
}

@Test func failureSink_verifierRejectionReportsVerifyCase() async {
    // Structurally valid JSON but empty units → coverage mismatch with the real source units.
    let plan = #"{"version":1,"decision":"render","units":[],"supersessions":[],"entities":[]}"#
    let categories = await run(StubCompiler(result: .success(Data(plan.utf8))))
    #expect(categories == ["verify-invalidCoverage"])
}

@Test func failureSink_preclassifiedCompilerErrorReportsReason() async {
    let categories = await run(StubCompiler(
        result: .failure(IntentCompilerFailure(.capabilityUnsupported))))
    #expect(categories == ["compiler-capabilityUnsupported"])
}

@Test func failureSink_unavailableRouteReportsCompilerUnavailable() async {
    let categories = await run(nil)
    #expect(categories == ["compilerUnavailable"])
}
