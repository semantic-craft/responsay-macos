import Foundation

/// 474 — 案号交叉验证（PRD S2）。对一个完整案号做引号精确搜（必应 + 新闻源），看是否 ≥1 个独立来源
/// （按域名去重）命中同一案件 → 验证通过 / 待核实。网络执行在 macOS 运行层；这里只产检索式 + 判定逻辑。
public enum CaseNumberCrossCheckResult: Sendable, Equatable {
    case verified   // ≥1 独立来源命中
    case pending    // 待核实（无命中 / 无法验证）→ 律师二审
}

public enum CaseNumberCrossCheck {
    /// 新闻源只用于"确认案号存在"，不作正文来源。
    private static let newsAnchors = ["news.qq.com", "cdsb.com.cn"]

    /// 引号精确检索式：裸引号 + 各新闻源限定 + 「判决」补充。
    public static func queries(for caseNumber: String) -> [String] {
        let quoted = "\"\(caseNumber)\""
        return [quoted, "\(quoted) 判决"] + newsAnchors.map { "\(quoted) \($0)" }
    }

    /// 命中 URL 列表 → 独立来源数（按 host 去重）。
    public static func independentSources(matchedURLs: [String]) -> Int {
        let hosts = matchedURLs.compactMap { URL(string: $0)?.host?.lowercased() }
        return Set(hosts).count
    }

    /// ≥ 阈值（默认 1）个独立来源 → 验证通过，否则待核实。
    public static func classify(independentSources count: Int, minimum: Int = 1) -> CaseNumberCrossCheckResult {
        count >= minimum ? .verified : .pending
    }
}
