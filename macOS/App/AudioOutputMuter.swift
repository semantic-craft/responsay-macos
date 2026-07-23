import CoreAudio
import Foundation
import OSLog
import ResponsayCore

/// Mutes the system default output device while the mic is live, so background
/// audio (music / video in other apps) doesn't bleed into the recording.
///
/// Reversible and crash-safe: the prior mute state is restored on stop, and is
/// also persisted so a crash mid-recording can't leave the user's output stuck
/// muted — `recoverStuckMuteIfNeeded()` unsticks it on next launch.
@MainActor
final class AudioOutputMuter {
    static let shared = AudioOutputMuter()

    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "audio-mute")
    private static let priorKey = "audioMute.priorMute"   // presence == "we left it muted"

    private var muted: (device: AudioDeviceID, prior: UInt32)?
    private var pending: DispatchWorkItem?

    private init() {}

    var isOutputMutedByApp: Bool { muted != nil }

    /// Mute after `delay` so a start cue can be heard first. Idempotent.
    func engage(afterDelay delay: TimeInterval) {
        guard muted == nil else { return }
        pending?.cancel()
        if delay <= 0 {
            applyMute()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.applyMute() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Restore the prior state. Idempotent; safe to call when nothing was muted.
    func disengage() {
        pending?.cancel()
        pending = nil
        guard let m = muted else { return }
        setMute(device: m.device, value: m.prior)
        UserDefaults.standard.removeObject(forKey: Self.priorKey)
        muted = nil
    }

    /// Call once at launch: if a previous run died while muted, restore output.
    func recoverStuckMuteIfNeeded() {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.priorKey) != nil, let device = defaultOutputDevice() else { return }
        // ponytail: restore the *current* default device to the saved prior (almost
        // always 0/unmuted). A device swap across reboot is rare; the user can fix
        // it from the menu bar if so.
        setMute(device: device, value: UInt32(d.integer(forKey: Self.priorKey)))
        d.removeObject(forKey: Self.priorKey)
        log.info("recovered from stuck mute after unclean exit")
    }

    private func applyMute() {
        pending = nil
        guard muted == nil, let device = defaultOutputDevice(), let prior = getMute(device: device) else { return }
        guard setMute(device: device, value: 1) else { return }
        muted = (device, prior)
        UserDefaults.standard.set(Int(prior), forKey: Self.priorKey)
    }

    // MARK: - CoreAudio

    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private func defaultOutputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private func getMute(device: AudioDeviceID) -> UInt32? {
        var addr = muteAddress
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    @discardableResult
    private func setMute(device: AudioDeviceID, value: UInt32) -> Bool {
        var addr = muteAddress
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue
        else {
            log.info("default output device has no settable master mute; skipping")
            return false
        }
        var v = value
        let status = AudioObjectSetPropertyData(
            device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        if status != noErr { log.warning("set mute failed: \(status)") }
        return status == noErr
    }
}
