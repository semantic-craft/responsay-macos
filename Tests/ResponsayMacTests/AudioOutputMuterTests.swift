import XCTest
@testable import ResponsayMac

@MainActor
final class AudioOutputMuterTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var backend: FakeOutputMuteBackend!
    private var muter: AudioOutputMuter!

    override func setUp() async throws {
        suite = "AudioOutputMuterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        backend = FakeOutputMuteBackend()
        muter = AudioOutputMuter(backend: backend, defaults: defaults)
    }

    override func tearDown() async throws {
        backend.failWrites = []
        backend.values = ["A": 0, "B": 0]
        muter.disengage()
        defaults.removePersistentDomain(forName: suite)
    }

    func testSwitchRestoresOldDeviceBeforeMutingNewAndRapidReturn() {
        muter.engage(afterDelay: 0)
        backend.switchTo("B")
        backend.switchTo("A")
        muter.disengage()
        XCTAssertEqual(backend.writes, ["A=1", "A=0", "B=1", "B=0", "A=1", "A=0"])
        XCTAssertEqual(backend.values, ["A": 0, "B": 0])
        XCTAssertFalse(muter.isOutputMutedByApp)
    }

    func testAlreadyMutedDeviceIsNeverOwnedOrUnmuted() {
        backend.values["A"] = 1
        muter.engage(afterDelay: 0)
        backend.switchTo("B")
        muter.disengage()
        XCTAssertEqual(backend.values["A"], 1)
        XCTAssertEqual(backend.writes, ["B=1", "B=0"])
    }

    func testStopCancelsDelayedMuteAndOldGenerationCannotAffectNewSession() async throws {
        muter.engage(afterDelay: 0.03)
        muter.disengage()
        muter.engage(afterDelay: 0.15)
        try await Task.sleep(for: .milliseconds(70))
        XCTAssertTrue(backend.writes.isEmpty)
        muter.disengage()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(backend.writes.isEmpty)
    }

    func testDelayedMuteUsesCurrentDevice() async throws {
        muter.engage(afterDelay: 0.03)
        backend.switchTo("B")
        XCTAssertTrue(backend.writes.isEmpty)
        try await Task.sleep(for: .milliseconds(90))
        XCTAssertEqual(backend.writes, ["B=1"])
    }

    func testUnsupportedMuteDoesNotClaimSuccess() {
        backend.failWrites = ["A"]
        muter.engage(afterDelay: 0)
        XCTAssertFalse(muter.isOutputMutedByApp)
        XCTAssertTrue(savedRecords.isEmpty)
        XCTAssertNotNil(muter.recoveryNotice)
    }

    func testMissingMutePropertyShowsNotice() {
        backend.values.removeValue(forKey: "A")
        muter.engage(afterDelay: 0)
        XCTAssertFalse(muter.isOutputMutedByApp)
        XCTAssertNotNil(muter.recoveryNotice)
    }

    func testFailedRestorePersistsAndRetriesOnHardwareChange() {
        muter.engage(afterDelay: 0)
        backend.failWrites = ["A"]
        muter.disengage()
        XCTAssertEqual(savedRecords["A"]?.uint32Value, 0)
        XCTAssertTrue(muter.isOutputMutedByApp)
        backend.failWrites = []
        backend.change?(nil, nil)
        XCTAssertEqual(backend.values["A"], 0)
        XCTAssertTrue(savedRecords.isEmpty)
        XCTAssertFalse(muter.isOutputMutedByApp)
    }

    func testUnavailableDeviceRecordSurvivesAndRestoresWhenReconnected() {
        muter.engage(afterDelay: 0)
        backend.values.removeValue(forKey: "A")
        backend.switchTo("B")
        muter.disengage()
        XCTAssertEqual(savedRecords["A"]?.uint32Value, 0)
        backend.values["A"] = 1
        backend.change?(nil, nil)
        XCTAssertEqual(backend.values["A"], 0)
        XCTAssertTrue(savedRecords.isEmpty)
    }

    func testUserOverrideWinsEvenAfterSwitchingAwayAndBack() {
        muter.engage(afterDelay: 0)
        backend.userMute(0, uid: "A")
        backend.userMute(1, uid: "A")
        backend.switchTo("B")
        backend.switchTo("A")
        muter.disengage()
        XCTAssertEqual(backend.values["A"], 1)
        XCTAssertEqual(backend.writes.filter { $0.hasPrefix("A") }, ["A=1"])
    }

    func testOverrideOnOldDeviceWithPendingRestoreSurvivesReturnWithoutNotification() {
        muter.engage(afterDelay: 0)
        backend.failWrites = ["A"]
        backend.switchTo("B")
        backend.values["A"] = 0
        backend.failWrites = []
        backend.switchTo("A")
        XCTAssertEqual(backend.values["A"], 0)
        XCTAssertEqual(backend.writes.filter { $0.hasPrefix("A") }, ["A=1"])
    }

    func testStopRespectsOverrideEvenWithoutNotification() {
        muter.engage(afterDelay: 0)
        backend.values["A"] = 0
        muter.disengage()
        XCTAssertEqual(backend.writes, ["A=1"])
        XCTAssertTrue(savedRecords.isEmpty)
    }

    func testCrashRecoveryUsesUIDNotCurrentDefaultAndKeepsUnavailableRecords() {
        defaults.set(["A": 0, "missing": 0], forKey: AudioOutputMuter.recoveryKey)
        backend.values["A"] = 1
        backend.defaultOutputUID = "B"
        muter = AudioOutputMuter(backend: backend, defaults: defaults)
        muter.recoverStuckMuteIfNeeded()
        XCTAssertEqual(backend.writes, ["A=0"])
        XCTAssertEqual(savedRecords["missing"]?.uint32Value, 0)
        XCTAssertEqual(backend.values["B"], 0)
    }

    func testLegacyRecordIsPreservedWithoutGuessingDevice() {
        defaults.set(0, forKey: AudioOutputMuter.legacyKey)
        muter.recoverStuckMuteIfNeeded()
        XCTAssertTrue(backend.writes.isEmpty)
        XCTAssertNotNil(defaults.object(forKey: AudioOutputMuter.legacyKey))
        XCTAssertNotNil(muter.recoveryNotice)
    }

    func testRestoreRetriesWithoutAnotherHardwareNotification() async throws {
        muter.engage(afterDelay: 0)
        backend.failWrites = ["A"]
        muter.disengage()
        XCTAssertNotNil(muter.recoveryNotice)
        backend.failWrites = []
        try await Task.sleep(for: .milliseconds(2200))
        XCTAssertEqual(backend.values["A"], 0)
        XCTAssertTrue(savedRecords.isEmpty)
        XCTAssertNil(muter.recoveryNotice)
    }

    func testWriteWithoutConfirmedReadbackIsNotReportedAsSuccess() {
        backend.hideAfterWrite = true
        muter.engage(afterDelay: 0)
        XCTAssertFalse(muter.isOutputMutedByApp)
        XCTAssertEqual(savedRecords["A"]?.uint32Value, 0)
        backend.hideAfterWrite = false
        backend.hidden = false
        muter.disengage()
        XCTAssertEqual(backend.values["A"], 0)
        XCTAssertTrue(savedRecords.isEmpty)
    }

    func testSettingOffRestoresImmediatelyAndUnrelatedDefaultsDoNotReengage() {
        let center = NotificationCenter()
        let subscription = RecordingMuteSettings.changes(defaults: defaults, center: center)
            .sink { [muter] enabled in
                MainActor.assumeIsolated {
                    if enabled { muter?.engage(afterDelay: 0) } else { muter?.disengage() }
                }
            }
        defer { subscription.cancel() }
        muter.engage(afterDelay: 0)
        defaults.set(false, forKey: RecordingMuteSettings.key)
        center.post(name: UserDefaults.didChangeNotification, object: defaults)
        XCTAssertEqual(backend.values["A"], 0)
        XCTAssertFalse(muter.isOutputMutedByApp)
        defaults.set(true, forKey: RecordingMuteSettings.key)
        center.post(name: UserDefaults.didChangeNotification, object: defaults)
        XCTAssertEqual(backend.values["A"], 1)
        muter.disengage() // e.g. the existing read-aloud handoff
        defaults.set("unrelated", forKey: "unrelated")
        center.post(name: UserDefaults.didChangeNotification, object: defaults)
        XCTAssertEqual(backend.values["A"], 0)
    }

    func testRecoveryRecordExistsBeforeHardwareWrite() {
        backend.beforeWrite = { [defaults] in
            XCTAssertEqual((defaults?.dictionary(forKey: AudioOutputMuter.recoveryKey)?["A"] as? NSNumber)?.uint32Value, 0)
        }
        muter.engage(afterDelay: 0)
        backend.beforeWrite = nil
    }

    private var savedRecords: [String: NSNumber] {
        defaults.dictionary(forKey: AudioOutputMuter.recoveryKey) as? [String: NSNumber] ?? [:]
    }
}

@MainActor
private final class FakeOutputMuteBackend: AudioOutputMuteBackend {
    var defaultOutputUID: String? = "A"
    var values: [String: UInt32] = ["A": 0, "B": 0]
    var failWrites = Set<String>()
    var writes: [String] = []
    var change: (@MainActor (String?, UInt32?) -> Void)?
    var beforeWrite: (() -> Void)?
    var hideAfterWrite = false
    var hidden = false
    func mute(for uid: String) -> UInt32? { hidden ? nil : values[uid] }
    func setMute(_ value: UInt32, for uid: String) -> Bool {
        beforeWrite?()
        guard !failWrites.contains(uid), values[uid] != nil else { return false }
        writes.append("\(uid)=\(value)")
        values[uid] = value
        hidden = hideAfterWrite
        return true
    }
    func observe(_ change: @escaping @MainActor (String?, UInt32?) -> Void) { self.change = change }
    func stopObserving() { change = nil }
    func switchTo(_ uid: String) { defaultOutputUID = uid; change?(nil, nil) }
    func userMute(_ value: UInt32, uid: String) { values[uid] = value; change?(uid, value) }
}
