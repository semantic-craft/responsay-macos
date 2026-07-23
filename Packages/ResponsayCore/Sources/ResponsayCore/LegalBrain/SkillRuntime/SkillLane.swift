import Foundation

/// Which 技能平台 lane a rewrite style pack is offered on. 听写技能 (`.dictation`) drives
/// 意图成稿 polish; 写作技能 (`.writing`) drives 划词改写.
///
/// The two lanes started life sharing one pack pool (2026-06-30 split decoupled *which pack is
/// active* per lane, not *which packs are offered*). That left the bundled 听写 flavors — whose
/// prompts are written for 语音转写 input — showing up on the 写作 lane, where the input is text
/// already on screen. Declaring the lane makes the pools disjoint.
///
/// A pack that declares nothing applies to **both** lanes, so imported third-party packs keep
/// working exactly as before without a schema migration.
public enum SkillLane: String, Codable, Sendable, CaseIterable {
    case dictation
    case writing
}
