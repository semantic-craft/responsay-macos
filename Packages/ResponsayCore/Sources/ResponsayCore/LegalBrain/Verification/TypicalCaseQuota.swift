import Foundation

/// 474 — 两高典型案例豁免配额（PRD S2）。最高法/最高检官方典型案例可无完整案号入选（标「案号待核实」+
/// 官方 URL），但报告中占比 ≤ 30%，且不能全靠它（无普通类案 → 不允许两高）。纯计数，整数运算避免浮点取整误差。
public enum TypicalCaseQuota {
    /// 占比上限 30% = 3/10。typical/(typical+regular) ≤ 3/10  ⇔  typical ≤ (3/7)·regular。
    public static func allowedTypicalCount(regularCount: Int) -> Int {
        max(0, regularCount) * 3 / 7
    }

    /// 保留全部普通类案，两高典型按配额截断后追加。
    public static func enforce<T>(regular: [T], typical: [T]) -> [T] {
        regular + typical.prefix(allowedTypicalCount(regularCount: regular.count))
    }
}
