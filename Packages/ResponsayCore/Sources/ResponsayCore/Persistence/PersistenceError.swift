import Foundation

public enum PersistenceError: LocalizedError {
    case sqlite(String)
    case invalidStoredValue(String)

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message): message
        case .invalidStoredValue(let message): message
        }
    }
}
