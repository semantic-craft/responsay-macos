import CoreAudio
import Foundation

/// All hardware access and callbacks are serialized on the main queue.
@MainActor
final class CoreAudioOutputMuteBackend: AudioOutputMuteBackend {
    private var callback: (@MainActor (String?, UInt32?) -> Void)?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private func address(_ selector: AudioObjectPropertySelector, output: Bool = false) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private var devices: [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var result = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !result.isEmpty,
              AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &result) == noErr else { return [] }
        return result
    }

    private func uid(_ device: AudioDeviceID) -> String? {
        var addr = address(kAudioDevicePropertyDeviceUID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    var defaultOutputUID: String? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return uid(device)
    }

    func mute(for uid: String) -> UInt32? {
        guard let device = devices.first(where: { self.uid($0) == uid }) else { return nil }
        var addr = address(kAudioDevicePropertyMute, output: true)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    func setMute(_ value: UInt32, for uid: String) -> Bool {
        guard let device = devices.first(where: { self.uid($0) == uid }) else { return false }
        var addr = address(kAudioDevicePropertyMute, output: true)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { return false }
        var value = value
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    func observe(_ change: @escaping @MainActor (String?, UInt32?) -> Void) {
        callback = change
        guard listeners.isEmpty else { return }
        add(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultOutputDevice))
        add(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDevices), rebuild: true)
        for device in devices {
            add(device, address(kAudioDevicePropertyMute, output: true), uid: uid(device))
        }
    }

    private func add(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, uid: String? = nil, rebuild: Bool = false) {
        var addr = addr
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, let callback = self.callback else { return }
                let value = uid.flatMap { self.mute(for: $0) }
                if rebuild {
                    self.stopObserving()
                    self.observe(callback)
                }
                callback(uid, value)
            }
        }
        if AudioObjectAddPropertyListenerBlock(object, &addr, .main, block) == noErr {
            listeners.append((object, addr, block))
        }
    }

    func stopObserving() {
        callback = nil
        for (object, var addr, block) in listeners {
            AudioObjectRemovePropertyListenerBlock(object, &addr, .main, block)
        }
        listeners.removeAll()
    }
}
