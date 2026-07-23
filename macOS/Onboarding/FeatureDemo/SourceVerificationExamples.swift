import Foundation

// MARK: - 来源真伪查询 · 真实示例（深圳大学法学院）
//
// 新手引导「看演示」里两段法律 AI 演示（来源核验 / 搜索引擎兜底）共用的真实素材。
// 全部经联网核实（来源 URL 见各条注释），并由 SourceVerificationExamplesTests 断言：
// 每条引用经 SearchStrategyGenerator 真实产出的检索源/深链，正是演示所展示的那样
// —— 以此保证「实际跑的效果 = 演示」。
//
// 两类教学点：
//   · 学术库查得到（正例）：院长熊伟、副院长宋旭光的 CLSCI 论文 → 知网 / 百度学术命中。
//   · 学术库查不到（兜底）：助理教授张贤伟新出的译著 → 知网/百度学术尚未收录 →
//     搜索引擎兜底，直达出版社 / 书目页核实真伪。

/// 一条可核验的引用示例。`query` = 抽取后送检的检索词（作者 + 标题），
/// 与 `verification.fact_check` 技能 rule D（文献/专著）的产物一致。
struct SourceVerificationExample: Sendable, Equatable {
    let citation: String            // 演示里被选中/展示的引用原文
    let query: String               // 送检检索词（作者 + 标题）
    let kindLabel: String           // [待核] 旁的分类标签：论文 / 专著 / 译著
    let findableInScholarDB: Bool   // true = 学术库可查（正例）；false = 兜底
}

enum SourceVerificationExamples {
    // MARK: 正例 —— 知网 / 百度学术可查

    /// 熊伟（深大法学院院长）·《国家创新体系中财税法的功能适配与规则优化》，
    /// 《现代法学》2025 年第 3 期（第 47 卷第 3 期），第 100–114 页。
    /// 核实：西南政法《现代法学》官网 PDF qks.swupl.edu.cn（2025-05；文章编号 1001-2397(2025)03-0100-15；
    /// DOI 10.3969/j.issn.1001-2397.2025.03.08；作者单位印「深圳大学法学院教授」）。近作 · CLSCI · 知网收录。
    static let xiongWeiPaper = SourceVerificationExample(
        citation: "熊伟《国家创新体系中财税法的功能适配与规则优化》（《现代法学》2025 年第 3 期）",
        query: "熊伟 国家创新体系中财税法的功能适配与规则优化",
        kindLabel: "论文",
        findableInScholarDB: true)

    /// 宋旭光（深大法学院副院长）·《论司法裁判的人工智能化及其限度》，《比较法研究》2020 年第 5 期。
    /// 核实：比较法研究官网 zgfxqk.chinalaw.org.cn/portal/article/index/id/3300.html（知网收录）。
    static let songXuguangPaper = SourceVerificationExample(
        citation: "宋旭光《论司法裁判的人工智能化及其限度》（《比较法研究》2020 年第 5 期）",
        query: "宋旭光 论司法裁判的人工智能化及其限度",
        kindLabel: "论文",
        findableInScholarDB: true)

    // MARK: 兜底 —— 新出译著，知网 / 百度学术尚未收录

    /// 张贤伟（深大法学院助理教授）译·《法律是可计算的吗？》商务印书馆 2025 年 11 月。
    /// 原著 Deakin & Markou, *Is Law Computable?* (Hart, 2020)。ISBN 9787100253529。
    /// 核实：商务印书馆 cp.com.cn/book/5d4f8dc5-d.html；豆瓣 book.douban.com/subject/37422136/。
    /// 知网/百度学术实测查无（2025.11 新书，学术库未收录）→ 演示「搜索引擎兜底」。
    static let zhangBookComputable = SourceVerificationExample(
        citation: "张贤伟 译《法律是可计算的吗？——关于法律和人工智能的批判性观点》（商务印书馆 2025 年版）",
        query: "张贤伟 法律是可计算的吗",
        kindLabel: "译著",
        findableInScholarDB: false)

    /// 张贤伟 主译·《新技术时代的知识产权法（第一卷）》中国政法大学出版社 2026 年 2 月。
    /// 原著 Menell / Lemley / Merges / Balganesh（2022 版）。ISBN 9787576424867。
    /// 撞名陷阱：另有 2003 年齐筠译同名书（douban 1613260）——「版本 / 真伪核对」教学点。
    static let zhangBookIP = SourceVerificationExample(
        citation: "张贤伟 主译《新技术时代的知识产权法（第一卷）》（中国政法大学出版社 2026 年版）",
        query: "新技术时代的知识产权法 张贤伟",
        kindLabel: "译著",
        findableInScholarDB: false)

    /// 「来源核验」演示用的正例对（学术库可查）。
    static let findablePair = [xiongWeiPaper, songXuguangPaper]
    /// 「搜索引擎兜底」演示主例（学术库查不到的新译著）。
    static let fallbackPrimary = zhangBookComputable
    /// 全部示例（供一致性测试遍历）。
    static let all = [xiongWeiPaper, songXuguangPaper, zhangBookComputable, zhangBookIP]
}
