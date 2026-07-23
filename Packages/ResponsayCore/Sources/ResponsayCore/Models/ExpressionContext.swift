import Foundation

public struct ExpressionContext: Codable, Sendable, Equatable {
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var selectedText: String?
    public var textBeforeCursor: String?
    public var textAfterCursor: String?
    /// 508 — full current-page URL (capped). Screen-derived context: the caller populates it
    /// only when 屏幕上下文 is enabled, exactly like `visibleScreenText`. Feeds the LLM so output
    /// fits the page; also handed to skill routing as-is (no host reduction, no legal special-case).
    public var browserURL: String?
    /// 屏幕可见内容 — the recursively-collected visible on-screen text (`VisibleTextCollector`),
    /// attached only on the cloud path and only when 屏幕上下文 is enabled. Capped hard so a long
    /// page can't blow up the prompt.
    public var visibleScreenText: String?
    public var hotwords: [String]

    public init(
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        selectedText: String? = nil,
        textBeforeCursor: String? = nil,
        textAfterCursor: String? = nil,
        browserURL: String? = nil,
        visibleScreenText: String? = nil,
        hotwords: [String] = []
    ) {
        self.appName = Self.clean(appName, limit: 120)
        self.bundleIdentifier = Self.clean(bundleIdentifier, limit: 120)
        self.windowTitle = Self.clean(windowTitle, limit: 180)
        self.selectedText = Self.clean(selectedText, limit: 700)
        self.textBeforeCursor = Self.clean(textBeforeCursor, limit: 700)
        self.textAfterCursor = Self.clean(textAfterCursor, limit: 700)
        self.browserURL = Self.clean(browserURL, limit: 300)
        self.visibleScreenText = Self.clean(visibleScreenText, limit: 2000)
        self.hotwords = Self.cleanHotwords(hotwords)
    }

    public func withBrowserURL(_ browserURL: String?) -> ExpressionContext {
        var copy = self
        copy.browserURL = Self.clean(browserURL, limit: 300)
        return copy
    }

    public func withVisibleScreenText(_ text: String?) -> ExpressionContext {
        var copy = self
        copy.visibleScreenText = Self.clean(text, limit: 2000)
        return copy
    }

    public var isEmpty: Bool {
        appName == nil
            && bundleIdentifier == nil
            && windowTitle == nil
            && selectedText == nil
            && textBeforeCursor == nil
            && textAfterCursor == nil
            && browserURL == nil
            && visibleScreenText == nil
            && hotwords.isEmpty
    }

    var jsonObject: [String: Any] {
        var object = [String: Any]()
        if let appName { object["appName"] = appName }
        if let bundleIdentifier { object["bundleIdentifier"] = bundleIdentifier }
        if let windowTitle { object["windowTitle"] = windowTitle }
        if let selectedText { object["selectedText"] = selectedText }
        if let textBeforeCursor { object["textBeforeCursor"] = textBeforeCursor }
        if let textAfterCursor { object["textAfterCursor"] = textAfterCursor }
        if let browserURL { object["browserURL"] = browserURL }   // 508: full URL → LLM (gated upstream by 屏幕上下文)
        if !hotwords.isEmpty { object["hotwords"] = hotwords }
        return object
    }

    private static func clean(_ value: String?, limit: Int) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return String(raw.prefix(limit))
    }

    private static func cleanHotwords(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var cleaned = [String]()
        for value in values {
            guard let word = clean(value, limit: 80), !seen.contains(word) else { continue }
            cleaned.append(word)
            seen.insert(word)
            if cleaned.count == 40 { break }
        }
        return cleaned
    }
}
