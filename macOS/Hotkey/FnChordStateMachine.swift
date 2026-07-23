import AppKit

@MainActor
final class FnChordStateMachine {
    private let anchor: ShortcutAnchor
    private let letterKeyTimeout: TimeInterval
    private let onDown: @MainActor (FnChord) -> Void
    private let onUp: @MainActor (FnChord) -> Void

    private enum State {
        case idle
        case waitingForLetterKey(modifiers: Set<FnModifier>)
        case letterKeyMatched(chord: FnChord)
        case modifierOnlyEmitted(chord: FnChord)
    }

    private var state: State = .idle
    private var timeoutTask: Task<Void, Never>?

    var isActive: Bool {
        if case .idle = state { return false }
        return true
    }

    init(
        anchor: ShortcutAnchor = .fn,
        letterKeyTimeout: TimeInterval = 0.4,
        onDown: @escaping @MainActor (FnChord) -> Void,
        onUp: @escaping @MainActor (FnChord) -> Void
    ) {
        self.anchor = anchor
        self.letterKeyTimeout = letterKeyTimeout
        self.onDown = onDown
        self.onUp = onUp
    }

    func fnDown(modifierFlags: NSEvent.ModifierFlags) {
        anchorDown(modifierFlags: modifierFlags)
    }

    func anchorDown(modifierFlags: NSEvent.ModifierFlags) {
        guard case .idle = state else { return }

        let modifiers = FnChord.extractModifiers(from: modifierFlags, anchor: anchor)
        state = .waitingForLetterKey(modifiers: modifiers)
        startTimeout()
    }

    /// A modifier key (⇧/⌃/⌥/⌘) changed while Fn is held, before a letter key or the
    /// timeout. **Accumulate** (union) it into the pending chord — never drop one on
    /// release. Two reasons: (1) Fn-then-Shift ordering — the keys rarely land on the same
    /// millisecond, so Fn-first must still reach `fn+shift`; (2) a quick Fn+⇧ *tap* releases
    /// ⇧ a hair before Fn, so replacing (instead of unioning) would reset the chord back to
    /// `fn` (→ 语音输入) right before fnUp. A modifier held with Fn at any point in the
    /// window counts. No-op once a letter key matched or before Fn is down.
    func modifiersChanged(modifierFlags: NSEvent.ModifierFlags) {
        guard case .waitingForLetterKey(let current) = state else { return }
        state = .waitingForLetterKey(
            modifiers: current.union(FnChord.extractModifiers(from: modifierFlags, anchor: anchor)))
    }

    @discardableResult
    func letterKeyDown(keyCode: UInt16) -> Bool {
        guard case .waitingForLetterKey(let modifiers) = state else { return false }
        guard let fnKey = FnKey.from(keyCode: keyCode) else { return false }

        cancelTimeout()
        let chord = FnChord(anchor: anchor, modifiers: modifiers, key: fnKey)
        state = .letterKeyMatched(chord: chord)
        onDown(chord)
        return true
    }

    func fnUp() {
        anchorUp()
    }

    func anchorUp() {
        switch state {
        case .idle:
            break

        case .waitingForLetterKey(let modifiers):
            cancelTimeout()
            let chord = FnChord(anchor: anchor, modifiers: modifiers, key: nil)
            state = .idle
            onDown(chord)
            onUp(chord)

        case .letterKeyMatched(let chord):
            state = .idle
            onUp(chord)

        case .modifierOnlyEmitted(let chord):
            state = .idle
            onUp(chord)
        }
    }

    private func startTimeout() {
        timeoutTask = Task { [weak self, letterKeyTimeout] in
            try? await Task.sleep(for: .seconds(letterKeyTimeout))
            guard !Task.isCancelled else { return }
            self?.handleTimeout()
        }
    }

    /// Reads the modifiers from `state` (not a value captured at Fn-down) so a modifier
    /// added mid-window via `modifiersChanged` is reflected in the emitted chord.
    private func handleTimeout() {
        guard case .waitingForLetterKey(let modifiers) = state else { return }
        let chord = FnChord(anchor: anchor, modifiers: modifiers, key: nil)
        state = .modifierOnlyEmitted(chord: chord)
        onDown(chord)
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}
