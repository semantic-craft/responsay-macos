import Testing
@testable import ResponsayCore

// #5 reduced: the two insertion rules centralized in one pure resolver.
// - route: copy-pill vs insert vs skip (platform-agnostic; nil editability never copy-pills)
// - mechanismOrder: clipboard first, keystroke only when Secure Input is off (AC1, no CGEvent)

// MARK: - mechanismOrder (AC1: ⌘V-under-Secure-Input fallback, tested without real CGEvent)

@Test func mechanismOrder_secureInputActive_clipboardOnly() {
    #expect(InsertionStrategyResolver.mechanismOrder(isSecureInputActive: true) == [.clipboard])
}

@Test func mechanismOrder_secureInputInactive_clipboardThenKeystroke() {
    #expect(InsertionStrategyResolver.mechanismOrder(isSecureInputActive: false) == [.clipboard, .keystroke])
}

// MARK: - route: copy-pill only for .insertImmediately + hasText + editable == false

@Test func route_insertImmediately_copyPillOnlyWhenHasTextAndEditableFalse() {
    // The single copy-pill case: non-editable target + text present.
    #expect(InsertionStrategyResolver.route(policy: .insertImmediately, isEditableTarget: false, hasText: true) == .copyPill)

    // No text → nothing to copy-pill → insert path (empty insert no-ops downstream).
    #expect(InsertionStrategyResolver.route(policy: .insertImmediately, isEditableTarget: false, hasText: false) == .insert)

    // Editable target → normal insert, not a copy pill.
    #expect(InsertionStrategyResolver.route(policy: .insertImmediately, isEditableTarget: true, hasText: true) == .insert)
    #expect(InsertionStrategyResolver.route(policy: .insertImmediately, isEditableTarget: true, hasText: false) == .insert)

    // nil editability (no provider / headless) NEVER copy-pills — matches HEAD's `isEditableTarget?() == false`
    // where nil ≠ false → falls through to insert.
    #expect(InsertionStrategyResolver.route(policy: .insertImmediately, isEditableTarget: nil, hasText: true) == .insert)
    #expect(InsertionStrategyResolver.route(policy: .insertImmediately, isEditableTarget: nil, hasText: false) == .insert)
}

// MARK: - route: exhaustive over policy × editability{nil,true,false} × hasText{true,false}

@Test func route_replaceSelection_alwaysInsert() {
    for editable: Bool? in [nil, true, false] {
        for hasText in [true, false] {
            #expect(InsertionStrategyResolver.route(policy: .replaceSelection, isEditableTarget: editable, hasText: hasText) == .insert)
        }
    }
}

@Test func route_copyOnly_alwaysSkip() {
    for editable: Bool? in [nil, true, false] {
        for hasText in [true, false] {
            #expect(InsertionStrategyResolver.route(policy: .copyOnly, isEditableTarget: editable, hasText: hasText) == .skip)
        }
    }
}

@Test func route_noInsert_alwaysSkip() {
    for editable: Bool? in [nil, true, false] {
        for hasText in [true, false] {
            #expect(InsertionStrategyResolver.route(policy: .noInsert, isEditableTarget: editable, hasText: hasText) == .skip)
        }
    }
}
