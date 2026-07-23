import Foundation

/// 可见文本组装纯逻辑（对齐 Typeless）。Mac 层 `VisibleTextCollector` 按 AX 树序遍历采集碎片；
/// 这里负责拼接与截断，进程无关、可单测。
/// smartJoin 语义：正文→正文空格连（读起来像段落），UI 标签换行独立（chrome 自成行）。
public enum VisibleTextComposer {
    public static func smartJoin(_ fragments: [(text: String, isBody: Bool)]) -> String {
        var result = ""
        var prevBody = false
        for (text, isBody) in fragments {
            if result.isEmpty {
                result = text
            } else if isBody && prevBody {
                result += " " + text
            } else {
                result += "\n" + text
            }
            prevBody = isBody
        }
        return result
    }

    /// 树序砍头（对齐 Typeless `collectVisibleTexts → smartJoinTexts → 截断到 maxVisibleTextLength`）：
    /// 碎片按 AX 树序（= 采集顺序，≈文档阅读顺序）拼接，保留前 `maxLength` 字符。
    /// 保头的理由：标题/主题/命名实体多在顶部，正是偏置消歧最需要的信号；且树序保持多栏/分组
    /// 子树连续，不会被几何排序打乱。
    public static func compose(_ fragments: [(text: String, isBody: Bool)], maxLength: Int = 2000) -> String {
        String(smartJoin(fragments).prefix(maxLength))
    }
}
