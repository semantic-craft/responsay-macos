import Testing
import Foundation
@testable import ResponsayCore

/// Phase 2 (#400) GitHub read-only catalog client: decode the index, download a skill's raw
/// markdown, and resolve install state vs what's imported. Pure given an injected fetcher.
struct LegalSkillCatalogTests {
    @Test func decodesIndexAndDownloadsSkillMarkdown() async throws {
        let indexJSON = """
        {"schemaVersion":1,"skills":[
          {"id":"community.demo.cn","title":"演示技能","tags":["demo"],"version":"1.0",
           "rawURL":"https://example.com/skills/demo.LEGAL_SKILL.md"}
        ]}
        """
        let skillMD = "# demo\n```legal-skill\n{}\n```\n"
        let client = LegalSkillCatalogClient(indexURL: URL(string: "https://example.com/index.json")!) { url in
            url.absoluteString.hasSuffix("index.json") ? Data(indexJSON.utf8) : Data(skillMD.utf8)
        }

        let index = try await client.loadIndex()
        #expect(index.schemaVersion == 1)
        #expect(index.skills.count == 1)
        #expect(index.skills[0].id == "community.demo.cn")
        #expect(index.skills[0].tags == ["demo"])

        let md = try await client.downloadSkillMarkdown(index.skills[0])
        #expect(md == skillMD)
    }

    @Test func downloadRejectsBadRawURL() async {
        let entry = LegalSkillCatalogEntry(id: "x.y.cn", title: "T", rawURL: "not a url")
        let client = LegalSkillCatalogClient(indexURL: URL(string: "https://x/i.json")!) { _ in Data() }
        await #expect(throws: LegalSkillCatalogError.badRawURL("not a url")) {
            _ = try await client.downloadSkillMarkdown(entry)
        }
    }

    @Test func installStateReflectsImportedAndVersion() {
        let entry = LegalSkillCatalogEntry(id: "a.b.cn", title: "T", version: "1.2",
                                           rawURL: "https://x/a.LEGAL_SKILL.md")
        #expect(entry.installState(installedVersions: [:]) == .notInstalled)
        #expect(entry.installState(installedVersions: ["a.b.cn": "1.2"]) == .installed)
        #expect(entry.installState(installedVersions: ["a.b.cn": "1.1"]) == .updateAvailable)
        // Installed but no recorded version → can't tell, treat as installed (no nag).
        #expect(entry.installState(installedVersions: ["a.b.cn": nil]) == .installed)
    }

    @Test func versionCompareIsNumericAware() {
        #expect(LegalSkillVersion.compare("1.2", "1.10") == .orderedAscending)
        #expect(LegalSkillVersion.compare("2.0", "1.9") == .orderedDescending)
        #expect(LegalSkillVersion.compare("1.0", "1.0") == .orderedSame)
        #expect(LegalSkillVersion.compare("1.0.1", "1.0") == .orderedDescending)
    }
}
