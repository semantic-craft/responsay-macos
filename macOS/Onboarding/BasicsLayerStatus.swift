import Foundation

/// 280 — pure aggregate of the two base-layer downloads (SenseVoice + Kokoro)
/// for the onboarding step: one progress story out of N independent manager
/// states. Unit-testable; the step view only renders this.
struct BasicsLayerStatus: Equatable {
    let allInstalled: Bool
    let anyBusy: Bool
    let firstFailure: String?
    /// 0…1 across all models — installed counts as 1, not-started as 0.
    let fraction: Double

    init(states: [LocalModelDownloadManager.State]) {
        guard !states.isEmpty else {
            allInstalled = false; anyBusy = false; firstFailure = nil; fraction = 0
            return
        }
        allInstalled = states.allSatisfy { $0 == .installed }
        anyBusy = states.contains { state in
            switch state {
            case .downloading, .verifying, .extracting, .checking: true
            default: false
            }
        }
        firstFailure = states.compactMap { state -> String? in
            if case let .failed(message) = state { return message }
            return nil
        }.first
        fraction = states.map { state -> Double in
            switch state {
            case .installed: 1
            case .downloading(let f): f
            case .verifying, .extracting: 0.97   // past transfer, finishing up
            case .checking, .notInstalled, .failed: 0
            }
        }.reduce(0, +) / Double(states.count)
    }
}
