import XCTest
@testable import ResponsayMac

/// `LocalEngineResidency` — the central record of which local ASR engines are in
/// memory plus manual load/unload (mirrors openless's `cache.rs`). Pure
/// bookkeeping, tested with a fake controller; the real recognizer load lives in
/// the capture service and is real-Mac territory.
@MainActor
final class LocalEngineResidencyTests: XCTestCase {

    private final class FakeController: LocalEngineResidencyControllable {
        var isCapturing = false
        var preloadCount = 0
        var backgroundPreloadCount = 0
        var unloadCount = 0
        var preloadError: Error?
        func preloadEngine() throws {
            if let preloadError { throw preloadError }
            preloadCount += 1
        }
        func preloadEngineInBackground() { backgroundPreloadCount += 1 }
        func unloadEngine() { unloadCount += 1 }
    }

    private struct StubError: Error {}

    func testCanControlReflectsRegistration() {
        let residency = LocalEngineResidency()
        XCTAssertFalse(residency.canControl("qwen3"))
        residency.register(FakeController(), id: "qwen3")
        XCTAssertTrue(residency.canControl("qwen3"))
    }

    func testSetResidentTogglesIsResident() {
        let residency = LocalEngineResidency()
        XCTAssertFalse(residency.isResident("qwen3"))
        residency.setResident("qwen3", true)
        XCTAssertTrue(residency.isResident("qwen3"))
        residency.setResident("qwen3", false)
        XCTAssertFalse(residency.isResident("qwen3"))
    }

    func testResidencyIsTrackedPerEngineIndependently() {
        let residency = LocalEngineResidency()
        residency.setResident("qwen3", true)
        XCTAssertTrue(residency.isResident("qwen3"))
        XCTAssertFalse(residency.isResident("sensevoice"))
    }

    func testPreloadDelegatesToController() throws {
        let residency = LocalEngineResidency()
        let controller = FakeController()
        residency.register(controller, id: "qwen3")
        try residency.preload("qwen3")
        XCTAssertEqual(controller.preloadCount, 1)
    }

    func testPreloadInBackgroundDelegatesToController() {
        let residency = LocalEngineResidency()
        let controller = FakeController()
        residency.register(controller, id: "qwen3")
        residency.preloadInBackground("qwen3")
        XCTAssertEqual(controller.backgroundPreloadCount, 1)
        XCTAssertEqual(controller.preloadCount, 0)   // background path is distinct from "Load now"
    }

    func testPreloadPropagatesControllerError() {
        let residency = LocalEngineResidency()
        let controller = FakeController()
        controller.preloadError = StubError()
        residency.register(controller, id: "qwen3")
        XCTAssertThrowsError(try residency.preload("qwen3"))
    }

    func testUnloadDelegatesWhenIdle() {
        let residency = LocalEngineResidency()
        let controller = FakeController()
        residency.register(controller, id: "qwen3")
        residency.unload("qwen3")
        XCTAssertEqual(controller.unloadCount, 1)
    }

    func testUnloadIsRefusedDuringCapture() {
        let residency = LocalEngineResidency()
        let controller = FakeController()
        controller.isCapturing = true
        residency.register(controller, id: "qwen3")
        residency.unload("qwen3")
        XCTAssertEqual(controller.unloadCount, 0)
    }

    func testIsCapturingReadsTheController() {
        let residency = LocalEngineResidency()
        let controller = FakeController()
        residency.register(controller, id: "qwen3")
        XCTAssertFalse(residency.isCapturing("qwen3"))
        controller.isCapturing = true
        XCTAssertTrue(residency.isCapturing("qwen3"))
    }

    func testCommandsOnUnknownEngineAreNoops() throws {
        let residency = LocalEngineResidency()
        try residency.preload("nope")     // no throw
        residency.unload("nope")          // no crash
        XCTAssertFalse(residency.isResident("nope"))
        XCTAssertFalse(residency.isCapturing("nope"))
    }
}
