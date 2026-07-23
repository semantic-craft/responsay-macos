import Foundation

/// Why a verified result could not be committed to its original target, so the transaction falls
/// back to a single safe copy instead of inserting into the wrong place (#560).
public enum TargetDriftReason: String, Sendable, Equatable {
    /// The frontmost app (or its process) is not the one capture started in.
    case appChanged
    /// Same app, but a different window / scene now has focus.
    case windowChanged
    /// The focused element can no longer receive text.
    case targetNotEditable
    /// No target could be read at commit time.
    case targetVanished
    /// No identifiable target existed at capture start (e.g. cursor outside any field).
    case identityUnknown
}

/// The commit decision for a verified final: insert into the bound target, or degrade to one safe
/// copy because the target drifted. There is no third "insert anyway" option (#560 铁律).
public enum InsertionCommitDecision: Sendable, Equatable {
    case insert
    case safeCopy(TargetDriftReason)
}
