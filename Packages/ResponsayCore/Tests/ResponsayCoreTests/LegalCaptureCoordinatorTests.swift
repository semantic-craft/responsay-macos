import Testing
import Foundation
@testable import ResponsayCore

// 372 — the legal "thick logic" (routing-context assembly, scene classification,
// privacy gate, run building) extracted off QuickCaptureViewModel into an
// independently-testable collaborator. These tests exercise the coordinator
// WITHOUT a view model, proving the decisions stand on their own.

// 296 (migrated down from QuickCaptureViewModelTests): AX-weak hosts report no
// selection, but the popup already captured the text — that text must drive scene
// routing, and the router's REAL confidence must come back (was hardcoded 1.0).
@Test @MainActor func coordinator_evaluateScene_usesPopupTextWhenAXSelectionEmpty() throws {
    let coordinator = LegalCaptureCoordinator(
        runtime: try LegalSkillRuntime.bundled(executor: nil),
        contextProvider: { ExpressionContext(selectedText: nil) })   // AX-weak host

    let scene = try #require(coordinator.evaluateScene(
        text: "起诉状\n一、事实与理由\n被告拖欠货款，构成违约，应承担违约责任。"))
    #expect(scene.scene != .unknown)   // popup text reached the router

    let vague = try #require(coordinator.evaluateScene(text: "随便写点什么"))
    #expect(vague.confidence < 1.0)    // real-confidence passthrough, not hardcoded 1.0
}

// The capture gate is law (ADR-0014): a SECURITY denial blocks the legal path
// entirely — no cloud send, no fields. The coordinator must route the gate +
// context through the privacy policy, not re-implement it.
@Test @MainActor func coordinator_privacyDecision_securityGate_noLongerBlocks() {
    // 2026-06-25 反转: 安全 gate 不再阻断;route 跟随用户偏好(默认 askEachTime → 发送前确认)。
    let coordinator = LegalCaptureCoordinator(
        runtime: nil,
        gateProvider: { .denied(.secureTextField) })

    let decision = coordinator.privacyDecision(transcript: "客户合同草稿")

    #expect(!decision.isBlocked)
    #expect(decision.route == .cloudRequiresUserConfirm)
}

// route() is what `processLegal` consumes: a configured runtime produces a
// palette outcome (the VM then renders its cards); an unconfigured one returns
// nil so the VM can surface "法律技能未配置".
@Test @MainActor func coordinator_route_producesOutcomeWhenConfigured_nilWhenNot() throws {
    let configured = LegalCaptureCoordinator(
        runtime: try LegalSkillRuntime.bundled(executor: nil),
        contextProvider: { ExpressionContext(selectedText: nil) })
    let outcome = configured.route(text: "起诉状\n一、事实与理由\n被告拖欠货款，构成违约。")
    #expect(outcome != nil)
    #expect(outcome?.decision.classification.scene != .unknown)

    let unconfigured = LegalCaptureCoordinator(runtime: nil)
    #expect(unconfigured.route(text: "起诉状") == nil)
}
