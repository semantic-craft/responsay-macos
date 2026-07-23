import Testing
import Foundation
@testable import ResponsayCore

/// Per-term provenance (🖋 manual / ✦ auto) so the flywheel's promoted terms
/// land in the store and the 词典 UI can filter them (issues 053/085).
@Suite struct HotwordProvenanceTests {
    @Test func mergingAutoAddedTermsMarksThemAuto() {
        let store = HotwordStore(userTerms: ["手动词"]).merging(autoAdded: ["处理者"])
        #expect(store.userTermEntries.contains(HotwordTerm(text: "处理者", source: .auto)))
        #expect(store.userTermEntries.contains(HotwordTerm(text: "手动词", source: .manual)))
        #expect(store.flattened().contains("处理者"))
    }

    @Test func autoMergeNeverDuplicatesOrDemotesAManualTerm() {
        let store = HotwordStore(userTerms: ["处理者"]).merging(autoAdded: ["处理者", "处理者"])
        #expect(store.userTermEntries == [HotwordTerm(text: "处理者", source: .manual)])
    }

    @Test func provenanceFilterSplitsManualAndAuto() {
        let store = HotwordStore(userTerms: ["手动词"]).merging(autoAdded: ["自动词"])
        #expect(store.userTermEntries(source: .manual).map(\.text) == ["手动词"])
        #expect(store.userTermEntries(source: .auto).map(\.text) == ["自动词"])
    }
}
