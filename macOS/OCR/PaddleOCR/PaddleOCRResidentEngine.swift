import Foundation
import OSLog
import ResponsayCore

@MainActor
final class PaddleOCRResidentEngine: LocalEngineResidencyControllable, @unchecked Sendable {
    static let shared = PaddleOCRResidentEngine()

    private let spec: LocalModelSpec
    private let residency: LocalEngineResidency
    private let makeProvider: @Sendable () throws -> any OCRProvider
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "paddleocr-residency")

    private var provider: (any OCRProvider)?
    private var loadTask: Task<any OCRProvider, Error>?
    private var releaseTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var registered = false
    private(set) var isCapturing = false

    init(
        spec: LocalModelSpec = LocalModelRegistry.defaultOCR,
        residency: LocalEngineResidency = .shared,
        makeProvider: @escaping @Sendable () throws -> any OCRProvider = {
            try PaddleOCRProvider(modelDir: LocalModelRegistry.defaultOCR.storagePath)
        }
    ) {
        self.spec = spec
        self.residency = residency
        self.makeProvider = makeProvider
    }

    func registerIfNeeded() {
        guard !registered else { return }
        residency.register(self, id: spec.id)
        registered = true
    }

    func beginRecognition() async throws -> any OCRProvider {
        registerIfNeeded()
        releaseTask?.cancel()
        releaseTask = nil
        isCapturing = true
        do {
            return try await providerAsync()
        } catch {
            isCapturing = false
            throw error
        }
    }

    func finishRecognition() {
        isCapturing = false
        scheduleRelease()
    }

    func preloadEngine() throws {
        registerIfNeeded()
        guard spec.isInstalled else { throw notInstalledError() }
        releaseTask?.cancel()
        releaseTask = nil
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        if provider == nil { setProvider(try makeProvider()) }
        if case .minutes = EngineKeepAlive(raw: keepLoadedRaw) { scheduleRelease() }
    }

    func preloadEngineInBackground() {
        registerIfNeeded()
        guard spec.isInstalled, provider == nil, loadTask == nil, !isCapturing else { return }
        let generation = nextLoadGeneration()
        let makeProvider = makeProvider
        let task = Task.detached(priority: .utility) { try makeProvider() }
        loadTask = task
        Task {
            do {
                let built = try await task.value
                finishBackgroundPreload(built, generation: generation)
            } catch {
                if generation == loadGeneration { loadTask = nil }
                log.info("background preload failed for \(self.spec.id, privacy: .public)")
            }
        }
    }

    func unloadEngine() {
        registerIfNeeded()
        guard !isCapturing else { return }
        releaseTask?.cancel()
        releaseTask = nil
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        setProvider(nil)
    }

    private func providerAsync() async throws -> any OCRProvider {
        guard spec.isInstalled else { throw notInstalledError() }
        if let provider { return provider }
        if let loadTask { return try await loadTask.value }

        let generation = nextLoadGeneration()
        let makeProvider = makeProvider
        let task = Task.detached(priority: .utility) { try makeProvider() }
        loadTask = task
        do {
            let built = try await task.value
            guard generation == loadGeneration else { return built }
            loadTask = nil
            setProvider(built)
            return built
        } catch {
            if generation == loadGeneration { loadTask = nil }
            throw error
        }
    }

    private func finishBackgroundPreload(_ built: any OCRProvider, generation: Int) {
        guard generation == loadGeneration, provider == nil, !isCapturing else { return }
        loadTask = nil
        setProvider(built)
        if case .minutes = EngineKeepAlive(raw: keepLoadedRaw) { scheduleRelease() }
    }

    private func scheduleRelease() {
        releaseTask?.cancel()
        releaseTask = nil
        guard let idle = EngineKeepAlive(raw: keepLoadedRaw).idleNanoseconds else { return }
        if idle == 0 {
            setProvider(nil)
            return
        }
        releaseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: idle)
            guard !Task.isCancelled else { return }
            if self?.isCapturing == false { self?.setProvider(nil) }
        }
    }

    private func setProvider(_ value: (any OCRProvider)?) {
        provider = value
        residency.setResident(spec.id, value != nil)
    }

    private func nextLoadGeneration() -> Int {
        loadGeneration += 1
        return loadGeneration
    }

    private func notInstalledError() -> OCRError {
        .recognitionFailed("\(spec.displayName) 模型未安装。请到 设置 › 本地模型 下载后再使用。")
    }

    private var keepLoadedRaw: String {
        UserDefaults.standard.string(forKey: "localEngineTTL") ?? "5"
    }
}
