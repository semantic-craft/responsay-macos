import Foundation

/// JSON-Schema payloads the LLM emits for structured legal-skill output. The labor /
/// private-lending calculator payloads were removed with the native calculators (2026-06-14);
/// only the fact-check (deep-link) payload remains, consumed by `FactCheckDeepLinkEngine`.
public enum LegalCalculatorPayloads {

    // MARK: - Fact Check Verification Payloads

    /// The standardized payload for Fact Check extraction (deep link mode).
    public struct VerificationFactCheckPayload: Codable, Equatable, Sendable {

        public enum TargetType: String, Codable, Sendable {
            case law
            case caseLaw = "case"
            case paper
        }

        public struct VerificationTarget: Codable, Equatable, Sendable {
            /// "law" or "case"
            public let type: TargetType

            /// For law: statute name & article number (e.g. "民法典 第一千零二十四条").
            /// For case: exact case number (e.g. "(2021)最高法民再1号").
            public let keywords: String?

            /// For case/law where keywords are unknown, a chunk of facts (100-800 words).
            public let semanticText: String?

            /// The original sentence from the user's text that triggered this verification.
            public let originalText: String

            public init(type: TargetType, keywords: String?, semanticText: String?, originalText: String) {
                self.type = type
                self.keywords = keywords
                self.semanticText = semanticText
                self.originalText = originalText
            }
        }

        public let targets: [VerificationTarget]

        public init(targets: [VerificationTarget]) {
            self.targets = targets
        }
    }
}
