import Testing
@testable import ResponsayCore

/// 112 — LegalBrainEnabled flag resolution.
struct LegalBrainFlagTests {
    @Test func resolve_nilUsesBuildDefault() {
        #expect(LegalBrainFlag.resolve(stored: nil).isEnabled == LegalBrainFlag.defaultEnabled)
    }

    @Test func resolve_explicitOverrideWins() {
        #expect(LegalBrainFlag.resolve(stored: true).isEnabled == true)
        #expect(LegalBrainFlag.resolve(stored: false).isEnabled == false)
    }

    @Test func internalTesterBuildDefaultsOn() {
        // The test target compiles DEBUG → internal-tester default is on.
        #expect(LegalBrainFlag.defaultEnabled == true)
    }
}
