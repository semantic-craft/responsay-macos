#if os(macOS)
import AVFoundation
import CoreAudio
import IOKit
import OSLog
import ResponsayCore

/// Applies the user's 首选麦克风 to an `AVAudioEngine` before it starts. The stored
/// `micDeviceID` is an `AVCaptureDevice.uniqueID`, which equals the CoreAudio device
/// UID — so we map UID → `AudioDeviceID` and set it on the input node's audio unit.
/// No-op when unset (system default). macOS only (CoreAudio HAL device enumeration);
/// iOS uses the system default input and never calls this.
public enum AudioInputDeviceSelector {
    private static let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "audio-input")

    /// The stored preferred input UID ("" = system default). Shared key with Settings.
    public static var preferredUID: String {
        UserDefaults.standard.string(forKey: "micDeviceID") ?? ""
    }

    /// Capturing from a Bluetooth headset mic (AirPods etc.) forces the headset out of A2DP into
    /// the HFP call profile: music playback is squashed while recording, and the switch back to
    /// A2DP on stop re-syncs Bluetooth absolute volume — the sudden loud burst users report.
    /// Default-on policy: record from the built-in mic instead so the headset never leaves A2DP.
    /// Shared key with Settings (通用 › 蓝牙耳机时改用内置麦克风).
    public static var avoidBluetoothMicEnabled: Bool {
        UserDefaults.standard.object(forKey: "avoidBluetoothMic") as? Bool ?? true
    }

    /// The built-in mic's UID to capture from instead of `uid`, when the Bluetooth-avoidance
    /// policy applies (setting on + `uid` resolves to a Bluetooth input + a built-in mic exists).
    /// nil = policy doesn't apply; caller keeps the original device.
    public static func builtInFallbackUID(insteadOf uid: String) -> String? {
        guard avoidBluetoothMicEnabled,
              let device = deviceID(forUID: uid),
              isBluetooth(transportType(device)),
              let builtIn = builtInInputUID(), builtIn != uid
        else { return nil }
        // Clamshell: closing the lid hardware-disconnects the built-in mic (it still enumerates
        // but delivers silence), so rerouting there would silently break dictation. Keep the
        // Bluetooth mic in that case — a working capture beats avoiding the HFP switch.
        guard !isLidClosed() else {
            log.info("Lid closed — built-in mic is hardware-muted; keeping Bluetooth mic \(uid, privacy: .public)")
            return nil
        }
        log.info("Bluetooth mic \(uid, privacy: .public) → built-in mic (keeping headset on A2DP)")
        return builtIn
    }

    /// MacBook clamshell state via IOKit (`AppleClamshellState` on IOPMrootDomain).
    /// false on desktops (property absent) and on any lookup failure.
    private static func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        else { return false }
        return (value.takeRetainedValue() as? Bool) ?? false
    }

    /// Route `engine`'s input to the preferred device. Call before `installTap`/`start`.
    public static func apply(to engine: AVAudioEngine) {
        let uid = preferredUID
        guard !uid.isEmpty else { return }                 // system default → leave engine alone
        guard let deviceID = deviceID(forUID: uid) else {
            log.warning("Preferred mic UID not found among inputs; using system default")
            return
        }
        guard let unit = engine.inputNode.audioUnit else {
            log.error("Input node has no audio unit; cannot set device")
            return
        }
        var device = deviceID
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr {
            log.error("AudioUnitSetProperty(CurrentDevice) failed: \(status, privacy: .public)")
        }
    }

    // MARK: - CoreAudio lookup

    /// The `AudioDeviceID` whose UID matches `uid` and that has at least one input channel.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDevices().first { hasInput($0) && deviceUID($0) == uid }
    }

    private static func allDevices() -> [AudioDeviceID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    private static func transportType(_ device: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func isBluetooth(_ transport: UInt32?) -> Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func builtInInputUID() -> String? {
        allDevices()
            .first { hasInput($0) && transportType($0) == kAudioDeviceTransportTypeBuiltIn }
            .flatMap(deviceUID)
    }

    private static func deviceUID(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        return status == noErr ? (uid as String?) : nil
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }
}
#endif
