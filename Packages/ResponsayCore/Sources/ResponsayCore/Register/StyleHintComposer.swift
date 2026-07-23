import Foundation

/// Style learning (P1): composes the polish `styleHint` from the per-app register hint
/// (`RegisterPromptHint`) and the learned per-user style descriptor. Both land in the same
/// styleHint slot, AFTER the faithfulness red lines, so each only nudges 语体/措辞.
public enum StyleHintComposer {
    public static func compose(register: String?, personalStyle: String?) -> String? {
        let style = personalStyle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let styleBlock = (style?.isEmpty == false) ? """
        贴合用户个人表达风格（只调措辞贴近其习惯，永远服从上方红线：不增删用户没说的内容、不改其立场或确定性）：
        - \(style!)
        """ : nil

        return [register, styleBlock]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .nonEmptyOrNil
    }
}

private extension String {
    var nonEmptyOrNil: String? { isEmpty ? nil : self }
}
