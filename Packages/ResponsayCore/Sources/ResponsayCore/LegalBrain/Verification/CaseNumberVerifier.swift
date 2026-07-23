import Foundation

/// 473 — 案号验证引擎（PRD S1）：案例进入展示/报告的唯一准入闸。把"案号"当成防幻觉的可核验锚点。
/// 纯函数：提取 → 格式校验 → 三重分类（+❓疑似虚构）→ 处置。交叉验证（引号精确搜）在 #474。

public enum CaseType: Sendable, Equatable {
    case criminalFirstInstance      // 刑初
    case criminalSecondInstance     // 刑终
    case civilFirstInstance         // 民初
    case civilSecondInstance        // 民终
    case administrativeFirstInstance // 行初
    case execution                  // 执
    case caseLibrary                // 入库编号
}

public enum CaseNumberStatus: Sendable, Equatable {
    case complete            // ✅ 可提取且格式正确
    case partial             // ⚠️ 有类型标记但缺年份/完整编号（截断）
    case missing             // ❌ 完全无案号信号
    case suspectedFabricated // ❓ 形似案号但格式不符规范
}

public enum CaseNumberDisposition: Sendable, Equatable {
    case admit                     // 准入
    case attemptCompleteElseDiscard // 尝试补全，失败则废弃
    case discard                   // 废弃
}

public struct CaseNumber: Sendable, Equatable {
    public let raw: String
    public let year: Int
    public let courtCode: String   // 法院代字，如 皖1702 / 粤01
    public let caseType: CaseType
    public let sequence: Int

    public init(raw: String, year: Int, courtCode: String, caseType: CaseType, sequence: Int) {
        self.raw = raw; self.year = year; self.courtCode = courtCode
        self.caseType = caseType; self.sequence = sequence
    }
}

public struct CaseNumberVerdict: Sendable, Equatable {
    public let caseNumber: CaseNumber?
    public let status: CaseNumberStatus

    public var disposition: CaseNumberDisposition {
        switch status {
        case .complete: return .admit
        case .partial: return .attemptCompleteElseDiscard
        case .missing, .suspectedFabricated: return .discard
        }
    }
}

public struct CaseNumberVerifier: Sendable {
    let currentYear: Int
    public init(currentYear: Int) { self.currentYear = currentYear }

    public func verify(_ text: String) -> CaseNumberVerdict {
        let shapes = fullShapeMatches(in: text)
        if let valid = shapes.first(where: { $0.yearValid }) {
            return CaseNumberVerdict(caseNumber: valid.cn, status: .complete)
        }
        if !shapes.isEmpty {
            // 完整形状存在但无一年份合法 = 格式不符规范 → 疑似虚构。
            return CaseNumberVerdict(caseNumber: nil, status: .suspectedFabricated)
        }
        if Self.hasPartialStem(in: text) {
            return CaseNumberVerdict(caseNumber: nil, status: .partial)
        }
        if Self.hasSuspectShape(in: text) {
            return CaseNumberVerdict(caseNumber: nil, status: .suspectedFabricated)
        }
        return CaseNumberVerdict(caseNumber: nil, status: .missing)
    }

    /// ❓ 形似案号但既非合法完整、也非真词干：`(YYYY)<连续非标点串>号` 的壳（类型字编造）。
    /// 跑到这步前，合法完整 / 非法年份完整形状 / 真部分词干都已被前面拦下。
    private static func hasSuspectShape(in text: String) -> Bool {
        let pattern = "[（(]\\d{4}[）)][^\\s。，、；：（）()]{1,18}号"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = text as NSString
        return re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil
    }

    /// ⚠️ 部分：有「代字（汉字+数字）+ 类型标记」的真案号词干，但 `completeMatch` 没过（缺年份/seq号）。
    /// 用「汉字+数字」前缀把「执行/执法」这类普通词里的「执」排除掉。
    private static func hasPartialStem(in text: String) -> Bool {
        let pattern = "\\p{Han}+\\d+(刑初|刑终|民初|民终|行初|执)|入库编号\\d"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = text as NSString
        return re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil
    }

    // MARK: - Marker table（标准格式，半/全角括号兼容）

    private static let markerTable: [(marker: String, type: CaseType)] = [
        ("刑初", .criminalFirstInstance), ("刑终", .criminalSecondInstance),
        ("民初", .civilFirstInstance), ("民终", .civilSecondInstance),
        ("行初", .administrativeFirstInstance), ("执", .execution),
    ]

    /// 所有「完整形状」案号匹配（不论年份是否合法），各带 `yearValid` 标记。`verify` 据此把
    /// 形状对但年份非法的判为 ❓疑似虚构，形状对且年份合法的判为 ✅完整。
    private func fullShapeMatches(in text: String) -> [(cn: CaseNumber, yearValid: Bool)] {
        let ns = text as NSString
        var out: [(CaseNumber, Bool)] = []
        func collect(_ pattern: String, _ build: (NSTextCheckingResult) -> CaseNumber?) {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return }
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if let cn = build(m) { out.append((cn, (1900...currentYear).contains(cn.year))) }
            }
        }
        // 入库编号 YYYY-XX-X-XXX-XXX（人民法院案例库，shape 与裁判文书案号不同）
        collect("入库编号(\\d{4})-\\d{2}-\\d-\\d{3}-\\d{3}") { m in
            guard let year = Int(ns.substring(with: m.range(at: 1))) else { return nil }
            return CaseNumber(raw: ns.substring(with: m.range), year: year,
                              courtCode: "", caseType: .caseLibrary, sequence: 0)
        }
        // 裁判文书：(YYYY)<代字><marker><seq>号
        for entry in Self.markerTable {
            collect("[（(](\\d{4})[）)]([^（）()号]*?)\(entry.marker)(\\d+)号") { m in
                guard let year = Int(ns.substring(with: m.range(at: 1))),
                      let seq = Int(ns.substring(with: m.range(at: 3))) else { return nil }
                let code = ns.substring(with: m.range(at: 2))
                guard !code.isEmpty else { return nil }
                return CaseNumber(raw: ns.substring(with: m.range), year: year,
                                  courtCode: code, caseType: entry.type, sequence: seq)
            }
        }
        return out
    }
}
