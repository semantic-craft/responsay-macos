import Foundation
import ResponsayCore

/// Two independent 风格包 lanes, each over its own pack pool. 听写技能 (`.dictation`) drives 意图成稿
/// polish; 写作技能 (`.writing`) drives 表达升级 / 改写选中文本 heavy rewrite. Decoupled so changing
/// one never moves the other (replaces the single `ActiveEverydaySkillSettings` that fed both).
///
/// History: the writing key originally seeded itself once from the dictation key ("表达升级 keeps
/// today's behavior" — the 2026-06-30 split migration). That seed died with the 1.5.0 lane-pool
/// split — for bundled packs the copied dictation id is no longer in the writing pool (resolver
/// falls back to the default anyway), and for *imported* packs (offered on both lanes) it would
/// leak a dictation choice into 划词改写, exactly the cross-talk the split eliminates. So the
/// lanes are now fully symmetric: absent key (or a legacy "" sentinel) = built-in default.
enum StyleLaneSettings {
    /// The lane vocabulary now lives in Core (`SkillLane`), because skill files declare which lane
    /// they belong to. Aliased rather than duplicated so the two can't drift apart.
    typealias Lane = SkillLane

    /// Dictation reuses the legacy everyday key → existing users keep their style with no migration.
    static let dictationKey = "rewrite.activeEverydaySkillID"
    static let writingKey = "rewrite.activeWritingSkillID"

    static func key(_ lane: Lane) -> String {
        switch lane {
        case .dictation: dictationKey
        case .writing: writingKey
        }
    }

    /// Pure read; the empty-string check also absorbs the retired seed-era "" sentinel that
    /// existing installs may still have stored.
    static func activeID(_ lane: Lane, defaults: UserDefaults = .standard) -> String? {
        guard let v = defaults.string(forKey: key(lane)), !v.isEmpty else { return nil }
        return v
    }

    static func setActive(_ id: String?, lane: Lane, defaults: UserDefaults = .standard) {
        let k = key(lane)
        if let id, !id.isEmpty {
            defaults.set(id, forKey: k)
        } else {
            defaults.removeObject(forKey: k)
        }
    }
}
