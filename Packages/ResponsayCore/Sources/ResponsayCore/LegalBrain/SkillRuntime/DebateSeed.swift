import Foundation

/// Builds the grounded context handed to a 对抗 session when the user continues from a skill's
/// result card. The stance directives all say「针对上面的论证 / 上面的方案」, so that thing has to
/// actually be in the context — otherwise the first 加压 turn argues with nothing.
///
/// Composed from what the skill already produced (its summary + any prose it offered for
/// insertion) rather than re-sending the raw selection, so the 对抗 starts from the analysis the
/// user just read on screen. Pure, so the composition is testable without a live skill run.
public enum DebateSeed {

    public static func subject(from response: LegalSkillResponse) -> String {
        var parts: [String] = []
        let summary = response.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { parts.append(summary) }
        for insertable in response.insertables {
            let text = insertable.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { parts.append(text) }
        }
        return parts.joined(separator: "\n\n")
    }
}
