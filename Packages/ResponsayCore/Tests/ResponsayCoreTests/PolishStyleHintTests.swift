import Testing
import Foundation
@testable import ResponsayCore

/// 418 — the active 日常办公 style pack must reach 轻度润色. The transformer takes its polish nudge
/// from a DEDICATED `polishStyleHintProvider` (the explicitly-activated pack only), threaded into the
/// batch polisher. No active pack → nil hint → plain polish.
/// 2026-06-16 — decoupled from `rewriteStyleProvider`: that now resolves to the heavy 表达升级 tier
/// default, which must never leak into the light tier.
@MainActor
final class StyleHintCapturingPolisher: TextPolishAPI {
    var lastStyleHint: String??   // outer optional = "was polish called", inner = the hint
    func polish(_ text: String) async throws -> PolishResult {
        lastStyleHint = .some(nil)
        return PolishResult(text: text, original: text)
    }
    func polish(_ text: String, styleHint: String?) async throws -> PolishResult {
        lastStyleHint = .some(styleHint)
        return PolishResult(text: text, original: text)
    }
}

struct PolishStyleHintTests {
    @MainActor
    private func transformer(
        polishHint: String?,
        rewriteStyle: RewriteStyle = .tone(.natural),
        polisher: any TextPolishAPI
    ) -> CaptureTransformer {
        CaptureTransformer(
            polisher: polisher, rewriter: nil, translator: nil,
            contextProvider: nil, translationTargetProvider: nil, rewriteToneProvider: nil,
            rewriteStyleProvider: { rewriteStyle }, polishStyleHintProvider: { polishHint })
    }

    @Test @MainActor func polishCarriesActiveEverydayPackPrompt() async throws {
        let polisher = StyleHintCapturingPolisher()
        _ = await transformer(polishHint: "用公文体改。", polisher: polisher).polish("你好 那个 我想说", locale: .english)
        #expect(polisher.lastStyleHint == .some("用公文体改。"))
    }

    @Test @MainActor func polishPassesNilHintWhenNoPackActive() async throws {
        let polisher = StyleHintCapturingPolisher()
        _ = await transformer(polishHint: nil, polisher: polisher).polish("你好", locale: .english)
        #expect(polisher.lastStyleHint == .some(nil))
    }

    /// Regression (2026-06-16) — the 表达升级 tier default on the REWRITE path (`rewriteStyleProvider`
    /// → `.pack`) must NOT leak into 轻度润色. The polish nudge comes only from polishStyleHintProvider;
    /// with no everyday pack active, polish stays unflavoured even while a heavy rewrite style is set.
    @Test @MainActor func polishIgnoresHeavyRewriteStyleDefault() async throws {
        let heavy = StylePack(id: "style.expression_upgrade.cn", name: "表达升级",
                              systemPrompt: "自由重述，改得更重。", origin: .builtIn)
        let polisher = StyleHintCapturingPolisher()
        _ = await transformer(polishHint: nil, rewriteStyle: .pack(heavy), polisher: polisher)
            .polish("你好", locale: .english)
        #expect(polisher.lastStyleHint == .some(nil))
    }
}
