import Foundation

// MARK: - 192 Legal insert mode (tracked-changes vs replace / append)
//
// Decides how a legal draft is written back to the writing surface: 改痕 (tracked-changes)
// where the host supports it (Word / WPS / Pages), else 整段替换 (a selection) or 追加 (append).
// `[待核]` tags are preserved in every mode. The ACTUAL host insertion (Word change-tracking
// via AX/automation, CGEvent) is macOS + real-host (HITL — simulator/build is not enough); this
// core is platform-agnostic and fully testable. Foundation-only.

public enum LegalInsertMode: String, Codable, Sendable, Equatable {
    case trackedChanges    // 改痕:host records the insertion as a tracked change
    case replaceSelection  // 整段替换选区
    case appendAfter       // 追加在选区/光标之后
    case copyOnly          // 不可插入 → 仅复制
}

/// What the host editor can do — detected by the macOS layer (here: data + an app-name
/// heuristic so the core stays testable; the macOS layer refines it with AX where possible).
public struct HostInsertCapability: Sendable, Equatable {
    public let isEditable: Bool
    public let hasSelection: Bool
    public let supportsTrackedChanges: Bool

    public init(isEditable: Bool, hasSelection: Bool, supportsTrackedChanges: Bool) {
        self.isEditable = isEditable
        self.hasSelection = hasSelection
        self.supportsTrackedChanges = supportsTrackedChanges
    }

    /// Rich editors that support 改痕 (conservative: unknown host → false).
    public static let trackedChangesApps: Set<String> = ["Microsoft Word", "WPS Office", "wpsoffice", "Pages"]

    /// Heuristic capability from an app name.
    public static func forApp(_ appName: String?, isEditable: Bool = true, hasSelection: Bool) -> HostInsertCapability {
        let supports = appName.map { name in
            trackedChangesApps.contains { name.localizedCaseInsensitiveContains($0) }
        } ?? false
        return HostInsertCapability(isEditable: isEditable, hasSelection: hasSelection, supportsTrackedChanges: supports)
    }
}

public enum LegalInsertPreference: String, Codable, Sendable {
    case trackedWhenAvailable    // default: prefer 改痕 in rich editors
    case alwaysReplaceOrAppend   // user opted out of tracked-changes
}

/// The resolved plan: which mode + the final text to write (with `[待核]` preserved).
public struct LegalInsertPlan: Sendable, Equatable {
    public let mode: LegalInsertMode
    public let text: String
    public init(mode: LegalInsertMode, text: String) { self.mode = mode; self.text = text }
}

public struct LegalInsertModeResolver: Sendable {
    private let tagger: VerificationPostProcessor

    public init(tagger: VerificationPostProcessor = VerificationPostProcessor()) { self.tagger = tagger }

    /// Pick the mode (capability + preference) and produce the final, `[待核]`-preserving text.
    public func resolve(
        text: String,
        capability: HostInsertCapability,
        preference: LegalInsertPreference = .trackedWhenAvailable
    ) -> LegalInsertPlan {
        let finalText = tagger.ensureTags(in: text)   // keep [待核] on inserted body, every mode
        let mode: LegalInsertMode
        if !capability.isEditable {
            mode = .copyOnly
        } else if preference == .trackedWhenAvailable, capability.supportsTrackedChanges {
            mode = .trackedChanges
        } else if capability.hasSelection {
            mode = .replaceSelection
        } else {
            mode = .appendAfter
        }
        return LegalInsertPlan(mode: mode, text: finalText)
    }
}

/// The macOS-side executor of an insert plan (Word change-tracking / CGEvent). Implemented in
/// the app layer; **real-host verification is HITL** (board rule: simulator/build success is not
/// enough — verify in Word/WPS on a real Mac). The core never imports AX/CGEvent.
public protocol LegalTextInserting: Sendable {
    func apply(_ plan: LegalInsertPlan) throws
}
