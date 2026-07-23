import Foundation

// MARK: - 488 找类案联网候选筛选
//
// The 找类案 online path: web-AI (qwenSearch) returns candidate cases; this screener is the
// runtime gate that finally exercises #473 (案号验证) + #474 (交叉验证 / 两高配额). Core-only —
// the actual quoted-case-number search is injected (`crossCheck`); the macOS layer wires it to
// the search executor. A candidate is shown only if it clears the 案号 gate; fabricated /
// numberless cases are dropped; passing-but-unconfirmed are labeled「AI 生成·未核验」.

public struct CaseCandidate: Sendable, Equatable {
    public let title: String
    public let text: String          // 含案号的候选文本（喂给案号验证）
    public let sourceURLs: [String]  // qwenSearch 返回的来源
    public let isTypicalCase: Bool   // 两高典型案例（官方，免案号闸但限配额）

    public init(title: String, text: String, sourceURLs: [String], isTypicalCase: Bool) {
        self.title = title; self.text = text; self.sourceURLs = sourceURLs; self.isTypicalCase = isTypicalCase
    }
}

public enum CaseCandidateLabel: String, Sendable, Equatable {
    case verified      // ✅ 过案号闸 + 交叉验证命中独立来源
    case aiUnverified  // ⚠️ AI 生成·未核验（过闸但来源不足 / 两高豁免「案号待核实」）
}

public struct ScreenedCase: Sendable, Equatable {
    public let candidate: CaseCandidate
    public let label: CaseCandidateLabel

    public init(candidate: CaseCandidate, label: CaseCandidateLabel) {
        self.candidate = candidate; self.label = label
    }
}

public struct CaseCandidateScreener: Sendable {
    let verifier: CaseNumberVerifier
    public init(currentYear: Int) { self.verifier = CaseNumberVerifier(currentYear: currentYear) }

    /// `crossCheck`: 案号 → 命中来源 URL（macOS 用引号精确搜执行；测试注入假值）。
    public func screen(
        _ candidates: [CaseCandidate],
        crossCheck: @Sendable (String) async -> [String]
    ) async -> [ScreenedCase] {
        var regular: [ScreenedCase] = []
        var typical: [ScreenedCase] = []
        for c in candidates {
            if c.isTypicalCase {
                // 两高典型案例：免案号闸（无文书案号），但须带官方来源，且标⚠️未核验、受配额限制。
                guard !c.sourceURLs.isEmpty else { continue }
                typical.append(ScreenedCase(candidate: c, label: .aiUnverified))
                continue
            }
            let verdict = verifier.verify(c.text)
            guard verdict.disposition == .admit, let cn = verdict.caseNumber else { continue }
            let urls = await crossCheck(cn.raw)
            let result = CaseNumberCrossCheck.classify(
                independentSources: CaseNumberCrossCheck.independentSources(matchedURLs: urls))
            regular.append(ScreenedCase(candidate: c, label: result == .verified ? .verified : .aiUnverified))
        }
        // 两高典型占比 ≤30%，且无普通类案则不收（TypicalCaseQuota）。
        return TypicalCaseQuota.enforce(regular: regular, typical: typical)
    }
}
