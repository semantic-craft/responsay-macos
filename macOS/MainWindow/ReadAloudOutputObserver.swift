import CoreAudio
import Foundation

/// AVAudioEngine need not emit a configuration change when the default output changes
/// without changing its graph format. Observe the hardware default as well, read-only.
final class ReadAloudOutputObserver {
    private let listener: AudioObjectPropertyListenerBlock
    let isRegistered: Bool

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        listener = { _, _ in
            MainActor.assumeIsolated { onChange() }
        }
        var address = Self.address
        isRegistered = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr
    }

    deinit {
        guard isRegistered else { return }
        var address = Self.address
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }

    private static var address: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                  mScope: kAudioObjectPropertyScopeGlobal,
                                  mElement: kAudioObjectPropertyElementMain)
    }
}
