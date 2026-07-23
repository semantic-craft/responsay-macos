import Foundation

/// 509 — explicit, observable terminal state of one dictation insertion's auto-learn window.
public enum InsertionState: String, Sendable, Equatable {
    case inserted   // text inserted; auto-learn window open
    case edited     // user changed the inserted text (non-terminal; repeatable)
    case learned    // a correction was learned (terminal)
    case reverted   // user reverted to the raw transcript (terminal)
    case expired    // window elapsed with no learnable correction (terminal)
    case abandoned  // field became unreadable / focus moved away (terminal)
}

/// Formalizes the implicit pending-snapshot state in `PostInsertEditWatcher` /
/// `HotwordAutoLearnController` so we can see WHERE an insertion ended up and how many edit
/// rounds it took. Pure observability — it records what happens, it does NOT gate whether
/// learning fires (that judgment stays in `PostInsertEditWatcher.observeEdit`). First terminal
/// wins; transitions after a terminal are ignored.
public struct InsertionLifecycle: Sendable, Equatable {
    public private(set) var state: InsertionState
    public private(set) var attempts: Int

    public init() { state = .inserted; attempts = 0 }

    public var isTerminal: Bool {
        switch state {
        case .inserted, .edited: false
        case .learned, .reverted, .expired, .abandoned: true
        }
    }

    /// User changed the inserted text. Non-terminal, repeatable; bumps `attempts`.
    public mutating func recordEdit() {
        guard !isTerminal else { return }
        state = .edited
        attempts += 1
    }

    public mutating func recordLearned() { finish(.learned) }
    public mutating func recordReverted() { finish(.reverted) }
    public mutating func recordExpired() { finish(.expired) }
    public mutating func recordAbandoned() { finish(.abandoned) }

    /// First terminal wins; a later terminal (e.g. the window expiring after a learn already
    /// fired) is ignored.
    private mutating func finish(_ terminal: InsertionState) {
        guard !isTerminal else { return }
        state = terminal
    }

    /// Compact fields for a diagnostic event.
    public var diagnosticFields: [String: String] {
        ["state": state.rawValue, "attempts": String(attempts)]
    }
}
