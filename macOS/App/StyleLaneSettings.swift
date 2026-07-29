import Foundation
import ResponsayCore

/// The built-in ways to run 意图成稿. They are product presets in 改写设置, not installable
/// capabilities in 技能平台. The stored values remain the existing style-pack ids so current users
/// keep their selection and the runtime prompt path stays unchanged.
enum DictationDraftPreset: CaseIterable, Hashable {
    case smartCleanup
    case clearStructure
    case formalExpression

    var styleID: String? {
        switch self {
        case .smartCleanup: nil
        case .clearStructure: "style.clear_structure.cn"
        case .formalExpression: "style.formal_expression.cn"
        }
    }

    var title: String {
        switch self {
        case .smartCleanup: "智能整理"
        case .clearStructure: "清晰结构"
        case .formalExpression: "正式表达"
        }
    }

    var subtitle: String {
        switch self {
        case .smartCleanup: "默认"
        case .clearStructure: "多事项分点"
        case .formalExpression: "商务书面"
        }
    }

    func activate(defaults: UserDefaults = .standard) {
        StyleLaneSettings.setActive(styleID, lane: .dictation, defaults: defaults)
    }

    func matches(activeStyleID: String?) -> Bool {
        switch self {
        case .smartCleanup:
            activeStyleID == nil || activeStyleID == SkillCategorizer.lightPolishSkillID
        case .clearStructure, .formalExpression:
            activeStyleID == styleID
        }
    }

    static func contains(styleID: String?) -> Bool {
        allCases.contains { $0.matches(activeStyleID: styleID) }
    }
}

/// Two independent style lanes. 听写成稿方式 / imported styles (`.dictation`) drive 意图成稿
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
