import Foundation

public protocol CaptureStore: Sendable {
    func save(_ item: CaptureItem) throws
    func recent(_ limit: Int) throws -> [CaptureItem]
    func overviewMetrics(
        now: Date,
        calendar: Calendar,
        status: ProviderStatusSummary,
        typingCharsPerSecond: Double
    ) throws -> OverviewMetrics
    /// Remove one capture by id (History 删除). Default no-op so test doubles
    /// and minimal stores needn't implement it.
    func delete(id: UUID) throws
    /// Remove every capture (History 清空). Default no-op.
    func deleteAll() throws
}

public extension CaptureStore {
    func overviewMetrics(
        now: Date,
        calendar: Calendar = .current,
        status: ProviderStatusSummary = .unknown,
        typingCharsPerSecond: Double = OverviewMetricsBuilder.defaultTypingCharsPerSecond
    ) throws -> OverviewMetrics {
        OverviewMetricsBuilder().build(
            from: try recent(Int.max),
            now: now,
            calendar: calendar,
            status: status,
            typingCharsPerSecond: typingCharsPerSecond)
    }

    func delete(id: UUID) throws {}
    func deleteAll() throws {}
}

public extension Notification.Name {
    /// Content-free, process-local invalidation for Overview usage metrics.
    static let captureStoreDidChange = Notification.Name("captureStoreDidChange")
}

/// M1 极简实现:整本错题以 JSON 数组存单文件。
public struct FileCaptureStore: CaptureStore {
    let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    private func loadAll() throws -> [CaptureItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([CaptureItem].self, from: data)
    }

    public func save(_ item: CaptureItem) throws {
        var all = try loadAll()
        all.append(item)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(all)
        try data.write(to: fileURL, options: .atomic)
        NotificationCenter.default.post(name: .captureStoreDidChange, object: nil)
    }

    public func recent(_ limit: Int) throws -> [CaptureItem] {
        try loadAll().sorted { $0.createdAt > $1.createdAt }.prefix(limit).map { $0 }
    }

    public func overviewMetrics(
        now: Date,
        calendar: Calendar,
        status: ProviderStatusSummary,
        typingCharsPerSecond: Double
    ) throws -> OverviewMetrics {
        OverviewMetricsBuilder().build(
            from: try loadAll(),
            now: now,
            calendar: calendar,
            status: status,
            typingCharsPerSecond: typingCharsPerSecond)
    }

    public func delete(id: UUID) throws {
        let remaining = try loadAll().filter { $0.id != id }
        let data = try JSONEncoder().encode(remaining)
        try data.write(to: fileURL, options: .atomic)
        NotificationCenter.default.post(name: .captureStoreDidChange, object: nil)
    }

    public func deleteAll() throws {
        let data = try JSONEncoder().encode([CaptureItem]())
        try data.write(to: fileURL, options: .atomic)
        NotificationCenter.default.post(name: .captureStoreDidChange, object: nil)
    }
}

extension CaptureStore where Self == FileCaptureStore {
    /// 默认落 Application Support/Responsay/captures.json
    public static func defaultStore() -> FileCaptureStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileCaptureStore(fileURL: base
            .appendingPathComponent(AppBrand.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("captures.json"))
    }
}
