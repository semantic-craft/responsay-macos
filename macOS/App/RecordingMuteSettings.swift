import Combine
import Foundation

/// Observe only actual changes to the recording preference. Recovery-journal
/// writes must not re-engage a mute that another operation has just released.
enum RecordingMuteSettings {
    static let key = "muteWhileRecording"

    static func enabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    static func changes(defaults: UserDefaults = .standard,
                        center: NotificationCenter = .default) -> AnyPublisher<Bool, Never> {
        center.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in enabled(in: defaults) }
            .prepend(enabled(in: defaults))
            .removeDuplicates()
            .dropFirst()
            .eraseToAnyPublisher()
    }
}
