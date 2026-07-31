import Foundation

/// 把一句口语提问压成一条检索词。
///
/// 为什么需要:语音提问动辄几百字,而豆包搜索 Global 版的 Query 硬上限是 100 字符
/// (`WebSearchBackendKind.queryCharacterLimit`),直接截前 100 字往往截到的是
/// 「那个我想问一下就是说……」这类铺垫,搜出来全不相关。所以超限时先让主模型提炼。
/// 没超限就原样送——不为一次多余的往返买单。
///
/// 纯字符串逻辑;真正的模型调用在 `DirectSearchQueryAPI`。
public enum SearchQueryDistiller {

    static let systemPrompt = """
    你是检索词提炼助手。把用户的一句口语提问压成一条能直接丢进搜索引擎的检索词。
    要求:
    - 只输出检索词本身,不要引号、不要解释、不要换行。
    - 去掉语气词、口癖、称呼、寒暄,以及「帮我查一下」这类指令性措辞。
    - 保留专有名词、时间、数字、地名和限定条件——它们才是检索的锚。
    - 用户用什么语言问,就用什么语言输出。
    """

    static func userPrompt(_ question: String, limit: Int) -> String {
        """
        把下面这句提问压成一条不超过 \(limit) 个字符的检索词:

        \(question)
        """
    }

    /// 只有超过后端的检索词上限才值得多跑一次模型。
    public static func needsDistilling(_ question: String, limit: Int) -> Bool {
        question.trimmingCharacters(in: .whitespacesAndNewlines).count > limit
    }

    /// 清洗模型输出:取第一行、去掉包裹的引号和「检索词:」前缀、压平空白、按上限截断。
    /// 清洗后为空 → nil,调用方退回截断原句。
    static func clean(_ raw: String, limit: Int) -> String? {
        let firstLine = raw
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        var text = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["检索词:", "检索词：", "搜索词:", "搜索词："] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”「」《》 "))
        let collapsed = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(limit))
    }

    /// 提炼失败时的兜底:直接截断。检索一个糙检索词,好过整条联网路径失败退回纯记忆作答。
    public static func truncated(_ question: String, limit: Int) -> String {
        String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}
