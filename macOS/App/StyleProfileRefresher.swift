import Foundation
import OSLog
import ResponsayCore

/// Style learning (P1): background distillation of the user's kept dictations into a style
/// descriptor. Triggered after dictations (auto, ≤ once/day) and by the「重新学习」button (force).
/// Reads recent 意图成稿 outputs from the capture store, distills via the configured LLM, caches.
@MainActor
enum StyleProfileRefresher {
    private static var inFlight = false
    private static let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "style-profile")

    /// Auto path: refresh iff enabled, not already fresh (<24h with a descriptor), and enough samples.
    /// `force` (the「重新学习」button) bypasses the enabled + staleness gates.
    static func scheduleIfNeeded(force: Bool = false, defaults: UserDefaults = .standard) {
        guard force || StyleProfileSettings.isEnabled(defaults: defaults) else { return }
        guard !inFlight else { return }
        if !force,
           let last = StyleProfileSettings.lastBuiltAt(defaults: defaults),
           Date().timeIntervalSince(last) < StyleProfileSettings.refreshInterval,
           StyleProfileSettings.hasLearned(defaults: defaults) {
            return   // recently built — nothing to do
        }
        let samples = recentDictationSamples(defaults: defaults)
        guard samples.count >= StyleProfileSettings.minSamples else {
            log.debug("Style refresh skipped: only \(samples.count, privacy: .public) samples")
            return
        }
        guard let endpoint = LLMEndpointResolver.resolveText(defaults: defaults) else {
            log.debug("Style refresh skipped: no text model configured")
            return
        }
        inFlight = true
        Task { @MainActor in
            defer { inFlight = false }
            do {
                let descriptor = try await StyleDistiller().distill(samples: samples, endpoint: endpoint)
                guard !descriptor.isEmpty else { return }
                StyleProfileSettings.setLearned(descriptor, at: Date(), defaults: defaults)
                log.info("Style descriptor refreshed (\(descriptor.count, privacy: .public) chars from \(samples.count, privacy: .public) samples)")
            } catch {
                log.error("Style distillation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Recent kept 意图成稿 outputs — the calibration target for "sounds like me".
    private static func recentDictationSamples(defaults: UserDefaults) -> [String] {
        guard let store = try? makeStore() else { return [] }
        let items = (try? store.recent(40)) ?? []
        return items
            .filter { $0.actionKind == .polish }
            .map { $0.idiomatic.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Same default store CaptureController uses (SQLite, file fallback).
    private static func makeStore() throws -> CaptureStore {
        if let sqlite = try? SQLiteReviewStore.defaultStore() {
            return ReviewCaptureStore(reviewStore: sqlite)
        }
        return FileCaptureStore.defaultStore()
    }
}
