import Testing
@testable import ResponsayCore

@Suite struct RegisterTierClassifierTests {
    private let classifier = RegisterTierClassifier()

    @Test func chatAppsClassifyAsChat() {
        #expect(classifier.tier(bundleID: "com.tencent.xinWeChat") == .chat)   // 微信
        #expect(classifier.tier(bundleID: "com.tencent.WeWorkMac") == .chat)   // 企业微信
        #expect(classifier.tier(bundleID: "com.alibaba.DingTalkMac") == .chat) // 钉钉
        #expect(classifier.tier(bundleID: "com.tinyspeck.slackmacgap") == .chat)
    }

    @Test func mailAppsClassifyAsMail() {
        #expect(classifier.tier(bundleID: "com.apple.mail") == .mail)
        #expect(classifier.tier(bundleID: "com.microsoft.Outlook") == .mail)
        #expect(classifier.tier(bundleID: "com.tencent.foxmail") == .mail)
    }

    @Test func documentAppsClassifyAsDocument() {
        #expect(classifier.tier(bundleID: "com.microsoft.Word") == .document)
        #expect(classifier.tier(bundleID: "com.apple.iWork.Pages") == .document)
        #expect(classifier.tier(bundleID: "notion.id") == .document)
        #expect(classifier.tier(bundleID: "com.kingsoft.wpsoffice.mac") == .document)
    }

    @Test func configuredLegalSeedClassifiesAsLegal() {
        let withSeed = RegisterTierClassifier(legalSeeds: ["com.example.caseflow"])
        #expect(withSeed.tier(bundleID: "com.example.caseFlow") == .legal)
        // Default has no legal seeds → the same app is neutral, not legal.
        #expect(classifier.tier(bundleID: "com.example.caseflow") == .neutral)
    }

    @Test func unknownOrMissingAppIsNeutral() {
        #expect(classifier.tier(bundleID: "com.unknown.app") == .neutral)
        #expect(classifier.tier(bundleID: nil) == .neutral)
        #expect(classifier.tier(bundleID: nil, appName: nil) == .neutral)
    }

    @Test func appNameFallbackWhenBundleMisses() {
        // Some capture paths only have the app name (no bundleId) — still classify.
        #expect(classifier.tier(bundleID: nil, appName: "WeChat") == .chat)
        #expect(classifier.tier(bundleID: nil, appName: "Microsoft Outlook") == .mail)
    }

    // MARK: - 463 browser-domain classification

    @Test func webMailDomainClassifiesAsMail() {
        // A browser (generic bundleID) on a mail web-app → the domain decides the register.
        #expect(classifier.tier(bundleID: "com.google.Chrome", domain: "mail.google.com") == .mail)
    }

    @Test func webDomainsClassifyDocChatLegal() {
        #expect(classifier.tier(bundleID: "com.google.Chrome", domain: "docs.google.com") == .document)
        #expect(classifier.tier(bundleID: "com.apple.Safari", domain: "web.whatsapp.com") == .chat)
        #expect(classifier.tier(bundleID: "com.google.Chrome", domain: "wenshu.court.gov.cn") == .legal)
    }

    @Test func fullURLHasItsHostExtracted() {
        #expect(classifier.tier(bundleID: "com.google.Chrome",
                                domain: "https://mail.google.com/mail/u/0/#inbox") == .mail)
    }

    @Test func domainBeatsGenericBrowserAndUnknownFallsThrough() {
        // Chrome bundleID is neutral on its own → domain is what classifies.
        #expect(classifier.tier(bundleID: "com.google.Chrome") == .neutral)
        // Unknown site → domain misses → fall back to (neutral) browser bundleID, never a wrong tier.
        #expect(classifier.tier(bundleID: "com.google.Chrome", domain: "https://example.com/x") == .neutral)
    }

    @Test func nilDomainKeepsAppBasedBehavior() {
        // 463 is additive: no domain → the existing app-based classification is unchanged.
        #expect(classifier.tier(bundleID: "com.tencent.xinWeChat", domain: nil) == .chat)
        #expect(classifier.tier(bundleID: "com.apple.mail") == .mail)
    }

    @Test func everyRealTierHasGuidanceAndNeutralIsEmpty() {
        for tier in RegisterTier.allCases {
            if tier == .neutral {
                // 462 appends nothing for an empty guidance → byte-identical to today (zero regression).
                #expect(tier.guidance.isEmpty)
            } else {
                #expect(!tier.guidance.isEmpty)
            }
        }
    }
}
