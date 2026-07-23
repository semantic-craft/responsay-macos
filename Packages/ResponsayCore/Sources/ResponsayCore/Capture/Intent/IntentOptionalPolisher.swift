import Foundation

/// The optional second-stage Polished renderer (#564, spec decision 10). It receives ONLY the
/// verified sanitized draft — never the raw transcript, side notes, superseded content or
/// grounding evidence, which are structurally out of reach by the time this runs. The caller
/// bakes register/style hints into the closure; the pipeline runs `IntentPostPolishGuard` on
/// whatever comes back and falls back to the sanitized draft on any failure.
public struct IntentOptionalPolisher: Sendable {
    let polish: @Sendable (_ sanitizedDraft: String) async throws -> String

    public init(polish: @escaping @Sendable (_ sanitizedDraft: String) async throws -> String) {
        self.polish = polish
    }
}
