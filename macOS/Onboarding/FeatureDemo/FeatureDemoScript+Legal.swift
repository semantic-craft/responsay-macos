import Foundation

// 来源核验 / 检索关键词 / 搜索引擎兜底 —— 法律 AI demos。示例用深大法学院真实可查的 CLSCI 论文
// （院长熊伟、副院长宋旭光）+ 新译著兜底（助理教授张贤伟）。锚点 label / 分类 / 检索词来自
// SourceVerificationExamples（已联网核实），经 SearchStrategyGenerator 真实产出知网 / 百度学术深链；
// 见 SourceVerificationExamplesTests。
extension FeatureDemoScript {

    static let verify = FeatureDemoScript(
        kicker: "法律 AI",
        title: "来源核验",
        blurb: "选中含文献引用的文字，从划词菜单选「来源核验」，提取论文、专著、法条等坐标，跳到知网 / 百度学术核对，并把命中的来源证据卡带回面板。",
        hostName: "文献综述",
        host: .document(title: "文献综述初稿",
                        before: "数字时代的财税与司法议题，参见",
                        selected: "熊伟《国家创新体系中财税法的功能适配与规则优化》、宋旭光《论司法裁判的人工智能化及其限度》",
                        after: "等。",
                        muted: "上述引用将随稿件提交，需逐条核验。"),
        listeningLabel: "",
        thinkingLabel: "提取并检索中…",
        resultLabel: "来源核验结果",
        target: "",
        diffDeleted: "",
        diffInserted: "",
        reason: "",
        primaryAction: "打开来源",
        wordTokens: [],
        resultContent: .anchors(items: [
            DemoAnchorItem(
                label: "熊伟《国家创新体系中财税法的功能适配与规则优化》",
                kind: SourceVerificationExamples.xiongWeiPaper.kindLabel,
                sourceTitle: "《现代法学》官网 PDF / 知网",
                sourceURL: "qks.swupl.edu.cn · CNKI",
                evidence: "作者熊伟 · 2025年第3期 · 第100–114页",
                searchQuery: SourceVerificationExamples.xiongWeiPaper.query,
                resultTitle: "国家创新体系中财税法的功能适配与规则优化",
                resultMeta: "熊伟 — 《现代法学》2025年第3期 · 第100–114页",
                resultSnippet: "期刊官网 PDF 与学术库题名一致，页码范围对应 100–114。",
                matchFields: ["题名一致", "作者：熊伟", "期刊：《现代法学》", "页码：100–114"]),
            DemoAnchorItem(
                label: "宋旭光《论司法裁判的人工智能化及其限度》",
                kind: SourceVerificationExamples.songXuguangPaper.kindLabel,
                sourceTitle: "《比较法研究》官网 / 知网",
                sourceURL: "zgfxqk.chinalaw.org.cn · CNKI",
                evidence: "作者宋旭光 · 2020年第5期 · 题名一致",
                searchQuery: SourceVerificationExamples.songXuguangPaper.query,
                resultTitle: "论司法裁判的人工智能化及其限度",
                resultMeta: "宋旭光 — 《比较法研究》2020年第5期",
                resultSnippet: "学术库结果与引用题名、作者、年份、期刊均对应。",
                matchFields: ["题名一致", "作者：宋旭光", "期刊：《比较法研究》", "年份：2020年第5期"]),
        ]))

    static let keywords = FeatureDemoScript(
        kicker: "法律 AI",
        title: "检索关键词生成",
        blurb: "选中案情描述，自动生成法条、案例、论文三类检索关键词和 CNKI 专业检索式。",
        hostName: "法律备忘录",
        host: .document(title: "案情摘要",
                        before: "",
                        selected: "承租人未经出租人同意擅自转租，出租人主张解除合同并要求返还租赁物。",
                        after: "",
                        muted: "争议焦点：转租效力与合同解除权行使条件。"),
        listeningLabel: "",
        thinkingLabel: "生成检索词…",
        resultLabel: "检索关键词",
        target: "检索式：SU=('转租' AND '合同解除') OR SU=('租赁' AND '违约')",
        diffDeleted: "",
        diffInserted: "",
        reason: "",
        primaryAction: "插入检索式",
        wordTokens: [],
        resultContent: .keywords(
            groups: [
                DemoKeywordGroup(category: "法条", terms: ["民法典 第716条", "民法典 第717条"]),
                DemoKeywordGroup(category: "案例", terms: ["擅自转租 合同解除", "未经同意转租 违约"]),
                DemoKeywordGroup(category: "论文", terms: ["转租效力 研究", "合同解除权 租赁"]),
            ],
            cnkiQuery: "SU=('转租' AND '合同解除') OR SU=('租赁' AND '违约')"))

    // 模型联网核验已接入；这个 demo 展示数据库未收录时的「搜索引擎兜底」—— 张贤伟新译
    // 《法律是可计算的吗？》知网/百度学术尚未收录，兜底走百度网页搜索，直达商务印书馆 / 豆瓣。
    // 结果 URL 均已联网核实；见 SourceVerificationExamples。
    static let fallback = FeatureDemoScript(
        kicker: "法律 AI",
        title: "搜索引擎兜底",
        blurb: "新出的译著学术库还没收录？知网、百度学术查不到时，兜底跳转搜索引擎，直达出版社 / 书目页核实真伪。",
        hostName: "百度搜索",
        host: .webSearchHost(title: "百度",
                             query: "张贤伟 法律是可计算的吗"),
        listeningLabel: "",
        thinkingLabel: "知网查无 · 搜索引擎兜底…",
        resultLabel: "兜底找到（搜索引擎 ↗ 浏览器打开）",
        target: "",
        diffDeleted: "",
        diffInserted: "",
        reason: "",
        primaryAction: "打开来源",
        wordTokens: [],
        resultContent: .webResults(items: [
            DemoWebResultItem(
                title: "法律是可计算的吗？——关于法律和人工智能的批判性观点",
                url: "cp.com.cn/book/5d4f8dc5-d.html",
                snippet: "〔英〕西蒙·迪金、克里斯托弗·马库 主编；张贤伟 译。商务印书馆 2025 年 11 月。ISBN 9787100253529。"),
            DemoWebResultItem(
                title: "法律是可计算的吗？ - 豆瓣读书",
                url: "book.douban.com/subject/37422136/",
                snippet: "536 页 · 定价 168 元 · 原著 Is Law Computable?（Hart, 2020）。"),
        ]))
}
