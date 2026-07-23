import ResponsayCore
@testable import ResponsaySpeech
import XCTest
@testable import ResponsayMac

/// Pins the fix for the orphaned per-provider ASR model keys (issue 282): the
/// runtime must honor the model the Settings card actually persists
/// (`byok.asr.model` + `byok.asr.provider`), not dead per-provider keys.
final class ASRModelSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "asr-model-selection-tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testFallsBackWhenNothingConfigured() {
        XCTAssertEqual(
            ASRModelSelection.model(forProvider: "openai", fallback: "gpt-4o-transcribe", defaults: defaults),
            "gpt-4o-transcribe")
    }

    func testUsesChosenModelWhenProviderMatches() {
        defaults.set("openai", forKey: "byok.asr.provider")
        defaults.set("whisper-1", forKey: "byok.asr.model")
        XCTAssertEqual(
            ASRModelSelection.model(forProvider: "openai", fallback: "gpt-4o-transcribe", defaults: defaults),
            "whisper-1")
    }

    func testLegacyMimoEngineIdNormalizesToCatalogProviderId() {
        defaults.set("mimo-token-plan", forKey: "byok.asr.provider")
        defaults.set("mimo-custom-asr", forKey: "byok.asr.model")
        XCTAssertEqual(
            ASRModelSelection.model(forProvider: "mimo", fallback: "mimo-v2.5-asr", defaults: defaults),
            "mimo-custom-asr")
    }

    func testIgnoresChosenModelForOtherProviders() {
        // The card stores one global pair; a MiMo selection must not leak
        // into the openai service.
        defaults.set("mimo", forKey: "byok.asr.provider")
        defaults.set("mimo-v2.5-asr", forKey: "byok.asr.model")
        XCTAssertEqual(
            ASRModelSelection.model(forProvider: "openai", fallback: "gpt-4o-transcribe", defaults: defaults),
            "gpt-4o-transcribe")
    }

    func testBlankModelFallsBack() {
        defaults.set("openai", forKey: "byok.asr.provider")
        defaults.set("   ", forKey: "byok.asr.model")
        XCTAssertEqual(
            ASRModelSelection.model(forProvider: "openai", fallback: "gpt-4o-transcribe", defaults: defaults),
            "gpt-4o-transcribe")
    }

    func testQwenASRFlashNormalPathUsesFinalOnlyTranscription() {
        XCTAssertFalse(
            CloudQwenSpeechCaptureService.usesPostUploadStreamingPreview(forProvider: "qwen-asr-flash"))
        XCTAssertTrue(
            CloudQwenSpeechCaptureService.usesPostUploadStreamingPreview(forProvider: "mimo"))
    }
}
