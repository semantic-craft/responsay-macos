import Foundation

/// Builds the focused NER-correction prompt for the optional LLM tier (#500 S3). The model is given
/// the transcript plus ONLY the retrieved near-miss term candidates and told to repair just those
/// terms' mis-recognitions — never to paraphrase, punctuate, add, or remove anything (ADR-0008
/// faithful transcript; ADR-0011 never insert an unspoken term). The divergence guard
/// (`HotwordCorrectionGuard`) is the backstop if the model over-edits anyway.
public enum HotwordCorrectionPromptBuilder {
    public static func build(transcript: String, candidates: [String]) -> (system: String, user: String) {
        let terms = candidates.joined(separator: "、")
        let system = """
        你是语音转写的术语校对器。下面给你一段语音识别文本，和一份用户常用的专有术语清单。
        任务：只把文本里这些术语的「听错 / 音近误识」改回清单里的正确写法。严格规则：
        - 只动这些术语的误识，别的字一个都不要改。
        - 英文术语以清单拼写为准（含大小写与空格）；一个术语可能被听成连写或拆开的几个词，整段换回清单写法。
        - 绝不新增、删除、改写或润色其它内容；不补标点、不解释、不翻译。
        - 文本里如果没有这些术语的误识，就原样返回。
        只返回改好的文本本身，不要任何前后缀。
        """
        let user = "术语清单：\(terms)\n\n文本：\(transcript)"
        return (system, user)
    }
}
