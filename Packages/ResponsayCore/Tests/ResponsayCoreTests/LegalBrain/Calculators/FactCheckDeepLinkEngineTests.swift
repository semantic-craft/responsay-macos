import Testing
import Foundation
@testable import ResponsayCore

@Suite("Fact Check Deep Link Engine Tests")
struct FactCheckDeepLinkEngineTests {
    
    let engine = FactCheckDeepLinkEngine()
    
    @Test("Test Law Exact Match Deep Link Generation")
    func testLawDeepLink() {
        let target = LegalCalculatorPayloads.VerificationFactCheckPayload.VerificationTarget(
            type: .law,
            keywords: "民法典 第一千零二十四条",
            semanticText: nil,
            originalText: "根据《民法典》第一千零二十四条的规定，名誉权受到侵害。"
        )
        let payload = LegalCalculatorPayloads.VerificationFactCheckPayload(targets: [target])
        
        let results = engine.generateDeepLinks(from: payload)
        #expect(results.count == 1)
        
        let result = results[0]
        #expect(result.type == .law)
        #expect(result.markdownLink.contains("pkulaw.com"))
        #expect(result.markdownLink.contains("%E6%B0%91%E6%B3%95%E5%85%B8%20%E7%AC%AC%E4%B8%80%E5%8D%83%E9%9B%B6%E4%BA%8C%E5%8D%81%E5%9B%9B%E6%9D%A1"))
    }
    
    @Test("Test Case Exact Match Deep Link Generation")
    func testCaseExactDeepLink() {
        let target = LegalCalculatorPayloads.VerificationFactCheckPayload.VerificationTarget(
            type: .caseLaw,
            keywords: "(2021)最高法民再1号",
            semanticText: nil,
            originalText: "参照(2021)最高法民再1号的裁判精神"
        )
        let payload = LegalCalculatorPayloads.VerificationFactCheckPayload(targets: [target])
        
        let results = engine.generateDeepLinks(from: payload)
        #expect(results.count == 1)
        
        let result = results[0]
        #expect(result.type == .caseLaw)
        #expect(result.markdownLink.contains("bing.com"))
        #expect(result.markdownLink.contains("site:wenshu.court.gov.cn"))
    }
    
    @Test("Test Empty Payload")
    func testEmptyPayload() {
        let payload = LegalCalculatorPayloads.VerificationFactCheckPayload(targets: [])
        let report = engine.generateDeepLinksReport(from: payload)
        #expect(report.contains("未在所选文本中检测到需要核查的法条或案号"))
    }
}
