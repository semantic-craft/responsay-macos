import Foundation

/// How long a loaded local engine stays resident after its last use, parsed from
/// the `localEngineTTL` setting ("0" / minutes / "never"). Mirrors openless's
/// `keep_loaded_secs` release policy (cache.rs).
enum EngineKeepAlive: Equatable, Sendable {
    case immediate          // release as soon as the utterance is decoded
    case minutes(Int)       // release after N idle minutes
    case keepForever        // never auto-release

    init(raw: String) {
        switch raw {
        case "0": self = .immediate
        case "never": self = .keepForever
        default: self = .minutes(Int(raw) ?? 5)
        }
    }

    var idleNanoseconds: UInt64? {
        switch self {
        case .immediate: 0
        case .keepForever: nil
        case .minutes(let m): UInt64(max(0, m)) * 60 * 1_000_000_000
        }
    }
}
