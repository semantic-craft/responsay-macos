import Foundation

public enum HotwordLearningSource: String, Sendable, Codable, Equatable, CaseIterable {
    case localRules
    case localModel
    // ponytail: 云端智能 tier was cut, but this Codable case stays so old learning-history
    // records tagged cloudBYOK still decode. No live tier produces it anymore.
    case cloudBYOK
    /// 518 — the capsule「纠正并学习」explicit user correction. Codable note: an app DOWNGRADE
    /// older than this case fails to decode a ledger containing it (records() returns []) —
    /// accepted per the issue; upgrades and fresh installs are unaffected.
    case manual

    public var displayName: String {
        switch self {
        case .localRules: return "本机规则"
        case .localModel: return "本地模型"
        case .cloudBYOK: return "云端智能"
        case .manual: return "手动纠正"
        }
    }
}
