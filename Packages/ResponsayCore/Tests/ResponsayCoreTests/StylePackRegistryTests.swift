import Testing
import Foundation
@testable import ResponsayCore

/// 121 — StylePack registry + built-ins.
struct StylePackRegistryTests {
    @Test func builtInsLoad() {
        let registry = StylePackRegistry()
        #expect(registry.packs.count == 7)
        #expect(registry.pack(id: "general.clear") != nil)
        #expect(registry.pack(id: "litigation.adversarial") != nil)
    }

    @Test func packsBindToDeclaredScope() {
        let registry = StylePackRegistry()
        let litigation = registry.packs(forScene: .litigation, stage: .briefDrafting).map(\.id)
        #expect(litigation.contains("litigation.adversarial"))
        #expect(litigation.contains("general.clear"))            // .any always offered
        #expect(litigation.contains("academic.argument") == false)

        let academic = registry.packs(forScene: .academicWriting, stage: .argumentDrafting).map(\.id)
        #expect(academic.contains("academic.argument"))
        #expect(academic.contains("litigation.adversarial") == false)
    }

    @Test func communityPack_rejectedInV0() {
        let community = StylePack(id: "evil", name: "untrusted", systemPrompt: "...", origin: .community)
        let registry = StylePackRegistry(packs: StylePackRegistry.builtIns + [community])
        #expect(registry.pack(id: "evil") == nil)

        let afterRegister = StylePackRegistry().registering(community)
        #expect(afterRegister.pack(id: "evil") == nil)
    }

    @Test func localImport_isAccepted() {
        let local = StylePack(id: "my.pack", name: "Mine", systemPrompt: "更简短", origin: .localImport)
        let registry = StylePackRegistry().registering(local)
        #expect(registry.pack(id: "my.pack")?.origin == .localImport)
    }

    // 325 slice 4: the bundled `style.*` LEGAL_SKILL.md files (kind:rewrite) load
    // as built-in StylePacks for the 改写风格 picker — the home they were moved to
    // when slice 3b removed them from the ⌥L generation palette.
    @Test func bundledLoadsStyleSkillsAsBuiltInPacks() throws {
        let registry = try StylePackRegistry.bundled()
        let formal = try #require(registry.pack(id: "style.formal_expression.cn"))
        #expect(formal.origin == .builtIn)
        #expect(formal.name == "正式表达")
        #expect(!formal.systemPrompt.isEmpty)
        // exactly the rewrite-kind bundled skills — no generation skill leaks in.
        // 4 after adding style.expression_upgrade.cn (表达升级 backing) on 2026-06-16;
        // 5 after adding style.condense.cn (精简压缩, 写作 lane).
        #expect(registry.packs.count == 5)
        #expect(registry.packs.allSatisfy { $0.id.hasPrefix("style.") })
    }
}
