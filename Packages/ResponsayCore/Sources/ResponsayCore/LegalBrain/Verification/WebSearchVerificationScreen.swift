import Foundation

// MARK: - WebSearchVerificationScreen
//
// 独立检索服务给的是**没有经过判断的**网页列表——模型自带联网那条路上,至少还有模型在
// 「这条搜到的东西对不对得上」这件事上把过一道关。直接拿第一条回填 `VerifiedSource`,
// 会把一条不相关的网页写成「已核验」,这正是 [待核] 机制最不能出的错。
//
// 所以在回填前做一道**保守**的本地筛:结果里要真的提到这个引用才算数。筛不出就返回 nil,
// 锚点保持 pending——沿用全局铁律:搜不到 ≠ 不存在,宁可不给来源,不给错来源。

enum WebSearchVerificationScreen {

    /// 第一条确实提到该引用的结果;都对不上 → nil。
    static func firstMatch(documents: [WebSearchDocument], query: String) -> WebSearchDocument? {
        let needle = normalize(query)
        guard !needle.isEmpty else { return nil }
        return documents.first { matches(document: $0, normalizedQuery: needle) }
    }

    /// 两条判据(满足其一即可):
    /// 1. 归一化后网页里直接出现了整个引用(法条名、标准号、文献标题多半这样命中);
    /// 2. 引用里的每一段数字都出现在网页里 —— 案号/年份/条序号这类引用几乎全靠数字定位,
    ///    「(2021)京01民终1234号」的三段数字全中,基本不可能是另一个案子。
    static func matches(document: WebSearchDocument, normalizedQuery needle: String) -> Bool {
        let haystack = normalize(document.title + document.snippet + document.url)
        guard !haystack.isEmpty else { return false }
        if haystack.contains(needle) { return true }
        let runs = digitRuns(needle)
        return !runs.isEmpty && runs.allSatisfy { haystack.contains($0) }
    }

    /// 去掉空白与引用里常见的标点/括号(全半角都算),避免「（2021）」与「(2021)」对不上。
    /// 大小写统一,英文文献标题才不会因为大小写差异漏判。
    static func normalize(_ raw: String) -> String {
        let dropped = Set("　 \t\n\r()（）[]【】〔〕《》<>「」“”\"'’‘,，、。.;；:：!！?？-—–_/\\|")
        return String(raw.lowercased().filter { !dropped.contains($0) })
    }

    /// 连续数字段。只认阿拉伯数字:中文数字(「第一千零七十九条」)由上面的整串包含判据兜住。
    static func digitRuns(_ text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in text {
            if character.isNumber, character.isASCII {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }
}
