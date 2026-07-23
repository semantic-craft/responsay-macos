import Foundation

// MARK: - CNKI 专业检索式构造器（移植自 opencli-stack academic-search 的 buildCnkiProfessionalExpr）
//
// 知网「专业检索」是输入法生成、用户粘贴进 kns.cnki.net/kns8s/AdvSearch 文本框的检索式
// （无 GET 参数）。语法以中山大学《知网使用手册》为权威、以 opencli cnki 适配器（已对真实
// CNKI 验证）为实现基准：
//   · 字段码：SU 主题 / TI 题名 / AU 作者 / AB 摘要 / KY 关键词 / LY 文献来源(期刊)
//   · 匹配算符（按字段）：SU → %=（相关匹配，官方推荐）；TI/AB → %（包含）；其余 → =（相等）
//   · 同字段多词用「 * 」(逻辑与) 组合；字段间用 AND/OR/NOT（前后空格）
//   · 检索词用英文单引号括起；词内单引号 ' 转义为 ''（避免撕裂引号配对）
public enum CNKIExpertQueryBuilder {

    /// 知网专业检索页（只能打开后把检索式粘进文本框，URL 不带检索参数）。
    public static let professionalSearchURL = URL(string: "https://kns.cnki.net/kns8s/AdvSearch")!

    /// Decomposed inputs for a citation/topic. Bare topic → SU; a scholarly citation can
    /// pass author/journal so they route to AU/LY instead of being dumped into SU.
    public struct Input: Sendable, Equatable {
        public var query: String
        public var author: String?
        public var journal: String?      // 多个期刊用 '+' 分隔
        public var field: String         // SU / TI / AU / AB / KY / DOI（默认 SU）

        public init(query: String, author: String? = nil, journal: String? = nil, field: String = "SU") {
            self.query = query
            self.author = author
            self.journal = journal
            self.field = field
        }
    }

    /// Build a professional-search expression. Bare-query convenience.
    public static func build(query: String) -> String { build(Input(query: query)) }

    public static func build(_ input: Input) -> String {
        let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "" }

        var parts = [fieldExpr(field: normalizeField(input.field), query: query)]

        if let author = input.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            parts.append("AU = '\(escape(author))'")
        }

        if let journal = input.journal?.trimmingCharacters(in: .whitespacesAndNewlines), !journal.isEmpty {
            let journals = journal.split(separator: "+").map { escape(String($0)) }.filter { !$0.isEmpty }
            if journals.count == 1 {
                parts.append("LY = '\(journals[0])'")
            } else if journals.count > 1 {
                parts.append("(" + journals.map { "LY = '\($0)'" }.joined(separator: " OR ") + ")")
            }
        }

        return parts.joined(separator: " AND ")
    }

    // MARK: - Internals

    /// CNKI 专业检索用 '' 表示词内单引号（SQL 式转义），保住外层 '...' 引号配对。
    static func escape(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "'", with: "''")
    }

    /// 单字段检索式。SU→%=；TI/AB→%；其余→=。多词用「 * 」组合。
    static func fieldExpr(field: String, query: String) -> String {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let escaped = escape(value)
        let terms = value.split(whereSeparator: { $0.isWhitespace })
            .map { escape(String($0)) }
            .filter { !$0.isEmpty }

        let op: String
        switch field {
        case "SU":        op = "%="
        case "TI", "AB":  op = "%"
        default:          op = "="
        }

        guard ["SU", "TI", "AB"].contains(field), terms.count > 1 else {
            return "\(field) \(op) '\(escaped)'"
        }
        return "\(field) \(op) " + terms.map { "'\($0)'" }.joined(separator: " * ")
    }

    private static let knownFields: Set<String> = ["SU", "TI", "AU", "AB", "KY", "DOI"]

    static func normalizeField(_ type: String) -> String {
        let key = type.trimmingCharacters(in: .whitespaces).uppercased()
        return knownFields.contains(key) ? key : "SU"
    }
}
