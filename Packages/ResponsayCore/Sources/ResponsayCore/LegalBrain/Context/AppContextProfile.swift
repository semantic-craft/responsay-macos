import Foundation

/// App category — the cheapest, most stable scene signal (issue 114). New enum,
/// no conflict with built types.
public enum AppCategory: String, Codable, Sendable, CaseIterable {
    case wordProcessor
    case browser
    case noteTaking
    case collaboration
    case messaging
    case codeEditor
    case unknown
}

/// The foreground app mapped to a scene prior. `legalScenePriors` use the
/// **built** `LegalScene`.
public struct AppContextProfile: Codable, Sendable, Equatable {
    public let bundleIdentifier: String?
    public let appName: String?
    public let appCategory: AppCategory
    public let legalScenePriors: [LegalScenePrior]

    public init(
        bundleIdentifier: String?,
        appName: String?,
        appCategory: AppCategory,
        legalScenePriors: [LegalScenePrior] = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.appCategory = appCategory
        self.legalScenePriors = legalScenePriors
    }

    public static let unknown = AppContextProfile(
        bundleIdentifier: nil, appName: nil, appCategory: .unknown, legalScenePriors: []
    )
}

/// Maps the foreground app (from `ExpressionContext`) to an `AppContextProfile`.
/// v0 uses an in-code table (a builder-editable `AppContextProfiles.json` resource
/// is the follow-up); no new macOS read logic — it only reads existing fields.
public struct AppContextProfiler: Sendable {
    public init() {}

    public func profile(_ context: ExpressionContext) -> AppContextProfile {
        let bundle = context.bundleIdentifier?.lowercased()
        let name = context.appName

        if let bundle, let entry = Self.table.first(where: { bundle == $0.bundleID || bundle.contains($0.match) }) {
            return AppContextProfile(bundleIdentifier: context.bundleIdentifier, appName: name,
                                     appCategory: entry.category, legalScenePriors: entry.priors)
        }
        if let name, let entry = Self.table.first(where: { name.lowercased().contains($0.match) }) {
            return AppContextProfile(bundleIdentifier: context.bundleIdentifier, appName: name,
                                     appCategory: entry.category, legalScenePriors: entry.priors)
        }
        return AppContextProfile(bundleIdentifier: context.bundleIdentifier, appName: name,
                                 appCategory: .unknown, legalScenePriors: [])
    }

    private struct Entry {
        let bundleID: String
        let match: String
        let category: AppCategory
        let priors: [LegalScenePrior]
    }

    private static let table: [Entry] = [
        Entry(bundleID: "com.microsoft.word", match: "word", category: .wordProcessor, priors: [
            LegalScenePrior(scene: .litigation, weight: 0.5, reason: "Word 常用于诉讼文书"),
            LegalScenePrior(scene: .academicWriting, weight: 0.3, reason: "Word 常用于论文"),
            LegalScenePrior(scene: .contract, weight: 0.3, reason: "Word 常用于合同"),
        ]),
        Entry(bundleID: "com.kingsoft.wpsoffice", match: "wps", category: .wordProcessor, priors: [
            LegalScenePrior(scene: .litigation, weight: 0.5, reason: "WPS 文书"),
            LegalScenePrior(scene: .contract, weight: 0.3, reason: "WPS 合同"),
        ]),
        Entry(bundleID: "com.apple.pages", match: "pages", category: .wordProcessor, priors: [
            LegalScenePrior(scene: .academicWriting, weight: 0.4, reason: "Pages 写作"),
        ]),
        Entry(bundleID: "md.obsidian", match: "obsidian", category: .noteTaking, priors: [
            LegalScenePrior(scene: .academicWriting, weight: 0.4, reason: "Obsidian 学术笔记"),
        ]),
        Entry(bundleID: "com.bytedance.feishu", match: "feishu", category: .collaboration, priors: [
            LegalScenePrior(scene: .privacy, weight: 0.4, reason: "飞书 PRD / 隐私评审"),
            LegalScenePrior(scene: .productCompliance, weight: 0.4, reason: "飞书 产品合规"),
        ]),
        Entry(bundleID: "notion.id", match: "notion", category: .collaboration, priors: [
            LegalScenePrior(scene: .productCompliance, weight: 0.3, reason: "Notion 协作"),
        ]),
        Entry(bundleID: "com.google.chrome", match: "chrome", category: .browser, priors: []),
        Entry(bundleID: "com.apple.safari", match: "safari", category: .browser, priors: []),
        Entry(bundleID: "com.tencent.xinwechat", match: "wechat", category: .messaging, priors: []),
        Entry(bundleID: "com.microsoft.vscode", match: "vscode", category: .codeEditor, priors: []),
    ]
}
