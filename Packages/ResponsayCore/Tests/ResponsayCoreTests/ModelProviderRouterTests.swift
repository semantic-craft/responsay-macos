import Testing
@testable import ResponsayCore

/// 106 / v0.2 §14 — ModelProviderRouter: purpose × privacy → ModelRoute.
struct ModelProviderRouterTests {
    private let router = ModelProviderRouter()

    @Test func localSensitiveAlwaysForcesLocal() {
        #expect(router.route(purpose: .localSensitive, baseRoute: .cloudAllowed) == .localOnly)
        #expect(router.route(purpose: .localSensitive, baseRoute: .cloudRequiresUserConfirm) == .localOnly)
    }

    @Test func localOnlyBaseIsNeverUpgraded() {
        // The privacy floor (110) holds for every purpose — no escalation to cloud.
        for purpose in ModelPurpose.allCases {
            #expect(router.route(purpose: purpose, baseRoute: .localOnly) == .localOnly)
        }
    }

    @Test func blockedStaysBlocked() {
        #expect(router.route(purpose: .legalSkill, baseRoute: .blocked) == .blocked)
    }

    @Test func cloudPurposesHonorTheBaseRoute() {
        #expect(router.route(purpose: .legalSkill, baseRoute: .cloudAllowed) == .cloudAllowed)
        #expect(router.route(purpose: .fastPolish, baseRoute: .cloudRequiresUserConfirm) == .cloudRequiresUserConfirm)
    }

    @Test func allowsCloudReflectsRoute() {
        #expect(router.allowsCloud(.cloudAllowed) == true)
        #expect(router.allowsCloud(.localOnly) == false)
        #expect(router.allowsCloud(.blocked) == false)
    }
}
