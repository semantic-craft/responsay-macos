import Foundation
import CryptoKit

// MARK: - 372 LegalCaptureCoordinator
//
// The legal "thick logic" lifted off QuickCaptureViewModel: routing-context
// assembly, scene classification, the privacy gate, run building and the
// runtime calls. It owns DECISIONS and returns values — it never touches the
// view model's @Observable state, so it is unit-testable without a VM. The VM's
// `+Legal` extension shrinks to "call coordinator → assign results to state".

@MainActor
public struct LegalCaptureCoordinator {
    private let runtime: LegalSkillRuntime?
    private let contextProvider: (@MainActor () -> ExpressionContext?)?
    private let profileProvider: (@MainActor () -> LegalPracticeProfile?)?
    private let enabledProvider: (@MainActor () -> Set<String>?)?
    private let gateProvider: (@MainActor () -> CaptureGateDecision)?
    private let runRecorder: (@MainActor (LegalSkillRun) -> Void)?
    private let privacyPolicy: LegalPrivacyPolicy

    public init(
        runtime: LegalSkillRuntime?,
        contextProvider: (@MainActor () -> ExpressionContext?)? = nil,
        profileProvider: (@MainActor () -> LegalPracticeProfile?)? = nil,
        enabledProvider: (@MainActor () -> Set<String>?)? = nil,
        gateProvider: (@MainActor () -> CaptureGateDecision)? = nil,
        runRecorder: (@MainActor (LegalSkillRun) -> Void)? = nil,
        privacyPolicy: LegalPrivacyPolicy = LegalPrivacyPolicy()
    ) {
        self.runtime = runtime
        self.contextProvider = contextProvider
        self.profileProvider = profileProvider
        self.enabledProvider = enabledProvider
        self.gateProvider = gateProvider
        self.runRecorder = runRecorder
        self.privacyPolicy = privacyPolicy
    }

    public var isConfigured: Bool { runtime != nil }

    /// Assemble the routing context from the host (via `contextProvider`), falling
    /// back to the captured `text` when the host reports no selection (AX-weak hosts).
    func routingContext(text: String) -> ExpressionContext {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var context = contextProvider?() ?? ExpressionContext(selectedText: trimmed.isEmpty ? nil : trimmed)
        if (context.selectedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !trimmed.isEmpty {
            context.selectedText = trimmed
        }
        if (context.textBeforeCursor ?? "").isEmpty, !trimmed.isEmpty {
            context.textBeforeCursor = trimmed
        }
        return context
    }

    /// Route the captured text to a legal palette outcome (cards + decision), or
    /// `nil` when no runtime is configured.
    public func route(text: String) -> LegalPaletteOutcome? {
        guard let runtime else { return nil }
        let context = routingContext(text: text)
        return runtime.route(
            context: context, now: Date(), browserURL: context.browserURL,
            profile: profileProvider?(), enabled: enabledProvider?())
    }

    public func evaluateScene(text: String) -> SceneStageClassification? {
        route(text: text)?.decision.classification
    }

    /// The host context for skill execution / privacy decisions, falling back to
    /// the captured transcript when the host reports no selection.
    func executionContext(transcript: String) -> ExpressionContext {
        contextProvider?() ?? ExpressionContext(selectedText: transcript)
    }

    /// Decide the model route + send-preview for the current context. The capture
    /// gate is consulted first (a security denial → `.blocked`).
    public func privacyDecision(transcript: String) -> LegalPrivacyDecision {
        let gate = gateProvider?() ?? .allowed
        let context = executionContext(transcript: transcript)
        let profile = profileProvider?()
        return privacyPolicy.decide(
            gate: gate,
            selectedText: context.selectedText ?? transcript,
            surroundingText: context.textBeforeCursor,
            appName: context.appName,
            privacyPreference: profile?.privacyPreference ?? .selectedTextOnly,
            modelPreference: profile?.modelPreference ?? .askEachTime)
    }

    /// Build a runnable card for one named skill (划词菜单 来源辅助检索 / 实务辅助 direct run).
    public func candidateCard(forSkillId id: String) -> LegalCandidateCard? {
        runtime?.candidateCard(forSkillId: id)
    }

    /// Run a chosen skill against the current host context.
    public func execute(card: LegalCandidateCard, context: ExpressionContext, route: ModelRoute) async throws -> LegalSkillResponse {
        guard let runtime else { throw LegalSkillRuntimeError.notConfigured }
        return try await runtime.execute(card: card, context: context, route: route)
    }

    /// Build + record a run-history entry (no-op when no recorder is wired).
    public func recordRun(card: LegalCandidateCard, context: ExpressionContext, route: ModelRoute, transcript: String) {
        guard let runRecorder else { return }
        let run = LegalSkillRun(
            id: UUID().uuidString, createdAt: Date(),
            contextHash: Self.legalInputHash(context.selectedText ?? transcript),
            scene: card.scene, stage: card.stage, skillId: card.skillId, modelRoute: route)
        runRecorder(run)
    }

    /// The effective search-verification permission for the response's route
    /// (disabled unless the route allows search AND the runtime supports it).
    public func searchPermission(route: ModelRoute?) -> SearchPrivacyGate.SearchPermission {
        guard let route,
              SearchPrivacyGate.permission(for: route).isSearchEnabled,
              runtime?.supportsSearchVerification(route: route) == true else {
            return .disabled
        }
        return SearchPrivacyGate.permission(for: route)
    }

    public func searchVerification(_ anchor: VerificationAnchor, route: ModelRoute?) async throws -> VerifiedSource? {
        guard let runtime, let route else { throw LegalSkillRuntimeError.notConfigured }
        return try await runtime.searchVerification(anchor, route: route)
    }

    /// 488 — 找类案 联网入口。Gated by the same search permission as anchor verification
    /// (route allows search AND provider supports it); secure-input/privacy already vetted
    /// at capture (#052).
    public func findSimilarCases(query: String, route: ModelRoute?, currentYear: Int) async throws -> [ScreenedCase] {
        guard let runtime, let route else { throw LegalSkillRuntimeError.notConfigured }
        return try await runtime.findSimilarCases(query: query, route: route, currentYear: currentYear)
    }

    static func legalInputHash(_ text: String) -> String {
        "sha256:" + SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
