import Foundation

/// 后端 /express 的返回:地道句 + 原话 + 为什么不地道(中文要点)
/// + 中式/美式思维对照 + 0–2 个备选说法。
public struct ExpressionResult: Codable, Sendable, Equatable {
    public let idiomatic: String
    public let original: String
    public let reasons: [String]
    public let thinkingShift: String
    public let alternatives: [String]
    /// 422 — 猜测意图: how the coach read a tangled utterance (原 X → 我理解为 Y, Simplified
    /// Chinese). Empty under 原意优先 / whenever the coach did not need to reconstruct intent.
    public let intentNote: String

    public init(
        idiomatic: String,
        original: String,
        reasons: [String],
        thinkingShift: String = "",
        alternatives: [String] = [],
        intentNote: String = ""
    ) {
        self.idiomatic = idiomatic
        self.original = original
        self.reasons = reasons
        self.thinkingShift = thinkingShift
        self.alternatives = alternatives
        self.intentNote = intentNote
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        idiomatic = try c.decode(String.self, forKey: .idiomatic)
        original = try c.decode(String.self, forKey: .original)
        reasons = try c.decodeIfPresent([String].self, forKey: .reasons) ?? []
        thinkingShift = try c.decodeIfPresent(String.self, forKey: .thinkingShift) ?? ""
        alternatives = try c.decodeIfPresent([String].self, forKey: .alternatives) ?? []
        intentNote = try c.decodeIfPresent(String.self, forKey: .intentNote) ?? ""
    }
}
