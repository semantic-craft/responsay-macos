import AppKit
import AVFoundation
import OSLog
import ResponsayCore

private enum InteractionSoundEvent {
    case captureStart
    case captureStop

    /// Style-specific resource name, e.g. `ResponsayCaptureStart_PianoUpright`.
    func resource(for style: InteractionSoundStyle) -> String {
        "\(base)_\(style.resourceSuffix)"
    }

    /// Legacy single-timbre cue, kept as a fallback if a style file is missing.
    var legacyResource: String {
        switch self {
        case .captureStart: "ResponsayCaptureStartCue"
        case .captureStop: "ResponsayCaptureStopCue"
        }
    }

    private var base: String {
        switch self {
        case .captureStart: "ResponsayCaptureStart"
        case .captureStop: "ResponsayCaptureStop"
        }
    }

    var fallbackNames: [String] {
        switch self {
        case .captureStart: ["Tink", "Pop"]
        case .captureStop: ["Pop", "Tink"]
        }
    }

    var label: String {
        switch self {
        case .captureStart: "capture start"
        case .captureStop: "capture stop"
        }
    }
}

@MainActor
final class InteractionSoundPlayer {
    static let shared = InteractionSoundPlayer()

    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "interaction-sound")
    private var players: [String: AVAudioPlayer] = [:]   // keyed by resource name
    private var fallbackSounds: [String: NSSound] = [:]

    private init() {}

    func playCaptureStart() {
        play(.captureStart)
    }

    func playCaptureStop() {
        play(.captureStop)
    }

    /// 截图复制 completion cue — a single fixed chime (borrowed from anamra's CaptureDone), no timbre
    /// styling. Falls back to the system "Glass" sound if the bundled WAV is missing.
    func playSnapCopyDone() {
        guard let player = audioPlayer(named: "ResponsaySnapCopyDone") else {
            NSSound(named: "Glass")?.play()
            return
        }
        if player.isPlaying {
            player.stop()
        }
        player.currentTime = 0
        if !player.play() {
            log.warning("Snap-copy sound did not start")
        }
    }

    private func play(_ event: InteractionSoundEvent) {
        let style = InteractionSoundStyle.current()
        // Prefer the selected style; fall back to the legacy cue, then a system sound.
        if let player = audioPlayer(named: event.resource(for: style))
            ?? audioPlayer(named: event.legacyResource) {
            if player.isPlaying {
                player.stop()
            }
            player.currentTime = 0
            if !player.play() {
                log.warning("Interaction sound did not start: \(event.label, privacy: .public)")
            }
            return
        }

        guard let sound = fallbackSound(for: event) else {
            log.warning("Interaction sound unavailable: \(event.label, privacy: .public)")
            return
        }
        if sound.isPlaying {
            sound.stop()
        }
        sound.currentTime = 0
        sound.play()
    }

    private func audioPlayer(named resource: String) -> AVAudioPlayer? {
        if let player = players[resource] {
            return player
        }

        guard let url = Bundle.main.url(forResource: resource, withExtension: "wav") else {
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = 1
            player.prepareToPlay()
            players[resource] = player
            return player
        } catch {
            log.warning("Failed to load interaction sound \(resource, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fallbackSound(for event: InteractionSoundEvent) -> NSSound? {
        if let sound = fallbackSounds[event.label] {
            return sound
        }

        for name in event.fallbackNames {
            if let sound = NSSound(named: name) {
                fallbackSounds[event.label] = sound
                return sound
            }
        }

        return nil
    }
}
