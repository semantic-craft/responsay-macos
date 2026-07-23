import Foundation
import Observation

/// Central, observable record of which in-process local engines are resident
/// in memory right now, plus manual load/unload commands. Mirrors openless's
/// central engine cache (`cache.rs`): a single owner of residency state so the
/// Settings UI and the capture path agree on what is loaded.
///
/// Capture services register themselves at construction (`register(_:id:)`) and
/// report load/free transitions (`setResident(_:_:)`). The Settings screen
/// observes `isResident(_:)` / `isCapturing(_:)` and drives `preload(_:)` /
/// `unload(_:)`. Keep-alive *timing* still lives in the capture service; this
/// type only tracks residency and forwards commands.
@MainActor
@Observable
final class LocalEngineResidency {
    /// App-wide instance. Tests construct their own via `init()`.
    static let shared = LocalEngineResidency()

    /// Engine ids (== `LocalModelSpec.id`) whose runtime is in memory now.
    private(set) var residentIDs: Set<String> = []

    /// Live runtime controllers keyed by engine id. App-lifetime singletons owned by
    /// capture / OCR services; not observed (membership is fixed at launch).
    @ObservationIgnored private var controllers: [String: any LocalEngineResidencyControllable] = [:]

    init() {}

    // MARK: - Registration & residency reporting (capture services)

    func register(_ controller: any LocalEngineResidencyControllable, id: String) {
        controllers[id] = controller
    }

    func setResident(_ id: String, _ resident: Bool) {
        if resident { residentIDs.insert(id) } else { residentIDs.remove(id) }
    }

    // MARK: - Observable reads (Settings)

    /// True when this engine has a controller that supports load/unload.
    func canControl(_ id: String) -> Bool { controllers[id] != nil }

    func isResident(_ id: String) -> Bool { residentIDs.contains(id) }

    /// True while a capture is in progress (UI disables "unload").
    func isCapturing(_ id: String) -> Bool { controllers[id]?.isCapturing ?? false }

    // MARK: - Commands (Settings)

    /// "Load now" — preload the engine into memory. Throws if the model isn't
    /// installed or the recognizer fails to build.
    func preload(_ id: String) throws {
        try controllers[id]?.preloadEngine()
    }

    /// openless-style prewarm-on-select: load the engine off the main thread so the first
    /// capture finds it resident (LATENCY-MODELLOAD-001). Best-effort; no-op if not controllable.
    func preloadInBackground(_ id: String) {
        controllers[id]?.preloadEngineInBackground()
    }

    /// "Unload now" — free the engine immediately; ignored mid-capture.
    func unload(_ id: String) {
        guard let controller = controllers[id], !controller.isCapturing else { return }
        controller.unloadEngine()
    }
}

/// What a capture service exposes so `LocalEngineResidency` can preload / unload
/// its recognizer and know whether it is currently busy.
@MainActor
protocol LocalEngineResidencyControllable: AnyObject {
    var isCapturing: Bool { get }
    func preloadEngine() throws
    func preloadEngineInBackground()
    func unloadEngine()
}
