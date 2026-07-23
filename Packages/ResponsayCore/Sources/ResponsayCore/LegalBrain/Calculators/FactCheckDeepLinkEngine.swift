import Foundation

/// Defines the outcome of a Deep Link verification generation.
public struct FactCheckDeepLinkResult: Equatable, Sendable {
    public let originalText: String
    public let markdownLink: String
    public let type: LegalCalculatorPayloads.VerificationFactCheckPayload.TargetType
}

/// Engine responsible for transforming a Fact Check Payload into a series of actionable Deep Links.
/// This perfectly implements "Option A": relying on the LLM's high-dimensional extraction to bypass proprietary APIs,
/// and directly routing the user to public databases (like PKULaw or Wenshu) for verification.
public final class FactCheckDeepLinkEngine: Sendable {
    
    public init() {}

    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#;,")
        return set
    }()

    private func encodeQuery(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) ?? ""
    }

    /// Processes the payload extracted by the LLM and generates Deep Links.
    /// - Parameter payload: The extracted targets from the selected text.
    /// - Returns: A formatted Markdown report containing the deep links.
    public func generateDeepLinksReport(from payload: LegalCalculatorPayloads.VerificationFactCheckPayload) -> String {
        let results = generateDeepLinks(from: payload)
        guard !results.isEmpty else {
            return "✅ 未在所选文本中检测到需要核查的法条或案号。"
        }
        
        var report = "### 🔍 来源核验 (Fact Check)\n\n"
        report += "已为您提取文本中的法律引用，请点击以下链接前往权威数据库核实：\n\n"
        
        for (index, result) in results.enumerated() {
            let icon = switch result.type {
            case .law: "⚖️"
            case .caseLaw: "🏛️"
            case .paper: "📄"
            }
            report += "\(index + 1). \(icon) **原文**: \"\(result.originalText)\"\n"
            report += "   👉 **核查链接**: \(result.markdownLink)\n\n"
        }
        
        report += "> *注：此核查链接由 AI 根据您的文本自动生成，点击直达公开检索系统进行真实性复核。*"
        
        return report
    }
    
    /// Generates individual DeepLink results.
    public func generateDeepLinks(from payload: LegalCalculatorPayloads.VerificationFactCheckPayload) -> [FactCheckDeepLinkResult] {
        var results: [FactCheckDeepLinkResult] = []
        
        for target in payload.targets {
            let link = buildDeepLink(for: target)
            results.append(FactCheckDeepLinkResult(
                originalText: target.originalText,
                markdownLink: link,
                type: target.type
            ))
        }
        
        return results
    }
    
    private func buildDeepLink(for target: LegalCalculatorPayloads.VerificationFactCheckPayload.VerificationTarget) -> String {
        switch target.type {
        case .law:
            // For laws, provide a combination of PKULaw and official government databases.
            let query = target.keywords ?? target.semanticText ?? ""
            guard !query.isEmpty else { return "[缺少检索词]" }
            
            let encodedQuery = encodeQuery(query)
            let pkulaw = "https://www.pkulaw.com/search/CLI.1?match=Exact&keyword=\(encodedQuery)"
            let npc = "https://flk.npc.gov.cn/"
            let moj = "https://xzfg.moj.gov.cn/"
            
            return "[北大法宝](\(pkulaw)) | [国家法律法规数据库 (人大)](\(npc)) | [国家行政法规库 (司法部)](\(moj))"
            
        case .caseLaw:
            // For cases, rely on platforms that allow URL query parameters and use the user's browser login state.
            let query = target.keywords ?? target.semanticText ?? ""
            guard !query.isEmpty else { return "[缺少检索词]" }
            
            let encodedQuery = encodeQuery(query)
            
            // 无讼案例 (ItsLaw) - highly robust URL routing, relies on browser login
            let itsLawURL = "https://www.itslaw.com/search?searchMode=judgements&searchWord=\(encodedQuery)"
            // 人民法院案例库 (Supreme Court Official) - Link to portal
            let rmfyalkURL = "https://rmfyalk.court.gov.cn/"
            
            if target.keywords != nil {
                // Exact case number
                let exactSearch = "\"\(query)\" (site:wenshu.court.gov.cn OR site:pkulaw.com)"
                let bingEncoded = encodeQuery(exactSearch)
                let bingURL = "https://www.bing.com/search?q=\(bingEncoded)"
                return "[无讼案例直达](\(itsLawURL)) | [人民法院案例库](\(rmfyalkURL)) | [Bing搜案号](\(bingURL))"
            } else {
                // Semantic long text
                let bingURL = "https://www.bing.com/search?q=\(encodedQuery)"
                return "[无讼检索案情](\(itsLawURL)) | [人民法院案例库](\(rmfyalkURL)) | [Bing搜案情](\(bingURL))"
            }
        case .paper:
            let query = target.keywords ?? target.semanticText ?? ""
            guard !query.isEmpty else { return "[缺少检索词]" }
            let encodedQuery = encodeQuery(query)
            
            let wanfangURL = "https://s.wanfangdata.com.cn/paper?q=\(encodedQuery)"
            let vipURL = "https://qikan.cqvip.com/Qikan/Search/Index?key=\(encodedQuery)"
            let baiduURL = "https://xueshu.baidu.com/s?wd=\(encodedQuery)"
            
            return "[万方直达](\(wanfangURL)) | [维普直达](\(vipURL)) | [百度学术](\(baiduURL))"
        }
    }
}
