import Foundation

// Toneless-pinyin phonetic machinery for the CJK hard-match pass (#465/#477). Split out of
// HotwordHardMatch (file ≤400 lines); same enum namespace, so the orchestration calls these
// unqualified. `internal` (not `private`) only so the methods can live in this file.
extension HotwordHardMatch {

    /// Per-character toneless pinyin syllables of a CJK string (Foundation
    /// `CFStringTransform`, no third-party dep). 根目录 → ["gen","mu","lu"]; 跟目录 → the same,
    /// so homophones align syllable-for-syllable. Empty syllables are dropped.
    static func pinyinSyllables(_ value: String) -> [String] {
        let latin = value.applyingTransform(.toLatin, reverse: false) ?? value
        let bare = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return bare.lowercased()
            .split { !($0.isASCII && $0.isLetter) }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Split a pinyin syllable into (initial, final) — longest-prefix initial match,
    /// "" initial for a zero-initial syllable (an, ying, …).
    static func splitSyllable(_ s: String) -> (initial: String, final: String) {
        for initial in ["zh", "ch", "sh"] where s.hasPrefix(initial) {
            return (initial, String(s.dropFirst(2)))
        }
        for initial in ["b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
                        "j", "q", "x", "r", "z", "c", "s", "y", "w"] where s.hasPrefix(initial) {
            return (initial, String(s.dropFirst(1)))
        }
        return ("", s)
    }

    /// Fuzzy-pinyin confusion sets (模糊音 — the pairs Mandarin speakers/ASR routinely
    /// blur), inspired by DimSim / IME fuzzy-pinyin. A substitution inside a set is a cheap
    /// edit; anything else is rejected — so 代码厂→代码仓 (ch/c) snaps but 排版→白板 (b/p, not a
    /// fuzzy pair) does not.
    ///
    /// #500 S4 — evaluated against the canonical rime `fuzzy_pinyin` set: these 6 initials + 5
    /// finals ARE that full standard set, so there is nothing safe left to add (k/g and j/q/x blurs
    /// are dialectal and, under toneless matching, would over-snap). Two deliberate non-additions:
    /// (1) **tone weighting** (`same_pinyin`, a CSC technique) is declined — ASR routinely errs on
    /// tone, so penalizing a tone mismatch would hurt recall on exactly the errors we exist to fix;
    /// toneless is correct for ASR correction (vs human-typo CSC). (2) A full **DimSim** encoding
    /// swap stays a deferred seam — the current sets already cover the high-frequency confusions.
    static let confusableInitials: [Set<String>] = [
        ["zh", "z"], ["ch", "c"], ["sh", "s"], ["n", "l"], ["r", "l"], ["f", "h"],
    ]
    static let confusableFinals: [Set<String>] = [
        ["an", "ang"], ["en", "eng"], ["in", "ing"], ["ian", "iang"], ["uan", "uang"],
    ]

    static func areConfusable(_ a: String, _ b: String, _ sets: [Set<String>]) -> Bool {
        sets.contains { $0.contains(a) && $0.contains(b) }
    }

    /// Phonetic cost of substituting one syllable for another: 0 if identical, 1 per
    /// confusable component (initial and/or final), or nil if any component differs by a
    /// non-confusable sound (a genuinely different syllable).
    static func syllableCost(_ a: String, _ b: String) -> Int? {
        if a == b { return 0 }
        let (ia, fa) = splitSyllable(a)
        let (ib, fb) = splitSyllable(b)
        let initialOK = ia == ib || areConfusable(ia, ib, confusableInitials)
        let finalOK = fa == fb || areConfusable(fa, fb, confusableFinals)
        guard initialOK, finalOK else { return nil }
        return (ia == ib ? 0 : 1) + (fa == fb ? 0 : 1)
    }

    /// Total phonetic cost over syllable-aligned words (same length), or nil if any
    /// syllable is a non-confusable mismatch.
    static func windowCost(_ a: [String], _ b: [String]) -> Int? {
        guard !a.isEmpty, a.count == b.count else { return nil }
        var total = 0
        for (x, y) in zip(a, b) {
            guard let cost = syllableCost(x, y) else { return nil }
            total += cost
        }
        return total
    }

    /// How much confusable drift a whole word may carry: a 2-char term gets one confusable
    /// component, longer terms two — tight enough to keep precision.
    static func costBudget(forSyllables n: Int) -> Int {
        n <= 2 ? 1 : 2
    }

    /// Common 多音字 (polyphones) whose single context-free `.toLatin` reading is often wrong
    /// inside a word. `pinyinSyllables` assigns one toneless reading per char regardless of
    /// context, so any window touching one of these can collide spuriously (#477): 银行 yín-háng
    /// and 银杏 yín-xìng both flatten to yin-xing because 行 is read "xing"; 音乐 yīn-yuè flattens
    /// to yin-le because 乐 is read "le". Not exhaustive — the high-collision chars.
    static let polyphones: Set<Character> = [
        "行", "长", "重", "乐", "朝", "会", "参", "差", "调", "着", "还", "都", "得", "地",
        "干", "分", "处", "发", "数", "中", "种", "为", "应", "系", "量", "给", "单", "假",
        "空", "角", "觉", "解", "区", "便", "传", "倒", "曲", "卷", "号", "降", "教", "尽",
        "落", "塞", "扇", "盛", "提", "挑", "占", "宿", "兴", "省", "藏", "称", "弹", "更",
        "好", "划", "和", "华", "结", "卡", "看", "累", "宁", "辟", "强", "散", "扫", "似",
    ]

    /// At cost 0 a CJK snap rests entirely on toneless-homophone equality — which a polyphone's
    /// wrong context-free reading can fake — so reject the snap when a 多音字 sits anywhere in the
    /// window or the hotword (#477). A cost≥1 snap carries a genuine confusion-音 edit and is left
    /// alone; a polyphone-free homophone (根目录→跟目录) still snaps.
    static func cost0SnapIsUnsafeAcrossPolyphone(cost: Int, surface: String, spelling: String) -> Bool {
        guard cost == 0 else { return false }
        return surface.contains(where: polyphones.contains) || spelling.contains(where: polyphones.contains)
    }
}
