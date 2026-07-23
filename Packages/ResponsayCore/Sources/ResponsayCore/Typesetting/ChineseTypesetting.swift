import Foundation

/// 中文规范排版：确定性规则（大陆出版通行）+ 指纹护栏下的薄 AI 段落重排。
///
/// 忠实移植自 法墨输入法 `FamoChineseTypesetting` / `FamoSelectionPublishFormatter`（2026-07-22）。
/// 两处刻意复用法言既有能力、不重复造轮子：
///   - 标点半→全角一步走 `OCRTextCleanupAction.chinesePunctuation`（附带 URL / 邮箱 / 反引号代码段保护）；
///   - CJK 判定复用 `OCRTextScript.isCJK`，与截图 OCR 整理保持同一判定。
///
/// 规则只动「空白 + 标点形态」，永不增删或改写文字（字母 / 数字 / 汉字假名）—— 排版工具擅改文字最危险，
/// `contentFingerprint` 把这条不变式变成可机械断言的护栏：AI 段落重排若动了文字（或夹带解释 / 代码块 /
/// 选区里的 prompt injection），指纹不符即丢弃 AI 结果、回退纯规则输出。
public enum ChineseTypesetting {

    // MARK: - 编排（规则优先 + AI 只重排段落）

    /// 指纹护栏择一 + 权威 `finalize`。给定 `cleaned`（`preClean` 后的原文）与可选的 AI 段落重排结果
    /// `reflowed`（nil = 无 AI / 调用失败）：仅当 `reflowed` 非空且**内容指纹与 `cleaned` 一致**
    /// （AI 只动了换行、没动文字）才采用，否则回退纯规则 `cleaned`；再走 `finalize`。这条护栏同时兜住
    /// 选区里夹带的 prompt injection —— 模型若照做而改了内容，指纹不符即被丢弃。
    ///
    /// 刻意拆成纯函数（不吃闭包 / 不涉 actor 隔离）故可离线单测；真正的 AI 调用与 actor 隔离留给调用方
    /// （macOS 侧 `CaptureTransformer.normalizeTypography` 用 BYOK `rewriter` 做重排）：
    /// `let cleaned = preClean(text); let reflowed = try? await rewriter.rewrite(cleaned…); assemble(cleaned:, reflowed:)`。
    public static func assemble(cleaned: String, reflowed: String?) -> String {
        let safe: String
        if let reflowed, !reflowed.isEmpty,
           contentFingerprint(reflowed) == contentFingerprint(cleaned) {
            safe = reflowed
        } else {
            safe = cleaned
        }
        return finalize(safe)
    }

    /// 段落重排系统提示：AI 只把被硬换行拆断的行拼回完整段落，一字不改（引号 / 全半角 / 空格全交给规则）。
    /// 移植自法墨 `publishReflowSystemPrompt`。
    public static let reflowSystemPrompt = """
    你是中文排版助手。下面 user 消息是一段从 PDF 或网页复制、常有硬换行断行的中文文本。你的唯一任务是把被硬换行拆断的行重新拼接成完整段落，保留真正的段落分界（段落之间留一个空行）。

    严格约束：
    1. 一字不改：不得增删、改写、纠错或翻译任何文字；标点也原样保留，不要替换、增删或转换全半角。
    2. 只调整换行与分段：把同一段落内被断开的行合并为连续文本；不同段落之间留一个空行。
    3. 只输出整理后的正文纯文本，不要任何解释、前言、标题、项目符号或 Markdown 代码块。
    """

    // MARK: - 规则管道（纯函数，逐条可离线单测）

    /// 预清洗（段落重排之前）：统一换行符、去每行行尾空白、最多保留一个空行。
    public static func preClean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        t = t.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).replacingOccurrences(of: "[ \\t\u{3000}]+$", with: "", options: .regularExpression) }
            .joined(separator: "\n")
        t = t.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return t
    }

    /// 规范化（段落重排之后、权威最后一道）：省略破折 → 引号 → 全半角标点(复用法言) → 全角括号 → 空格。
    /// 只改标点形态与空白、绝不动文字，故 `contentFingerprint` 前后恒等。
    public static func finalize(_ s: String) -> String {
        var t = normalizeEllipsisAndDash(s)
        t = normalizeQuotes(t)
        // 复用法言既有引擎：`,。；：！？` 半→全角，且自带 URL / 邮箱 / 反引号代码段保护。
        t = OCRTextCleanupAction.chinesePunctuation.apply(to: t)
        // 法言引擎不含全角括号，补上（法墨有）：紧挨 CJK 才转，故 `func(x)` 类英文括号在非 CJK 语境保持。
        t = normalizeBrackets(t)
        t = normalizeSpaces(t)
        return t
    }

    /// 内容指纹：只留文字（字母 / 数字 / 汉字假名等），滤掉一切空白与标点。段落重排前后指纹若不等，
    /// 说明 AI 动了文字（或加了解释 / 代码块），据此丢弃 AI 结果、回退纯规则。
    public static func contentFingerprint(_ s: String) -> String {
        String(s.filter { $0.isLetter || $0.isNumber })
    }

    /// 省略号 → `……`（六点）、破折号 → `——`（双全角）。先于全半角，免得 `...` 被逐点转成句号。
    /// 单个 ASCII `-` 不动（连字符 / 数字区间）。
    public static func normalizeEllipsisAndDash(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "\\.{3,}", with: "……", options: .regularExpression)
        t = t.replacingOccurrences(of: "。{3,}", with: "……", options: .regularExpression)
        t = t.replacingOccurrences(of: "…+", with: "……", options: .regularExpression)
        t = t.replacingOccurrences(of: "-{2,}", with: "——", options: .regularExpression)
        t = t.replacingOccurrences(of: "—+", with: "——", options: .regularExpression)
        return t
    }

    /// 直引号 / 直角引号 → 大陆弯引号 `“”‘’`。英文所有格 / 缩写（ASCII 字母 `'` ASCII 字母）里的撇号保留。
    public static func normalizeQuotes(_ s: String) -> String {
        let chars = Array(s)
        var out: [Character] = []
        out.reserveCapacity(chars.count)
        var dblOpen = true
        var sglOpen = true
        for (i, ch) in chars.enumerated() {
            switch ch {
            case "\"":
                out.append(dblOpen ? "“" : "”")
                dblOpen.toggle()
            case "「": out.append("“")
            case "」": out.append("”")
            case "『": out.append("‘")
            case "』": out.append("’")
            case "'":
                // 仅英文缩写 / 所有格（ASCII 字母'ASCII 字母，如 don't、O'Brien）里的撇号保留；汉字也 isLetter，
                // 汉字之间的直单引号（'乙'）必须转弯引号，故须限定 ASCII，不能只判 isLetter。
                let prev = i > 0 ? chars[i - 1] : " "
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if prev.isLetter, prev.isASCII, next.isLetter, next.isASCII {
                    out.append("'")
                } else {
                    out.append(sglOpen ? "‘" : "’")
                    sglOpen.toggle()
                }
            default:
                out.append(ch)
            }
        }
        return String(out)
    }

    /// CJK 语境里的半角圆括号 → 全角 `（）`。上下文守卫——`(` 后紧挨 CJK、`)` 前紧挨 CJK 时才转，
    /// 故 `func(x)`、`(2022)` 里的半角括号在非 CJK 语境保持不动。（法言 `OCRTextCleanupAction` 未含括号，补此。）
    public static func normalizeBrackets(_ s: String) -> String {
        let chars = Array(s)
        var out: [Character] = []
        out.reserveCapacity(chars.count)
        for (i, ch) in chars.enumerated() {
            let prev = i > 0 ? chars[i - 1] : nil
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            switch ch {
            case "(": out.append(isCJK(next) ? "（" : ch)
            case ")": out.append(isCJK(prev) ? "）" : ch)
            default: out.append(ch)
            }
        }
        return String(out)
    }

    /// 空格规范化：CJK↔CJK 的割裂空格删除；CJK↔数字 不留空（中文数词惯例 2020年 / 第3条 / 共3人）；
    /// CJK↔拉丁字母 走盘古之白，统一成恰好一个空格（先清后插，兼容原文 0 / 1 / 多个空格）；拉丁串内
    /// 多空格并 1。含全角空格 U+3000。换行不受影响（段落分界保住）。
    public static func normalizeSpaces(_ s: String) -> String {
        let cjk = "\\p{Han}\\p{Hiragana}\\p{Katakana}"
        let sp = "[ \u{3000}]+"
        var t = s
        // CJK↔CJK / CJK↔数字：删空
        for p in [
            "(?<=[\(cjk)])\(sp)(?=[\(cjk)])",
            "(?<=[\(cjk)])\(sp)(?=[0-9])",
            "(?<=[0-9])\(sp)(?=[\(cjk)])",
        ] {
            t = t.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        // CJK↔拉丁字母：盘古之白——先清掉原有空格、再在边界插入恰好一个（兼容 0/1/多个）
        for p in [
            "(?<=[\(cjk)])\(sp)(?=[A-Za-z])",
            "(?<=[A-Za-z])\(sp)(?=[\(cjk)])",
        ] {
            t = t.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        for p in [
            "(?<=[\(cjk)])(?=[A-Za-z])",
            "(?<=[A-Za-z])(?=[\(cjk)])",
        ] {
            t = t.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        // 拉丁串内多空格并 1
        return t.replacingOccurrences(of: "[ ]{2,}", with: " ", options: .regularExpression)
    }

    // MARK: - Private

    private static func isCJK(_ character: Character?) -> Bool {
        guard let character else { return false }
        return OCRTextScript.isCJK(character)
    }
}
