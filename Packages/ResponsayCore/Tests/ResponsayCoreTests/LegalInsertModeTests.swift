import Testing
import Foundation
@testable import ResponsayCore

/// 192 — LegalInsertModeResolver: tracked-changes vs replace/append + [待核] preservation.
struct LegalInsertModeTests {
    private let resolver = LegalInsertModeResolver()

    @Test func richEditor_prefersTrackedChanges() {
        let cap = HostInsertCapability.forApp("Microsoft Word", hasSelection: true)
        #expect(resolver.resolve(text: "草拟回函。", capability: cap).mode == .trackedChanges)
    }

    @Test func plainField_withSelection_replaces() {
        let cap = HostInsertCapability.forApp("TextEdit", hasSelection: true)
        #expect(cap.supportsTrackedChanges == false)
        #expect(resolver.resolve(text: "x", capability: cap).mode == .replaceSelection)
    }

    @Test func plainField_noSelection_appends() {
        let cap = HostInsertCapability.forApp("Mail", hasSelection: false)
        #expect(resolver.resolve(text: "x", capability: cap).mode == .appendAfter)
    }

    @Test func nonEditable_copyOnly() {
        let cap = HostInsertCapability(isEditable: false, hasSelection: false, supportsTrackedChanges: true)
        #expect(resolver.resolve(text: "x", capability: cap).mode == .copyOnly)
    }

    @Test func optOut_usesReplaceEvenInWord() {
        let cap = HostInsertCapability.forApp("Microsoft Word", hasSelection: true)
        let plan = resolver.resolve(text: "x", capability: cap, preference: .alwaysReplaceOrAppend)
        #expect(plan.mode == .replaceSelection)
    }

    @Test func preservesPendingTag_inEveryMode() {
        let cap = HostInsertCapability.forApp("Microsoft Word", hasSelection: true)
        let plan = resolver.resolve(text: "本案适用《民法典》第577条。", capability: cap)
        #expect(plan.text.contains("《民法典》第577条[待核]"))
    }

    @Test func forApp_detectsRichEditors() {
        #expect(HostInsertCapability.forApp("Microsoft Word", hasSelection: false).supportsTrackedChanges)
        #expect(HostInsertCapability.forApp("wpsoffice", hasSelection: false).supportsTrackedChanges)
        #expect(HostInsertCapability.forApp("Notes", hasSelection: false).supportsTrackedChanges == false)
        #expect(HostInsertCapability.forApp(nil, hasSelection: false).supportsTrackedChanges == false)
    }
}
