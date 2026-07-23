import Foundation

/// A compiler-side failure that already knows how it should surface to the user. A compiler
/// (or a test) throws this when it can classify the fault more precisely than the pipeline's
/// generic transport mapping — e.g. a capability probe that found the model can't emit the
/// structured plan, or a detected request timeout. The pipeline maps `reason` straight through.
///
/// It carries only the category, never a provider message or request content (spec decision 29;
/// #559 "不泄漏敏感请求内容").
public struct IntentCompilerFailure: Error, Sendable, Equatable {
    public let reason: IntentUnavailableReason

    public init(_ reason: IntentUnavailableReason) {
        self.reason = reason
    }
}
