import XCTest
import ResponsayCore
@testable import ResponsayMac

/// Repro for the 设置·模型 panel bug: "选了模型后选择生效不了，会卡在那" — picking a model in a
/// lane's dropdown doesn't stick / reverts. The picker binding is
/// `get: ModelRouteCatalog.currentXId` / `set: ModelRouteSelectionActions.applyXSelection`, so the
/// invariant is: applying an option id must make `currentXId` return that same id. If it doesn't,
/// SwiftUI's Picker re-reads `get`, sees a different value, and snaps back — the "stuck" symptom.
final class ModelLaneSelectionRoundTripTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.modelLaneSelectionRoundTrip"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func laneDisplay() -> ModelLaneDisplay {
        ModelLaneDisplay(
            defaults: defaults,
            readiness: ModelLaneReadinessResolver(
                dispatcher: ProviderConfigDispatcher(
                    defaults: defaults,
                    keyReader: { _ in nil }),
                ocrKeyReader: { _ in nil }))
    }

    func testEveryASROptionSticksWhenSelected() {
        for option in ModelRouteCatalog.asrOptions {
            ModelRouteSelectionActions.applyASRSelection(option.id, defaults: defaults)
            let got = ModelRouteCatalog.currentASRId(defaults: defaults)
            XCTAssertEqual(got, option.id, "ASR '\(option.id)' must stick; got '\(got)'")
        }
    }

    func testEveryLLMOptionSticksWhenSelected() {
        for option in ModelRouteCatalog.llmOptions {
            ModelRouteSelectionActions.applyLLMSelection(option.id, defaults: defaults)
            let got = ModelRouteCatalog.currentLLMId(defaults: defaults)
            XCTAssertEqual(got, option.id, "LLM '\(option.id)' must stick; got '\(got)'")
        }
    }

    func testEveryTTSOptionSticksWhenSelected() {
        for option in ModelRouteCatalog.ttsOptions {
            ModelRouteSelectionActions.applyTTSSelection(option.id, defaults: defaults)
            let got = ModelRouteCatalog.currentTTSId(defaults: defaults)
            XCTAssertEqual(got, option.id, "TTS '\(option.id)' must stick; got '\(got)'")
        }
    }

    func testSelectionPostsContentFreeModelConfigurationEvent() {
        let event = expectation(description: "model configuration invalidated")
        let token = NotificationCenter.default.addObserver(
            forName: .modelConfigurationDidChange,
            object: nil,
            queue: nil
        ) { note in
            XCTAssertNil(note.object)
            event.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        ModelRouteSelectionActions.applyLLMSelection("openai", defaults: defaults)

        wait(for: [event], timeout: 0.1)
    }

    /// The exact value the SwiftUI Picker reads back (`lane.currentOptionId`) must equal the
    /// applied option — this is what makes the dropdown show the new choice instead of reverting.
    func testASRLanePickerValueMatchesAppliedOption() {
        for option in ModelRouteCatalog.asrOptions {
            ModelRouteSelectionActions.applyASRSelection(option.id, defaults: defaults)
            let lane = laneDisplay().lanes().first { $0.lane == .asr }!
            XCTAssertEqual(lane.currentOptionId, option.id, "ASR picker get for '\(option.id)'")
        }
    }

    func testLLMLanePickerValueMatchesAppliedOption() {
        for option in ModelRouteCatalog.llmOptions {
            ModelRouteSelectionActions.applyLLMSelection(option.id, defaults: defaults)
            let lane = laneDisplay().lanes().first { $0.lane == .llm }!
            XCTAssertEqual(lane.currentOptionId, option.id, "LLM picker get for '\(option.id)'")
        }
    }

    func testTTSLanePickerValueMatchesAppliedOption() {
        for option in ModelRouteCatalog.ttsOptions {
            ModelRouteSelectionActions.applyTTSSelection(option.id, defaults: defaults)
            let lane = laneDisplay().lanes().first { $0.lane == .tts }!
            XCTAssertEqual(lane.currentOptionId, option.id, "TTS picker get for '\(option.id)'")
        }
    }
}
