import Foundation
import Testing
@testable import ResponsayCore

/// #567 · S8 — the machine-readable conformance report is CONTENT-FREE (AC12) and never fakes a
/// live pass (AC11). The report aggregates counts / rates / labels only; no transcript, key, side
/// note, or provider raw response can appear in its JSON.
struct IntentConformanceReportTests {
    private static let base = Date(timeIntervalSince1970: 2_000_000)

    private static func trace(totalMs: Double) -> IntentLatencyTrace {
        func at(_ f: Double) -> Date { base.addingTimeInterval(totalMs * f / 1000) }
        var t = IntentLatencyTrace()
        t.mark(.stop, at: base); t.mark(.compile, at: at(0.4))
        t.mark(.planVerify, at: at(0.5)); t.mark(.sourceRender, at: at(0.6))
        t.mark(.optionalPolish, at: at(0.8)); t.mark(.postRenderGuard, at: at(0.9))
        t.mark(.visible, at: at(1.0))
        return t
    }

    /// A representative report assembled from real gate outputs (offline: gates ran, but not on a
    /// real device / live provider → ranLive false).
    private static func sampleReport() -> IntentConformanceReport {
        let tally = IntentProviderContractRunner.Tally(
            insertable: 99, needsReview: 1, safeUnavailable: 0, total: 100)
        let verdict = IntentLatencyGate.evaluate(
            warmCloud: [1400, 1500, 1600].map(trace(totalMs:)), polishedBaselineP95Ms: 2000)
        return IntentConformanceReport(
            corpusVersion: 1,
            generatedAtEpochMs: 1_700_000_000_000,
            corpus: [
                .init(category: "correctionNear", total: 2, autoCorrectOrSafeReview: 2, wrongAutoInsert: 0),
                .init(category: "sideNoteTrue", total: 2, autoCorrectOrSafeReview: 2, wrongAutoInsert: 0),
                .init(category: "ordinaryNegative", total: 2, autoCorrectOrSafeReview: 2, wrongAutoInsert: 0)
            ],
            contract: [
                .init(providerModel: "qwen/qwen-flash", route: "cloud", tally: tally, passed: true, ranLive: false),
                .init(providerModel: "ollama/qwen2.5", route: "local", tally: tally, passed: true, ranLive: false)
            ],
            latency: .init(route: "warmCloud", verdict: verdict, ranLive: false),
            coldLocalLatency: IntentLatencyGate.coldLocalReport([3000, 3500].map(trace(totalMs:)))
                .map { .init(p50Ms: $0.p50Ms, p95Ms: $0.p95Ms) },
            privacy: [
                .init(name: "screenContextOffZeroFields", passed: true),
                .init(name: "localRouteZeroCloud", passed: true),
                .init(name: "historyZeroRaw", passed: true),
                .init(name: "unconfirmedZeroLearning", passed: true)
            ],
            badResponseMatrix: [
                .init(name: "emptyResponse", passed: true),
                .init(name: "pureText", passed: true),
                .init(name: "cyclicSupersession", passed: true)
            ])
    }

    @Test func reportAggregatesByVersionProviderRouteAndStage() throws {
        let json = try String(data: Self.sampleReport().jsonData(), encoding: .utf8) ?? ""
        for key in ["corpusVersion", "providerModel", "route", "category", "stagePercentilesMs", "ranLive"] {
            #expect(json.contains(key), "report must expose \(key)")
        }
    }

    @Test func reportJSONCarriesNoUserTextKeyOrProviderRaw() throws {
        let json = try String(data: Self.sampleReport().jsonData(), encoding: .utf8) ?? ""
        // No transcript / side note / name / key material — the report is counts + labels only.
        for forbidden in ["周四开会", "贺正杰", "如何的何", "这句不用写", "私密", "sk-", "Bearer", "apiKey", "PaddleOCR"] {
            #expect(!json.contains(forbidden), "report must not contain \(forbidden)")
        }
    }

    @Test func notRunIsVisibleAndNeverFakedAsPassed() throws {
        let json = try String(data: Self.sampleReport().jsonData(), encoding: .utf8) ?? ""
        // Offline: the network / on-device gates are marked NOT RUN, distinct from a pass.
        #expect(json.contains("\"ranLive\" : false"))

        // A live-absent contract/latency summary is explicitly ranLive:false, not silently passed.
        let report = Self.sampleReport()
        #expect(report.contract.allSatisfy { $0.ranLive == false })
        #expect(report.latency?.ranLive == false)
    }

    @Test func reportRoundTripsThroughCodable() throws {
        let original = Self.sampleReport()
        let decoded = try JSONDecoder().decode(IntentConformanceReport.self, from: original.jsonData())
        #expect(decoded == original)
    }
}
