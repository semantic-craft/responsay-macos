import Testing
import Foundation
@testable import ResponsayCore

/// 121 — PromptAssembler precedence + route invariance.
struct PromptAssemblerTests {
    private let assembler = PromptAssembler()

    @Test func precedenceOrdering_stylePackBelowInvariantsAndSchema() {
        let pack = StylePack(id: "p", name: "p", systemPrompt: "STYLE")
        let components = PromptComponents(
            systemInvariants: ["INVARIANT"],
            outputSchema: ["SCHEMA"],
            reasoningRequirement: ["REASONING"],
            stylePack: pack,
            contextProfile: ["CONTEXT"]
        )
        let prompt = assembler.assemble(components)
        #expect(prompt.segments.map(\.layer) == [
            .systemInvariants, .outputSchema, .reasoningRequirement, .stylePack, .contextProfile
        ])
        let text = prompt.systemPrompt
        let inv = text.range(of: "INVARIANT")!.lowerBound
        let schema = text.range(of: "SCHEMA")!.lowerBound
        let style = text.range(of: "STYLE")!.lowerBound
        let ctx = text.range(of: "CONTEXT")!.lowerBound
        #expect(inv < schema)
        #expect(schema < style)   // pack can never outrank the schema
        #expect(style < ctx)
    }

    @Test func stylePack_cannotChangeRoute() {
        // The privacy layer decided localOnly; assembling with any pack keeps it.
        let pack = StylePack(id: "p", name: "p", systemPrompt: "STYLE")
        let withPack = assembler.assemble(PromptComponents(
            stylePack: pack, route: .localOnly, contextScope: .selectedTextOnly))
        let withoutPack = assembler.assemble(PromptComponents(
            route: .localOnly, contextScope: .selectedTextOnly))
        #expect(withPack.route == .localOnly)
        #expect(withPack.route == withoutPack.route)
        #expect(withPack.contextScope == .selectedTextOnly)
    }

    @Test func emptyStylePack_isOmitted() {
        let pack = StylePack(id: "p", name: "p", systemPrompt: "")
        let prompt = assembler.assemble(PromptComponents(systemInvariants: ["INV"], stylePack: pack))
        #expect(prompt.segments.contains { $0.layer == .stylePack } == false)
    }
}
