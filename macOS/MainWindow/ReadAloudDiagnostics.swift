import CryptoKit
import Foundation
import ResponsayCore

struct ReadAloudTransaction: Equatable, Sendable {
    let requestID: UUID
    let traceID: String

    init(requestID: UUID = UUID()) {
        self.requestID = requestID
        traceID = requestID.uuidString
    }
}

struct ReadAloudDiagnosticContext: Sendable {
    let transaction: ReadAloudTransaction
    let source: String
    let chars: Int
    let hash: String

    init(transaction: ReadAloudTransaction, text: String, source: String = "prosodyAnalysis") {
        self.transaction = transaction
        self.source = source
        chars = text.count
        hash = ReadAloudDiagnostics.hash(text)
    }

    func fields(
        mode: String,
        phase: String,
        attempt: Int,
        provider: String,
        fallback: String,
        result: String,
        extra: [String: String] = [:]
    ) -> [String: String] {
        var fields = [
            "traceID": transaction.traceID,
            "requestID": transaction.requestID.uuidString,
            "source": source,
            "chars": String(chars),
            "hash": hash,
            "attempt": String(attempt),
            "provider": provider,
            "mode": mode,
            "phase": phase,
            "fallback": fallback,
            "result": result,
        ]
        fields.merge(extra) { _, new in new }
        return fields
    }
}

enum ReadAloudDiagnostics {
    static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func errorCode(_ error: Error) -> String {
        guard let error = error as? TTSError else { return String(describing: type(of: error)) }
        return switch error {
        case .modelNotInstalled: "modelNotInstalled"
        case .emptyText: "emptyText"
        case .missingAPIKey: "missingAPIKey"
        case .http(let status): "http_\(status)"
        case .providerReturnedNoAudio: "providerReturnedNoAudio"
        case .network: "network"
        case .synthesisFailed: "synthesisFailed"
        }
    }
}
