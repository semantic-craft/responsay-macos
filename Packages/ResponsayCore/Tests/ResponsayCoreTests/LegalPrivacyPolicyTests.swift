import Testing
@testable import ResponsayCore

/// 110 — LegalPrivacyPolicy: route 只跟随用户的 modelPreference;联网与否由用户决定,
/// 不再因 安全输入 / 敏感词 / 敏感应用 / surrounding 自动阻断或降级(2026-06-25 用户反转)。
struct LegalPrivacyPolicyTests {
    private let policy = LegalPrivacyPolicy()
    private let provider = ModelProviderRouter()

    // MARK: - 用户决定:安全/敏感不再改变路由

    @Test func secureField_doesNotBlock_routeFollowsPreference() {
        // 安全输入框不再阻断法律路径:route 仍按用户偏好(默认 askEachTime → 发送前确认)。
        let d = policy.decide(gate: .denied(.secureTextField), selectedText: "任意文本")
        #expect(d.route == .cloudRequiresUserConfirm)
        #expect(!d.isBlocked)
        #expect(d.sendFields == [.selectedText, .sceneTag, .appCategory])
    }

    @Test func anyDenial_neverBlocks() {
        // 无论 security 还是 compatibility 拒绝,都不再阻断隐私路由。
        for gate: CaptureGateDecision in [
            .denied(.secureTextField),
            .denied(.sensitiveApp(bundleID: "com.agilebits.onepassword")),
            .denied(.incompatibleApp(bundleID: "com.microsoft.Excel")),
        ] {
            let d = policy.decide(gate: gate, selectedText: "普通文本", modelPreference: .cloudFirst)
            #expect(d.route == .cloudAllowed)
        }
    }

    @Test func sensitiveTerm_cloudFirst_stillGoesCloud() {
        // 敏感词不再把 cloudFirst 降级为"需确认"——联网与否用户自己定。
        let d = policy.decide(gate: .allowed, selectedText: "涉及客户保密信息", modelPreference: .cloudFirst)
        #expect(d.route == .cloudAllowed)
    }

    @Test func sensitiveApp_feishu_cloudFirst_stillGoesCloud() {
        let d = policy.decide(gate: .allowed, selectedText: "上线评审材料", appName: "Feishu", modelPreference: .cloudFirst)
        #expect(d.route == .cloudAllowed)
    }

    @Test func surroundingText_doesNotChangeRoute_andIsNeverSent() {
        let d = policy.decide(
            gate: .allowed, selectedText: "见附件", surroundingText: "客户保密资料清单",
            modelPreference: .cloudFirst)
        #expect(d.route == .cloudAllowed)                          // surrounding 不再触发降级
        #expect(d.sendFields == [.selectedText, .sceneTag, .appCategory])   // surrounding 仍不入字段
    }

    @Test func nonSensitive_cloudFirst_allowsCloud() {
        let d = policy.decide(gate: .allowed, selectedText: "这段话需要改写一下", modelPreference: .cloudFirst)
        #expect(d.route == .cloudAllowed)
    }

    @Test func localFirst_alwaysLocal() {
        let d = policy.decide(gate: .allowed, selectedText: "普通文本", modelPreference: .localFirst)
        #expect(d.route == .localOnly)
    }

    @Test func askEachTime_alwaysConfirms() {
        let d = policy.decide(gate: .allowed, selectedText: "普通文本", modelPreference: .askEachTime)
        #expect(d.route == .cloudRequiresUserConfirm)
    }

    // MARK: - AC3: send-preview = minimal default fields

    @Test func sendPreview_defaultsToMinimalFields() {
        let d = policy.decide(gate: .allowed, selectedText: "x", privacyPreference: .selectedTextOnly)
        #expect(d.sendFields.contains(.selectedText))
        #expect(d.sendFields.contains(.sceneTag))
        #expect(d.sendFields.contains(.windowTitleHash) == false)   // withheld by default
        #expect(d.sendFields.contains(.nearbyHeading) == false)
    }

    @Test func relaxedScope_addsNearbyHeadingOnly() {
        let d = policy.decide(gate: .allowed, selectedText: "x", privacyPreference: .allowLocalHeading)
        #expect(d.sendFields.contains(.nearbyHeading))
        #expect(d.sendFields.contains(.windowTitleHash) == false)
    }

    // MARK: - v0.2 §14: privacy axis composes with the purpose router

    @Test func composesWithProviderRouter_localNeverUpgraded() {
        let d = policy.decide(gate: .allowed, selectedText: "x", modelPreference: .localFirst)
        let effective = provider.route(purpose: .legalSkill, baseRoute: d.route)
        #expect(effective == .localOnly)
        #expect(provider.allowsCloud(effective) == false)
    }
}
