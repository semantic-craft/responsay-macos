import Foundation

// MARK: - 来源核验 source menu (verify-on-demand for ANY selection)
//
// 用户拍板：选中 → 点「来源核验」→ 弹一个分组源菜单，自己挑去哪个源核验（不再靠
// 「识别到法条/案号才给核验」那道门，也不再一次性自动开 4 个）。
//
// 每组列若干源，每个源都备好一条可直接打开的 route：
//   · 抽到该组相关的结构化坐标（法条/案号/文献） → 用坐标当检索词（最精准）；
//   · 抽不到 → 用整段选区规范化后的检索词（截断+合并空白）——这样「任何选区都能核验」。
// 付费/JS 站由 VerificationQueryRouter 自动走必应 site: 落到结果页。

public struct VerifyMenuItem: Sendable, Equatable {
    public let source: VerificationSourcePreference
    public let title: String              // 显示名（北大法宝 / 知网 / 必应 …）
    public let route: VerificationRoute    // 已备好的可打开 route

    public init(source: VerificationSourcePreference, title: String, route: VerificationRoute) {
        self.source = source
        self.title = title
        self.route = route
    }
}

public struct VerifyMenuGroup: Sendable, Equatable {
    public let title: String              // 法规 / 案例 / 文献 / 兜底
    public let items: [VerifyMenuItem]

    public init(title: String, items: [VerifyMenuItem]) {
        self.title = title
        self.items = items
    }
}

public struct SelectionVerifyMenu: Sendable {
    public init() {}

    /// Longest query we put into a search URL when falling back to the whole selection.
    /// Long queries blow up the URL and make CJK search engines return nothing (issue 328).
    public static let maxSelectionQueryLength = 80

    private let router = VerificationQueryRouter()

    // 分组定义：标题 · 该组「相关的」锚点 kind（用于挑精准检索词）· 该组列出的源（顺序即菜单顺序）。
    private struct GroupSpec {
        let title: String
        let kinds: Set<VerificationKind>
        let sources: [VerificationSourcePreference]
    }

    private static let groups: [GroupSpec] = [
        GroupSpec(title: "法规",
                  kinds: [.law, .administrativeRule, .standard, .officialDocument],
                  sources: [.govLaw, .pkulaw]),
        GroupSpec(title: "案例",
                  kinds: [.caseLaw],
                  sources: [.pkulaw, .itslaw, .wenshu, .rmfyalk]),
        GroupSpec(title: "文献",
                  kinds: [.scholarlyArticle],
                  sources: [.cnki, .vip, .wanfang, .baiduScholar]),
        GroupSpec(title: "兜底",
                  kinds: [],
                  sources: [.bing, .webSearch]),
    ]

    /// Build the grouped source menu for a selection. Pass any anchors the extractor found
    /// so each group can prefer the precise coordinate; with no anchors every group falls
    /// back to the whole selection. Empty selection → empty menu.
    public func build(selectedText: String, anchors: [VerificationAnchor] = []) -> [VerifyMenuGroup] {
        let fallback = Self.normalizeSelection(selectedText)
        return Self.groups.compactMap { spec in
            let query = Self.query(for: spec, anchors: anchors, fallback: fallback)
            guard !query.isEmpty else { return nil }
            let items = spec.sources.flatMap { source -> [VerifyMenuItem] in
                if source == .cnki { return cnkiItems(query: query) }
                return [VerifyMenuItem(source: source, title: source.displayName,
                                       route: router.route(for: Self.syntheticAnchor(query: query), source: source))]
            }
            return VerifyMenuGroup(title: spec.title, items: items)
        }
    }

    // MARK: - Query resolution

    private static func query(for spec: GroupSpec, anchors: [VerificationAnchor], fallback: String) -> String {
        if let match = anchors.first(where: { spec.kinds.contains($0.kind) }) {
            let q = match.query.trimmingCharacters(in: .whitespacesAndNewlines)
            return q.isEmpty ? match.label : q
        }
        return fallback
    }

    private static func syntheticAnchor(query: String) -> VerificationAnchor {
        VerificationAnchor(id: "selection", label: query, kind: .other, query: query)
    }

    /// 知网拆成两项：关键词直达（一框式 `?kw=`）+ 专业检索式（开 AdvSearch 页 + 复制检索式）。
    /// 专业检索框无 GET 参数：route.url=AdvSearch（无 query string）、route.query=生成的检索式，
    /// 打开时 `SelectionVerifyClipboard` 自动把检索式复制到剪贴板供粘贴。
    private func cnkiItems(query: String) -> [VerifyMenuItem] {
        let keyword = VerifyMenuItem(
            source: .cnki, title: "知网·关键词",
            route: router.route(for: Self.syntheticAnchor(query: query), source: .cnki))
        let expert = VerifyMenuItem(
            source: .cnki, title: "知网·专业检索式",
            route: VerificationRoute(kind: .deepLink, source: .cnki,
                                     query: CNKIExpertQueryBuilder.build(query: query),
                                     url: CNKIExpertQueryBuilder.professionalSearchURL))
        return [keyword, expert]
    }

    /// Trim + collapse internal whitespace/newlines + truncate. Used only for the
    /// whole-selection fallback query (precise anchors are short and used verbatim).
    static func normalizeSelection(_ text: String, maxLength: Int = maxSelectionQueryLength) -> String {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        return collapsed.count <= maxLength ? collapsed : String(collapsed.prefix(maxLength))
    }
}
