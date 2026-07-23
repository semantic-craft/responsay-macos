import Testing
import Foundation
@testable import ResponsayCore

/// 114 — AppContextProfiler.
struct AppContextProfilerTests {
    private let profiler = AppContextProfiler()

    @Test func word_isWordProcessor_withLitigationPriors() {
        let profile = profiler.profile(ExpressionContext(bundleIdentifier: "com.microsoft.Word"))
        #expect(profile.appCategory == .wordProcessor)
        let scenes = Set(profile.legalScenePriors.map(\.scene))
        #expect(scenes.contains(.litigation))
        #expect(scenes.contains(.academicWriting))
        #expect(scenes.contains(.contract))
    }

    @Test func feishu_isCollaboration_withPrivacyPriors() {
        let profile = profiler.profile(ExpressionContext(bundleIdentifier: "com.bytedance.feishu"))
        #expect(profile.appCategory == .collaboration)
        let scenes = Set(profile.legalScenePriors.map(\.scene))
        #expect(scenes.contains(.privacy))
        #expect(scenes.contains(.productCompliance))
    }

    @Test func unknownBundle_isUnknown_noPriors() {
        let profile = profiler.profile(ExpressionContext(bundleIdentifier: "com.example.mysteryapp"))
        #expect(profile.appCategory == .unknown)
        #expect(profile.legalScenePriors.isEmpty)
    }
}

/// 115 — BrowserURLClassifier.
struct BrowserURLClassifierTests {
    private let classifier = BrowserURLClassifier()

    @Test func officialLaw_govHint() {
        let signal = classifier.classify("https://flk.npc.gov.cn/detail?id=42")
        #expect(signal.category == .officialLawDatabase)
        #expect(signal.verificationSourceHint == .govLaw)
        #expect(signal.legalSceneBoosts.contains { $0.scene == .litigation })
    }

    @Test func cnki_andBaiduScholar_academic() {
        #expect(classifier.classify("https://www.cnki.net/index").verificationSourceHint == .cnki)
        let baidu = classifier.classify("https://xueshu.baidu.com/s?wd=privacy")
        #expect(baidu.category == .academicDatabase)
        #expect(baidu.verificationSourceHint == .baiduScholar)
    }

    @Test func unknownHost_noBoost() {
        let signal = classifier.classify("https://example.com/page")
        #expect(signal.category == .unknown)
        #expect(signal.legalSceneBoosts.isEmpty)
        #expect(signal.verificationSourceHint == nil)
    }

    @Test func queryIsStripped_privacy() {
        let signal = classifier.classify("https://flk.npc.gov.cn/path?token=SECRET123")
        #expect(signal.host == "flk.npc.gov.cn")
        #expect(signal.host?.contains("SECRET") == false)
    }
}

/// 116 — HeadingDetector.
struct HeadingDetectorTests {
    private let detector = HeadingDetector()

    @Test func factsAndReasons_briefDrafting() {
        let signals = detector.detect(
            textBeforeCursor: "一、事实与理由\n被告于2025年违约，应承担责任", windowTitle: nil)
        #expect(signals.first?.stageHint == .briefDrafting)
        #expect((signals.first?.confidenceBoost ?? 0) > 0)
    }

    @Test func references_citationDrafting() {
        let signals = detector.detect(textBeforeCursor: "参考文献\n[1] 张三", windowTitle: nil)
        #expect(signals.first?.stageHint == .citationDrafting)
    }

    @Test func evidenceList_evidenceReview() {
        let signals = detector.detect(textBeforeCursor: "证据目录\n证据一：合同", windowTitle: nil)
        #expect(signals.first?.stageHint == .evidenceReview)
    }

    @Test func noCue_noSignal() {
        #expect(detector.detect(textBeforeCursor: "随便写点什么普通文字", windowTitle: nil).isEmpty)
    }
}

/// 117 — ContextConfidenceScorer.
struct ContextConfidenceScorerTests {
    private let scorer = ContextConfidenceScorer()

    @Test func anchorA_litigationBriefDrafting_highConfidence() {
        let profiler = AppContextProfiler()
        let appProfile = profiler.profile(ExpressionContext(bundleIdentifier: "com.microsoft.Word"))
        let heading = HeadingDetector().detect(textBeforeCursor: "事实与理由\n被告违约", windowTitle: nil)
        let url = BrowserURLClassifier().classify("https://flk.npc.gov.cn/x")
        let result = scorer.classify(appProfile: appProfile, headingSignals: heading,
                                     urlSignal: url, hasSelection: true)
        #expect(result.scene == .litigation)
        #expect(result.stage == .briefDrafting)
        #expect(result.confidence >= 0.75)
        #expect(result.shouldAskUser == false)
    }

    @Test func anchorB_ambiguous_asksUser() {
        let appProfile = AppContextProfiler().profile(ExpressionContext(bundleIdentifier: "com.bytedance.feishu"))
        let result = scorer.classify(appProfile: appProfile, headingSignals: [],
                                     urlSignal: nil, hasSelection: true)
        #expect(result.confidence < ContextConfidenceScorer.askThreshold)
        #expect(result.shouldAskUser)
    }

    @Test func emptySelection_manualDowngrade_noModel() {
        let result = scorer.classify(appProfile: .unknown, headingSignals: [],
                                     urlSignal: nil, hasSelection: false)
        #expect(result.scene == .unknown)
        #expect(result.shouldAskUser)
        #expect(result.confidence == 0)
    }
}

/// 113 — ContextSignalLayer assembly + Codable round-trip.
struct ContextSignalLayerTests {
    private let layer = ContextSignalLayer()
    private let now = Date(timeIntervalSinceReferenceDate: 700_000)

    @Test func assemblesBundle_fromFixtureContext() {
        let context = ExpressionContext(
            appName: "Microsoft Word", bundleIdentifier: "com.microsoft.Word",
            windowTitle: "起诉状.docx", selectedText: "被告应承担违约责任",
            textBeforeCursor: "事实与理由\n")
        let bundle = layer.assemble(context: context, browserURL: nil, now: now)
        #expect(bundle.appProfile.appCategory == .wordProcessor)
        #expect(bundle.headingSignals.contains { $0.stageHint == .briefDrafting })
        #expect(bundle.hasSelection)

        let classification = layer.classify(bundle)
        #expect(classification.scene == .litigation)
    }

    @Test func bundle_roundTripsCodable() throws {
        let context = ExpressionContext(bundleIdentifier: "com.bytedance.feishu", selectedText: "x")
        let bundle = layer.assemble(
            context: context, browserURL: "https://cnki.net/a",
            verificationTargets: [VerificationTarget(id: "v", label: "《民法典》第577条", kind: .statute)],
            now: now)
        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(ContextSignalBundle.self, from: data)
        #expect(decoded == bundle)
    }
}
