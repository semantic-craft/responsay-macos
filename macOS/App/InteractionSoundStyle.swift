import Foundation

/// User-selectable timbre for the capture start / stop cues.
enum InteractionSoundStyle: String, CaseIterable {
    case pianoUpright   // 立式钢琴
    case marimba        // 软木
    case beep
    case blip
    case blop
    case bong
    case clack
    case ding
    case sonar
    case thump
    case twoTone

    static let key = "interactionSound.style"

    var title: String {
        switch self {
        case .pianoUpright: "立式钢琴"
        case .marimba: "软木"
        case .beep: "哔声"
        case .blip: "滴答声"
        case .blop: "咕嘟声"
        case .bong: "钟声"
        case .clack: "咔嗒声"
        case .ding: "叮声"
        case .sonar: "声呐音"
        case .thump: "砰声"
        case .twoTone: "双音"
        }
    }

    /// Resource-name suffix for the bundled WAV pair.
    var resourceSuffix: String {
        switch self {
        case .pianoUpright: "PianoUpright"
        case .marimba: "Marimba"
        case .beep: "Beep"
        case .blip: "Blip"
        case .blop: "Blop"
        case .bong: "Bong"
        case .clack: "Clack"
        case .ding: "Ding"
        case .sonar: "Sonar"
        case .thump: "Thump"
        case .twoTone: "TwoTone"
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> InteractionSoundStyle {
        InteractionSoundStyle(rawValue: defaults.string(forKey: key) ?? "") ?? .pianoUpright
    }
}
