import Foundation

public protocol IntentPlanCompiler: Sendable {
    func compile(_ input: IntentCompilerInput) async throws -> Data
}
