import Foundation

public enum IntentRoutePolicy: String, Codable, Sendable, Equatable {
    case unavailable
    case injectedCompiler
}
