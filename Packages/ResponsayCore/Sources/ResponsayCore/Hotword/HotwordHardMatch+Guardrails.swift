import Foundation

// #500 S2 — 误纠护栏 (false-positive guard), ported in spirit from `HaujetZhao/asr-hotword` (MIT).
// Same enum namespace as HotwordHardMatch so the orchestration calls these unqualified.
extension HotwordHardMatch {

    /// **Proximity / common-word blacklist**: high-frequency words that a fuzzy CJK snap must never
    /// rewrite. The #465 phonetic pass is intentionally aggressive (it snaps near-miss homophones to
    /// a user's term), but a common word is far more likely to be what was actually said than a rare
    /// hotword that merely sounds like it — so 扶贫(办) must not become 傅平(办) just because a user
    /// added the name 傅平 (fu pín ≈ fu píng via in/ing). Surfaces here are protected from the fuzzy
    /// `else if` branch only; an EXACT occurrence of the word as a registered hotword still normalizes.
    ///
    // ponytail: hand-picked seed of ultra-common words, NOT a frequency dictionary — extend as real
    // false positives surface. The trigger is narrow (window surface == a protected word AND a user
    // term fuzzy-matches it), so a modest list is safe; a full common-word corpus would risk
    // suppressing legitimate rare-term snaps.
    static let protectedSurfaces: Set<String> = [
        // collide with name/term hotwords via fuzzy-pinyin drift
        "扶贫", "数据", "经济", "社会", "政府", "人民", "法律", "教育", "国家", "公司",
        "工作", "问题", "发展", "时间", "现在", "学生", "老师", "医院", "城市", "环境",
        "政策", "市场", "管理", "服务", "技术", "信息", "系统", "标准", "项目", "结构",
    ]

    /// True when `surface` is a protected common word that a fuzzy snap must leave alone.
    static func isProtectedSurface(_ surface: String) -> Bool {
        protectedSurfaces.contains(surface)
    }
}
