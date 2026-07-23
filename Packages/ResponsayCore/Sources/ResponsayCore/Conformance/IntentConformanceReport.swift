import Foundation

/// #567 — the machine-readable conformance report (AC / Testing gate output). Aggregates results by
/// corpus version / provider-model / route / stage. CONTENT-FREE by construction: every field is a
/// count, rate, enum label, or bool — never a transcript, a key, a side note, entity evidence, full
/// context, or a provider raw response (AC12). `generatedAtEpochMs` is caller-supplied so the type
/// stays clock-free and deterministic in tests and scripts.
public struct IntentConformanceReport: Codable, Sendable, Equatable {
    public let corpusVersion: Int
    public let generatedAtEpochMs: Int
    public let corpus: [CategorySummary]
    public let contract: [ProviderSummary]
    /// nil ⇒ the warm-cloud latency gate did NOT run (no on-device samples yet — #568).
    public let latency: LatencySummary?
    public let coldLocalLatency: StageLatency?
    public let privacy: [Check]
    public let badResponseMatrix: [Check]

    public init(
        corpusVersion: Int,
        generatedAtEpochMs: Int,
        corpus: [CategorySummary] = [],
        contract: [ProviderSummary] = [],
        latency: LatencySummary? = nil,
        coldLocalLatency: StageLatency? = nil,
        privacy: [Check] = [],
        badResponseMatrix: [Check] = []
    ) {
        self.corpusVersion = corpusVersion
        self.generatedAtEpochMs = generatedAtEpochMs
        self.corpus = corpus
        self.contract = contract
        self.latency = latency
        self.coldLocalLatency = coldLocalLatency
        self.privacy = privacy
        self.badResponseMatrix = badResponseMatrix
    }

    public struct CategorySummary: Codable, Sendable, Equatable {
        public let category: String
        public let total: Int
        public let autoCorrectOrSafeReview: Int
        public let wrongAutoInsert: Int
        public init(category: String, total: Int, autoCorrectOrSafeReview: Int, wrongAutoInsert: Int) {
            self.category = category
            self.total = total
            self.autoCorrectOrSafeReview = autoCorrectOrSafeReview
            self.wrongAutoInsert = wrongAutoInsert
        }
    }

    public struct ProviderSummary: Codable, Sendable, Equatable {
        public let providerModel: String
        public let route: String            // cloud | local
        public let total: Int
        public let insertable: Int
        public let needsReview: Int
        public let safeUnavailable: Int
        public let structuralValidRate: Double
        public let passed: Bool
        /// false ⇒ NOT RUN (no live credentials) — surfaced explicitly, never a faked pass.
        public let ranLive: Bool

        public init(
            providerModel: String, route: String, tally: IntentProviderContractRunner.Tally,
            passed: Bool, ranLive: Bool
        ) {
            self.providerModel = providerModel
            self.route = route
            self.total = tally.total
            self.insertable = tally.insertable
            self.needsReview = tally.needsReview
            self.safeUnavailable = tally.safeUnavailable
            self.structuralValidRate = tally.structuralValidRate
            self.passed = passed
            self.ranLive = ranLive
        }
    }

    public struct StageLatency: Codable, Sendable, Equatable {
        public let p50Ms: Double?
        public let p95Ms: Double?
        public init(p50Ms: Double?, p95Ms: Double?) { self.p50Ms = p50Ms; self.p95Ms = p95Ms }
    }

    public struct LatencySummary: Codable, Sendable, Equatable {
        public let route: String
        public let sampleCount: Int
        public let p50Ms: Double?
        public let p95Ms: Double?
        public let polishedBaselineP95Ms: Double
        public let regression: Double?
        public let allSafetyStagesPresent: Bool
        public let passed: Bool
        /// false ⇒ NOT RUN (no on-device warm-cloud samples yet — #568).
        public let ranLive: Bool
        public let stagePercentilesMs: [String: StageLatency]

        public init(route: String, verdict: IntentLatencyGate.Verdict, ranLive: Bool) {
            self.route = route
            self.sampleCount = verdict.sampleCount
            self.p50Ms = verdict.p50Ms
            self.p95Ms = verdict.p95Ms
            self.polishedBaselineP95Ms = verdict.polishedBaselineP95Ms
            self.regression = verdict.regression
            self.allSafetyStagesPresent = verdict.allSafetyStagesPresent
            self.passed = verdict.passed
            self.ranLive = ranLive
            self.stagePercentilesMs = verdict.stagePercentilesMs.mapValues {
                StageLatency(p50Ms: $0.p50Ms, p95Ms: $0.p95Ms)
            }
        }
    }

    public struct Check: Codable, Sendable, Equatable {
        public let name: String
        public let passed: Bool
        public init(name: String, passed: Bool) { self.name = name; self.passed = passed }
    }

    /// Deterministic JSON (sorted keys) for a stable artifact a script or CI can diff.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }
}
