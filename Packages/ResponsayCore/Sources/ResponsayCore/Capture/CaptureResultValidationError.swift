import Foundation

public enum CaptureResultValidationError: Error, Equatable {
    case missingInsertText(mode: CaptureMode)
    case missingIntentInsertRoute
}
