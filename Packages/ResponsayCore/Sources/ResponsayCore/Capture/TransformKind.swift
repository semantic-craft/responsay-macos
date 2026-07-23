import Foundation

public enum TransformKind: String, Codable, Sendable, Equatable {
    case none
    case sameLanguagePolish
    case intentCompilation
    case intentToEnglish
    case coachOnly
    case prosodyOnly
    case practiceSeed
    case rewriteSelection
    case translateSelection
    /// Pure dispatch sentinel (105): the legal hotkey/mode routed to the candidate
    /// palette. Carries no legal logic — `LegalSkillRuntime` produces the cards.
    case legalSkillPalette
}
