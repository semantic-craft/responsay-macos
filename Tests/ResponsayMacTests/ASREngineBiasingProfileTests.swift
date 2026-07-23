import XCTest
@testable import ResponsayMac

/// Locks the biasing-seam audit (2026-06-20) into executable form: which ASR engine carries which
/// contextual-biasing route. Guards against the default engine's request-side inertness being
/// silently regressed or misread. The `ASREngineBiasingProfile` switch is exhaustive, so a new
/// `ASREngine` case fails to compile until declared; these tests pin the values the audit found.
final class ASREngineBiasingProfileTests: XCTestCase {

    /// Pins WHICH engine is the cold-start default, on a fresh defaults store so it can't be
    /// polluted by sibling tests.
    func testColdStartDefaultEngineIsQwenRealtime() {
        let suite = "test.asr.biasing.\(name)"
        let fresh = UserDefaults(suiteName: suite)!
        fresh.removePersistentDomain(forName: suite)
        XCTAssertEqual(ASREngine.selected(defaults: fresh), .cloudQwenASRFlashRealtime)
    }

    /// hard-match is universal: `RoutedSpeechCaptureService.stop()` enforces it on every engine.
    func testEveryEngineCarriesHardMatch() {
        for engine in ASREngine.allCases {
            XCTAssertTrue(ASREngineBiasingProfile.routes(for: engine).contains(.hardMatch),
                          "\(engine.rawValue) must carry hardMatch (stop() enforces it for all)")
        }
    }

    /// No engine is biasing-dead: every engine carries at least the hard-match repair.
    func testNoEngineHasEmptyRoutes() {
        for engine in ASREngine.allCases {
            XCTAssertFalse(ASREngineBiasingProfile.routes(for: engine).isEmpty,
                           "\(engine.rawValue) has no biasing routes at all")
        }
    }

    /// Whisper-family + Gemini genuinely put the weak prompt on the wire.
    func testWhisperFamilyCarriesWeakPrompt() {
        for engine in [ASREngine.cloudOpenAI, .cloudGemini, .customOpenAI] {
            XCTAssertTrue(ASREngineBiasingProfile.routes(for: engine).contains(.weakPrompt),
                          "\(engine.rawValue) should carry weakPrompt")
        }
    }

    /// In-process Qwen3-ASR (LLM decoder) is the ONE offline engine that carries a request-side
    /// soft route: its model-config `hotwords` field (sherpa-onnx ≥v1.12.35; we ship v1.13.2) is
    /// fed `weakPrompt` at recognizer build — wired 2026-06-20 (#500 S1). If this regresses to
    /// hard-match only, the offline flywheel lost its biasing channel.
    func testQwen3LocalCarriesWeakPromptViaModelHotwords() {
        XCTAssertEqual(ASREngineBiasingProfile.routes(for: .qwen3LocalASR), [.weakPrompt, .hardMatch])
    }

    /// MiMo's factory wires a weak-prompt provider, but its API discards text parts. Pin the
    /// HONEST (effective) behavior so the profile can never be misread as actually biasing MiMo.
    func testMimoDoesNotEffectivelyCarryWeakPrompt() {
        XCTAssertFalse(ASREngineBiasingProfile.routes(for: .cloudMimo).contains(.weakPrompt))
        XCTAssertEqual(ASREngineBiasingProfile.routes(for: .cloudMimo), [.hardMatch])
    }

    /// Volcengine flash gets no request-side biasing today (BigASR boosting not wired).
    func testVolcengineCarriesOnlyHardMatch() {
        XCTAssertEqual(ASREngineBiasingProfile.routes(for: .cloudVolcengineFlash), [.hardMatch])
    }

    /// Offline (non-Qwen3) + Apple engines never reach a request-side biasing channel, so they are
    /// hard-match only. Qwen3-local is excluded: it carries weakPrompt via its model-config
    /// `hotwords` field (see `testQwen3LocalCarriesWeakPromptViaModelHotwords`).
    func testLocalAndAppleEnginesAreHardMatchOnly() {
        for engine in [ASREngine.apple, .sensevoiceLocal,
                       .fireRedASR2AEDLocal, .funAsrNanoLocal] {
            XCTAssertEqual(ASREngineBiasingProfile.routes(for: engine), [.hardMatch],
                           "\(engine.rawValue) should be hard-match only")
        }
    }
}
