import Foundation
import NaturalLanguage

/// Whether a learned hotword candidate is "specialized" enough to interrupt the user.
/// Drives the auto-learn tiering (PRD 2026-06-19 §3): specialized + high confidence → toast,
/// specialized + low/mid → pending, **ordinary → learn silently** (no toast). The default is
/// ordinary, i.e. "don't interrupt" — interruptions are the exception, not the rule.
public enum HotwordSensitivity: Sendable, Equatable {
    case ordinary
    case specialized(SpecializedReason)
}

public enum SpecializedReason: String, Sendable, Equatable, CaseIterable {
    case caseNumber          // 案号, e.g. （2023）京01民终1234号
    case legalGazetteer      // court name / statute abbreviation in the legal term list
    case personalName        // NER 人名（当事人）
    case organizationName    // NER 机构（法院 / 律所）
    case placeName           // NER 地名
}

/// Classifies one already-extracted hotword candidate. The case-number regex and the gazetteer
/// lookup are fully deterministic; the named-entity pass is a best-effort extra signal (it can be
/// toggled off for deterministic tests / headless runs). A missed "specialized" only costs an
/// interruption we skipped — never a wrong edit — so the rules lean conservative.
public struct HotwordSensitivityClassifier: Sendable {
    private let gazetteer: Set<String>
    private let useNamedEntityRecognition: Bool

    public init(
        gazetteer: Set<String> = HotwordSensitivityClassifier.legalSeedTerms,
        useNamedEntityRecognition: Bool = true
    ) {
        self.gazetteer = gazetteer
        self.useNamedEntityRecognition = useNamedEntityRecognition
    }

    public func classify(_ term: String) -> HotwordSensitivity {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .ordinary }

        if Self.isCaseNumber(trimmed) { return .specialized(.caseNumber) }
        if gazetteer.contains(trimmed) { return .specialized(.legalGazetteer) }
        if useNamedEntityRecognition, let reason = Self.namedEntityReason(trimmed) {
            return .specialized(reason)
        }
        return .ordinary
    }

    /// Interrupt-worthy? (toast at high confidence, pending otherwise; ordinary learns silently.)
    public func isSpecialized(_ term: String) -> Bool {
        if case .specialized = classify(term) { return true }
        return false
    }

    // MARK: - Case number (案号)

    // ponytail: deliberately loose — matches the common （YYYY）…号 shape. Refine as real 案号
    // formats surface; a miss just skips an interruption, it never causes a wrong edit.
    private static let caseNumberRegex = try! NSRegularExpression(
        pattern: "[（(]\\s*\\d{4}\\s*[）)].{0,40}?号$")

    static func isCaseNumber(_ term: String) -> Bool {
        let range = NSRange(term.startIndex..<term.endIndex, in: term)
        return caseNumberRegex.firstMatch(in: term, options: [], range: range) != nil
    }

    // MARK: - Named entity recognition (best-effort)

    static func namedEntityReason(_ term: String) -> SpecializedReason? {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = term
        var reason: SpecializedReason?
        tagger.enumerateTags(
            in: term.startIndex..<term.endIndex,
            unit: .word, scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, _ in
            if let tag {
                switch tag {
                case .personalName: reason = .personalName
                case .organizationName: reason = .organizationName
                case .placeName: reason = .placeName
                default: break
                }
            }
            return reason == nil   // stop at the first named-entity hit
        }
        return reason
    }

    // MARK: - Legal seed gazetteer

    /// Minimal seed set — grow over time (PRD §10 / open Q2). Exact-match membership only, so a
    /// plain `Set` is the right tool here; `NLGazetteer` is for tagging terms *within running text*,
    /// which is not what we do with an already-isolated candidate.
    public static let legalSeedTerms: Set<String> = [
        "民法典", "刑法", "民事诉讼法", "刑事诉讼法", "行政诉讼法", "公司法", "合同法", "物权法",
        "最高人民法院", "最高人民检察院", "知识产权法院", "互联网法院", "金融法院",
        "司法解释", "管辖权异议", "不当得利", "缔约过失", "善意取得", "法律拟制", "既判力",
    ]
}
