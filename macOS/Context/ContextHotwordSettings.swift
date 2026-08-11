import AppKit
import Foundation
import ResponsayCore

enum ContextHotwordSettings {
    static let defaultsKey = "contextHotwords"
    static let autoDefaultsKey = "contextAutoHotwords"
    static let autoMetadataDefaultsKey = "contextAutoHotwordMetadata"
    static let removedDefaultsKey = "didRemoveDefaultHotwords"

    /// Scene-aware biasing (P0a). Both learn-time (`proposal.appName` = bundleID) and ASR-time
    /// (frontmost bundleID) classify through the same substring table, so the two sides agree.
    private static let registerClassifier = RegisterTierClassifier()

    /// The user's own free-text terms (the Settings editor binds to this raw string).
    static func hotwords(defaults: UserDefaults = .standard) -> [String] {
        parse(defaults.string(forKey: defaultsKey) ?? "")
    }

    /// One-time cleanup (2026-06-29): the app used to fold the built-in example terms
    /// (`HotwordStore.defaultSeeds` — CLSCI / SSRN / Westlaw / arXiv / …) into every user's manual
    /// dictionary. That's retired by product decision — we ship NO default hotwords. This strips any
    /// of those legacy seed terms still sitting in the manual dictionary from the old fold-in, so they
    /// stop biasing ASR (and stop showing up echoed on near-empty captures). Runs once
    /// (`removedDefaultsKey`); auto-learned and hand-added terms are untouched, and a former seed the
    /// user has since re-typed survives a later launch. Call at app launch.
    static func removeSeededDefaultsIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: removedDefaultsKey) else { return }
        let legacySeeds = Set(HotwordCategory.allCases.flatMap { HotwordStore.defaultSeeds[$0] ?? [] })
        let current = hotwords(defaults: defaults)
        let cleaned = current.filter { !legacySeeds.contains($0) }
        if cleaned.count != current.count {
            defaults.set(cleaned.joined(separator: ", "), forKey: defaultsKey)
            refreshProfileSoon(defaults: defaults)
        }
        defaults.set(true, forKey: removedDefaultsKey)
    }

    /// Add a term (e.g. the current selection) to the manual recognition dictionary.
    /// User terms go first so they survive the per-request cap. Returns false when the
    /// term is empty or already present.
    @discardableResult
    static func addManual(_ term: String, defaults: UserDefaults = .standard) -> Bool {
        let cleaned = String(term.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !cleaned.isEmpty else { return false }
        var current = hotwords(defaults: defaults)
        guard !current.contains(cleaned) else { return false }
        current.insert(cleaned, at: 0)
        defaults.set(current.joined(separator: ", "), forKey: defaultsKey)
        refreshProfileSoon(defaults: defaults)
        return true
    }

    static func removeManual(_ term: String, defaults: UserDefaults = .standard) {
        let cleaned = cleanTerm(term)
        defaults.set(
            hotwords(defaults: defaults).filter { $0 != cleaned }.joined(separator: ", "),
            forKey: defaultsKey)
        refreshProfileSoon(defaults: defaults)
    }

    @discardableResult
    static func renameManual(
        _ oldTerm: String,
        to newTerm: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let oldCleaned = cleanTerm(oldTerm)
        let newCleaned = cleanTerm(newTerm)
        guard !oldCleaned.isEmpty, !newCleaned.isEmpty else { return false }
        var current = hotwords(defaults: defaults)
        guard let index = current.firstIndex(of: oldCleaned) else { return false }
        if oldCleaned == newCleaned { return true }
        guard !current.contains(newCleaned), !autoHotwords(defaults: defaults).contains(newCleaned) else {
            return false
        }
        current[index] = newCleaned
        defaults.set(current.joined(separator: ", "), forKey: defaultsKey)
        refreshProfileSoon(defaults: defaults)
        return true
    }

    static func autoHotwords(defaults: UserDefaults = .standard) -> [String] {
        parse(defaults.string(forKey: autoDefaultsKey) ?? "")
    }

    /// Add an auto-learned term (the correction flywheel, 434) to the auto recognition
    /// dictionary. Returns false when empty, or already present as a manual OR auto term.
    /// Auto terms surface in `DictionarySettingsPane`, where the user can remove them — so the
    /// learning is always undoable (AC#3).
    @discardableResult
    static func addAuto(
        _ term: String,
        source: HotwordLearningSource = .localRules,
        reason: String = "",
        learnedAt: Date = Date(),
        confidence: Double? = nil,
        appName: String? = nil,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let cleaned = String(term.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !cleaned.isEmpty, !hotwords(defaults: defaults).contains(cleaned) else { return false }
        var current = autoHotwords(defaults: defaults)
        guard !current.contains(cleaned) else { return false }
        current.insert(cleaned, at: 0)
        defaults.set(current.joined(separator: ", "), forKey: autoDefaultsKey)
        var metadata = autoMetadata(defaults: defaults)
        metadata[cleaned] = AutoHotwordMetadata(
            source: source, reason: reason, learnedAt: learnedAt, confidence: confidence,
            scene: classifyScene(appName))
        saveAutoMetadata(metadata, defaults: defaults)
        refreshProfileSoon(defaults: defaults)
        return true
    }

    /// The learn-time scene (`RegisterTier` rawValue) for an app, or `nil` when unclassifiable
    /// (→ the term stays global). `appName` is a bundleID at the live call sites.
    private static func classifyScene(_ appName: String?) -> String? {
        guard let appName, !appName.isEmpty else { return nil }
        let tier = registerClassifier.tier(bundleID: appName, appName: appName)
        return tier == .neutral ? nil : tier.rawValue
    }

    /// Wipe every auto-learned term and its metadata (the 「清空学习记录」 reset). Manual terms
    /// (`defaultsKey`) are untouched — only the flywheel's own contributions are removed.
    static func clearAuto(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: autoDefaultsKey)
        defaults.removeObject(forKey: autoMetadataDefaultsKey)
        refreshProfileSoon(defaults: defaults)
    }

    static func removeAuto(_ term: String, defaults: UserDefaults = .standard) {
        let cleaned = cleanTerm(term)
        defaults.set(
            autoHotwords(defaults: defaults).filter { $0 != cleaned }.joined(separator: ", "),
            forKey: autoDefaultsKey)
        var metadata = autoMetadata(defaults: defaults)
        metadata.removeValue(forKey: cleaned)
        saveAutoMetadata(metadata, defaults: defaults)
        refreshProfileSoon(defaults: defaults)
    }

    @discardableResult
    static func renameAuto(
        _ oldTerm: String,
        to newTerm: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let oldCleaned = cleanTerm(oldTerm)
        let newCleaned = cleanTerm(newTerm)
        guard !oldCleaned.isEmpty, !newCleaned.isEmpty else { return false }
        var current = autoHotwords(defaults: defaults)
        guard let index = current.firstIndex(of: oldCleaned) else { return false }
        if oldCleaned == newCleaned { return true }
        guard !hotwords(defaults: defaults).contains(newCleaned), !current.contains(newCleaned) else {
            return false
        }
        current[index] = newCleaned
        defaults.set(current.joined(separator: ", "), forKey: autoDefaultsKey)
        var metadata = autoMetadata(defaults: defaults)
        if let existing = metadata.removeValue(forKey: oldCleaned) {
            metadata[newCleaned] = existing
            saveAutoMetadata(metadata, defaults: defaults)
        }
        refreshProfileSoon(defaults: defaults)
        return true
    }

    /// The **biasing set** (偏置集) for a request — the single entry point that replaces the old
    /// per-route facades (`activeHotwords` / `vocabularyHotwords` / `activeHotwordsByProvenance`).
    /// Builds the store once from UserDefaults; the Core seam (`HotwordBiasingSets`) owns the three
    /// subsets (vocabulary / weak-prompt / hard-match) and the hard-match `enforce`, with the
    /// confidence threshold and per-route caps baked in. See CONTEXT.md · Biasing set.
    /// Live entry point (all ASR call sites): scene = the frontmost app's register tier.
    static func biasingSets(defaults: UserDefaults = .standard) -> HotwordBiasingSets {
        biasingSets(defaults: defaults, currentScene: resolveCurrentScene())
    }

    /// 517 — the weak-prompt list the cloud ASR clients actually send: the dictionary weak prompt
    /// plus this capture's transient screen terms (`TransientScreenTerms`), dictionary first.
    /// Byte-identical to `biasingSets().weakPrompt` when the stash is empty (屏幕上下文 off /
    /// nothing harvested), so the OFF path sends exactly today's request. Read-only: never writes
    /// the dictionary or UserDefaults.
    static func asrWeakPrompt(
        defaults: UserDefaults = .standard,
        transientTerms: [String] = []
    ) -> [String] {
        biasingSets(defaults: defaults).weakPrompt(augmentedWith: transientTerms)
    }

    /// Stable local vocabulary used when binding a precompiled Qwen list. It intentionally excludes
    /// per-capture screen terms and scene suppression: either would make the durable snapshot vary
    /// with the frontmost app. The request path still applies both before choosing ID vs instant.
    static func qwenPersistentHotwords(defaults: UserDefaults = .standard) -> [String] {
        store(defaults: defaults)
            .biasingSets()
            .merging(profile: DictationLexicalProfileSettings.current(defaults: defaults))
            .weakPrompt
    }

    /// P0a — scene-aware biasing. `currentScene == nil` (unclassifiable app, or no scene given in a
    /// test) suppresses nothing, so behavior is byte-identical to pre-P0a whenever the scene is
    /// unknown. When both the current app and a learned term carry *different* register tiers, that
    /// term is dropped from this request's biasing (e.g. legal terms don't bias chat dictation).
    static func biasingSets(defaults: UserDefaults, currentScene: RegisterTier?) -> HotwordBiasingSets {
        let sets = store(defaults: defaults)
            .biasingSets()
            .merging(profile: DictationLexicalProfileSettings.current(defaults: defaults))
        let suppressed = suppressedAutoTerms(currentScene: currentScene, defaults: defaults)
        let pass: ([String]) -> [String] = { terms in
            suppressed.isEmpty ? terms : terms.filter { !suppressed.contains($0) }
        }
        let hardMatchUser = pass(sets.hardMatchUser)
        let currentTerms = Set(hardMatchUser)
        let liveAliases = AutoLearnHotwordHistorySettings.learnedAliases(defaults: defaults)
            .filter { currentTerms.contains($0.value) }
        var aliases = sets.learnedAliases.filter { currentTerms.contains($0.value) }
        aliases.merge(liveAliases) { _, live in live }
        return HotwordBiasingSets(
            weakPrompt: pass(sets.weakPrompt),
            hardMatchUser: hardMatchUser,
            hardMatchSeed: sets.hardMatchSeed,
            learnedAliases: aliases)
    }

    /// The frontmost app's register tier, or `nil` when unclassifiable (→ no scene filtering).
    /// ponytail: bundleID only, so chat/mail/document native tiers engage; browser-domain tiers
    /// (incl. legal *sites*) don't — auto-learn fires where you dictate (native apps), not while
    /// browsing, so this covers the realistic case. Upgrade path: pass the active-tab URL as
    /// `domain:` here and at learn time (CaptureGateContextReader already resolves it).
    static func resolveCurrentScene() -> RegisterTier? {
        let app = NSWorkspace.shared.frontmostApplication
        let tier = registerClassifier.tier(bundleID: app?.bundleIdentifier, appName: app?.localizedName)
        return tier == .neutral ? nil : tier
    }

    /// Auto-learned terms to drop for `currentScene`: scene-scoped terms whose tier differs from the
    /// current one. Manual terms are never here (always global). `currentScene == nil` → empty.
    static func suppressedAutoTerms(currentScene: RegisterTier?, defaults: UserDefaults = .standard) -> Set<String> {
        guard currentScene != nil else { return [] }
        let manual = Set(hotwords(defaults: defaults))
        var suppressed = Set<String>()
        for (term, meta) in autoMetadata(defaults: defaults) where !manual.contains(term) {
            let stored = meta.scene.flatMap(RegisterTier.init(rawValue:))
            if sceneSuppresses(stored: stored, current: currentScene) { suppressed.insert(term) }
        }
        return suppressed
    }

    /// Pure scene rule: suppress only when both sides are classified and differ.
    static func sceneSuppresses(stored: RegisterTier?, current: RegisterTier?) -> Bool {
        guard let stored, let current else { return false }
        return stored != current
    }

    static func store(defaults: UserDefaults = .standard) -> HotwordStore {
        let manual = hotwords(defaults: defaults)
        let manualSet = Set(manual)
        let metadata = autoMetadata(defaults: defaults)
        let auto = autoHotwords(defaults: defaults).filter { !manualSet.contains($0) }
        // No seed lane and no built-in defaults (retired 2026-06-29): the dictionary is exactly the
        // user's hand-added + auto-learned terms. `removeSeededDefaultsIfNeeded` strips any legacy
        // folded-in seeds once at launch.
        return HotwordStore(
            userTermEntries: manual.map { HotwordTerm(text: $0, source: .manual) }
                + auto.map {
                    let meta = metadata[$0]
                    return HotwordTerm(
                        text: $0,
                        source: .auto,
                        learnedSource: meta?.source,
                        learnedAt: meta?.learnedAt,
                        confidence: meta?.confidence)
                },
            seeds: [:])
    }

    static func autoMetadata(defaults: UserDefaults = .standard) -> [String: AutoHotwordMetadata] {
        guard let data = defaults.data(forKey: autoMetadataDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: AutoHotwordMetadata].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func parse(_ raw: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，、;\n\t")
        var seen = Set<String>()
        var output = [String]()

        for part in raw.components(separatedBy: separators) {
            let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !seen.contains(value) else { continue }
            output.append(String(value.prefix(80)))
            seen.insert(value)
            if output.count == 40 { break }
        }
        return output
    }

    private static func saveAutoMetadata(_ metadata: [String: AutoHotwordMetadata], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        defaults.set(data, forKey: autoMetadataDefaultsKey)
    }

    private static func cleanTerm(_ term: String) -> String {
        String(term.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }

    private static func refreshProfileSoon(defaults: UserDefaults) {
        guard defaults === UserDefaults.standard else { return }
        DictationLexicalProfileSettings.scheduleRefresh()
    }
}
