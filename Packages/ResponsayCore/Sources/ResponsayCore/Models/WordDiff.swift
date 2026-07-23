import Foundation

/// 词级 diff 的一段:不变 / 删除 / 新增。
public enum DiffOp: Equatable, Sendable {
    case same(String)
    case del(String)
    case ins(String)
}

/// 把"原话 → 地道版"做词级 LCS diff;中文原文(含 CJK)时不显 diff。
public enum WordDiff {
    /// 原文含中日韩字符时返回 false(中文意图改显引用、不显 diff)。
    public static func shouldShow(forSource source: String) -> Bool {
        for s in source.unicodeScalars {
            let v = s.value
            if (0x3400...0x9FFF).contains(v)   // CJK Unified (+ Ext A)
                || (0xF900...0xFAFF).contains(v) // CJK Compatibility
                || (0x3040...0x30FF).contains(v) // Hiragana/Katakana
                || (0xAC00...0xD7A3).contains(v) // Hangul
            { return false }
        }
        return true
    }

    /// 按空白切词后的 LCS diff。
    public static func diff(original: String, idiomatic: String) -> [DiffOp] {
        let a = original.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let b = idiomatic.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        // lcs[i][j] = LCS 长度 of a[i...], b[j...]
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        if !a.isEmpty && !b.isEmpty {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1
                                             : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var ops: [DiffOp] = []
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { ops.append(.same(a[i])); i += 1; j += 1 }
            else if lcs[i + 1][j] >= lcs[i][j + 1] { ops.append(.del(a[i])); i += 1 }
            else { ops.append(.ins(b[j])); j += 1 }
        }
        while i < a.count { ops.append(.del(a[i])); i += 1 }
        while j < b.count { ops.append(.ins(b[j])); j += 1 }
        return ops
    }
}
