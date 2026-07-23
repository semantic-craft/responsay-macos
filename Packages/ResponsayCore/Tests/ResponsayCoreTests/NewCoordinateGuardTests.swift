import Testing
import Foundation
@testable import ResponsayCore

/// 121 — NewCoordinateGuard enforces `[待核]` discipline after style shaping.
struct NewCoordinateGuardTests {
    private let guardPass = NewCoordinateGuard()

    private func verified(label: String, kind: VerificationKind) -> VerificationAnchor {
        VerificationAnchor(
            id: label, label: label, kind: kind, status: .verifiedLaw, query: label,
            source: VerifiedSource(title: label, url: "https://flk.npc.gov.cn", accessedAt: "2026-06-07", provider: "Manual")
        )
    }

    @Test func detects_law_case_date_standard() {
        let text = "依据《民法典》第577条，参见（2023）京01民终1234号，标准 GB/T 39335，作出于 2026年6月7日。"
        let kinds = Set(guardPass.detectCoordinates(in: text).map(\.kind))
        #expect(kinds.contains(.law))
        #expect(kinds.contains(.caseLaw))
        #expect(kinds.contains(.standard))
        #expect(kinds.contains(.date))
    }

    @Test func newCoordinate_isMarkedPending() {
        let text = "本案应适用《个人信息保护法》第13条。"
        let anchors = guardPass.reconcile(text: text, existing: [])
        #expect(anchors.count == 1)
        #expect(anchors[0].status == .pending)            // [待核]
        #expect(anchors[0].kind == .law)
    }

    @Test func verifiedWithSource_isPreserved() {
        let label = "《民法典》第577条"
        let text = "如\(label)所述，违约方应担责。"
        let anchors = guardPass.reconcile(text: text, existing: [verified(label: label, kind: .law)])
        #expect(anchors.count == 1)
        #expect(anchors[0].status == .verifiedLaw)
    }

    @Test func packCannotCancelPending_forgedVerifiedWithoutSource() {
        // A pack/model asserted "verified" but there is no source → guard re-marks pending.
        let label = "《数据安全法》第21条"
        let forged = VerificationAnchor(
            id: label, label: label, kind: .law, status: .verifiedLaw, query: label, source: nil
        )
        let text = "据\(label)，应分级保护。"
        let anchors = guardPass.reconcile(text: text, existing: [forged])
        #expect(anchors[0].status == .pending)
    }

    @Test func allCoordinatesVerified_falseWhenAnyNew() {
        let text = "适用《民法典》第577条 与 《消费者权益保护法》第55条。"
        let onlyOneVerified = [verified(label: "《民法典》第577条", kind: .law)]
        #expect(guardPass.allCoordinatesVerified(text: text, existing: onlyOneVerified) == false)
    }

    @Test func noCoordinates_isVacuouslyVerified() {
        #expect(guardPass.allCoordinatesVerified(text: "这是一段没有法条坐标的普通润色文本。", existing: []))
    }
}
