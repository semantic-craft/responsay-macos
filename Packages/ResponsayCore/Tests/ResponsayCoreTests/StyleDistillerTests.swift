import Testing
import Foundation
@testable import ResponsayCore

private let configured = LLMEndpoint(
    providerId: "openai", baseURL: "https://api.example.com/v1", model: "m", apiKey: "k")

@Test func styleDistiller_clean_takesFirstNonEmptyLineCapped() {
    #expect(StyleDistiller.clean("  \n偏简洁、主动语态、保留术语。\n（解释：……）") == "偏简洁、主动语态、保留术语。")
    #expect(StyleDistiller.clean(String(repeating: "字", count: 200)).count == 80)
}

@Test func styleDistiller_userPrompt_numbersSamples() {
    let p = StyleDistiller.userPrompt(samples: ["第一句", "第二句"])
    #expect(p.contains("1. 第一句"))
    #expect(p.contains("2. 第二句"))
}

@Test func styleDistiller_emptySamples_returnEmptyWithoutCalling() async throws {
    // A non-empty stub return would surface as "x"; "" proves the early-return path was taken.
    let d = StyleDistiller(execute: { _ in "x" })
    let out = try await d.distill(samples: ["   ", ""], endpoint: configured)
    #expect(out.isEmpty)
}

@Test func styleDistiller_happyPath_returnsCleanedDescriptor() async throws {
    let d = StyleDistiller(execute: { _ in "偏正式、长句、术语密集\n多余的第二行" })
    let out = try await d.distill(samples: ["我们应当审慎认定违约责任。"], endpoint: configured)
    #expect(out == "偏正式、长句、术语密集")
}
