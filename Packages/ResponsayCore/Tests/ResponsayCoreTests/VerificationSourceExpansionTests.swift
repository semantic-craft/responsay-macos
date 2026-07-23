import Testing
import Foundation
@testable import ResponsayCore

// MARK: - VerificationSourcePreference expansion tests

@Suite("VerificationSourcePreference expansion — parity with FactCheckDeepLinkEngine")
struct VerificationSourceExpansionTests {

    // MARK: - New enum cases exist

    @Test func itslaw_caseExists() {
        let source = VerificationSourcePreference.itslaw
        #expect(source.rawValue == "itslaw")
    }

    @Test func wanfang_caseExists() {
        let source = VerificationSourcePreference.wanfang
        #expect(source.rawValue == "wanfang")
    }

    @Test func vip_caseExists() {
        let source = VerificationSourcePreference.vip
        #expect(source.rawValue == "vip")
    }

    @Test func rmfyalk_caseExists() {
        let source = VerificationSourcePreference.rmfyalk
        #expect(source.rawValue == "rmfyalk")
    }

    // MARK: - Router generates correct URLs

    @Test func router_itslaw_buildsSearchURL() throws {
        let anchor = VerificationAnchor(
            id: "test:1", label: "(2019)最高法民再59号", kind: .caseLaw,
            query: "(2019)最高法民再59号", preferredSources: [.itslaw])
        let route = VerificationQueryRouter().route(for: anchor)
        #expect(route.kind == .deepLink)
        let url = try #require(route.url)
        #expect(url.host?.contains("itslaw.com") == true)
        #expect(url.absoluteString.contains("searchWord="))
    }

    @Test func router_wanfang_buildsSearchURL() throws {
        let anchor = VerificationAnchor(
            id: "test:2", label: "王利明 侵权责任", kind: .scholarlyArticle,
            query: "王利明 侵权责任", preferredSources: [.wanfang])
        let route = VerificationQueryRouter().route(for: anchor)
        let url = try #require(route.url)
        #expect(url.host?.contains("wanfangdata") == true)
        #expect(url.absoluteString.contains("q="))
    }

    @Test func router_vip_buildsSearchURL() throws {
        let anchor = VerificationAnchor(
            id: "test:3", label: "张三 法学论文", kind: .scholarlyArticle,
            query: "张三 法学论文", preferredSources: [.vip])
        let route = VerificationQueryRouter().route(for: anchor)
        let url = try #require(route.url)
        #expect(url.host?.contains("cqvip.com") == true)
        #expect(url.absoluteString.contains("key="))
    }

    @Test func router_rmfyalk_routesViaBingSiteSearch() throws {
        // 人民法院案例库前端检索带不了词 → 必应 site: 落结果页。
        let anchor = VerificationAnchor(
            id: "test:4", label: "案例", kind: .caseLaw,
            query: "案例", preferredSources: [.rmfyalk])
        let route = VerificationQueryRouter().route(for: anchor)
        let url = try #require(route.url)
        #expect(url.host == "www.bing.com")
        #expect(url.query?.contains("site:rmfyalk.court.gov.cn") == true)
    }

    // MARK: - Default routing includes new sources

    @Test func caseLaw_defaultSource_includesItslawOrPkulaw() {
        let def = VerificationQueryRouter.defaultSource(for: .caseLaw)
        #expect(def == .pkulaw || def == .itslaw)
    }

    // MARK: - Existing sources still work

    @Test func baiduScholar_stillWorks() throws {
        let anchor = VerificationAnchor(
            id: "test:5", label: "测试", kind: .other,
            query: "测试", preferredSources: [.baiduScholar])
        let route = VerificationQueryRouter().route(for: anchor)
        let url = try #require(route.url)
        #expect(url.host?.contains("xueshu.baidu.com") == true)
    }

    @Test func cnki_stillWorks() throws {
        let anchor = VerificationAnchor(
            id: "test:6", label: "论文", kind: .scholarlyArticle,
            query: "论文", preferredSources: [.cnki])
        let route = VerificationQueryRouter().route(for: anchor)
        let url = try #require(route.url)
        #expect(url.host?.contains("cnki.net") == true)
    }
}
