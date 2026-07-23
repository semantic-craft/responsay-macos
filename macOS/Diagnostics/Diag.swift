import Foundation
import OSLog
import ResponsayCore

/// Tiny emit facade for speech diagnostics. TTS also emits OSLog in Release so
/// read-aloud failure chains are reconstructable; the in-app panel remains DEBUG-only.
/// Call sites must log descriptors (model / engine / char-count / hash), never raw text.
enum Diag {
    private static let logger = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "Diagnostics")

    static func tts(
        _ level: DiagnosticEvent.Level, _ title: String,
        fields: [String: String] = [:], error: String? = nil
    ) {
        emit(.tts, level, title, fields, error)
    }

    static func asr(
        _ level: DiagnosticEvent.Level, _ title: String,
        fields: [String: String] = [:], error: String? = nil
    ) {
        emit(.asr, level, title, fields, error)
    }

    static func llm(
        _ level: DiagnosticEvent.Level, _ title: String,
        fields: [String: String] = [:], error: String? = nil
    ) {
        emit(.llm, level, title, fields, error)
    }

    /// 507: end-to-end dictation latency. Release OSLog (numeric stage/total ms + engine
    /// label only — never raw text/URL); the in-app panel stays DEBUG-only like the rest.
    static func pipeline(_ trace: LatencyTrace, engine: String?, provider: String?) {
        guard let event = DiagnosticEvent.pipeline(
            trace, engine: engine, provider: provider, timestamp: Date()) else { return }
        oslog(.info, category: .pipeline, title: event.title, fields: event.fields, error: nil)
        #if DEBUG
        Task { @MainActor in DiagnosticsCenter.shared.record(event) }
        #endif
    }

    /// 568: Intent-aware warm-cloud latency (stop→visible, per stage). Release OSLog (numeric
    /// stage/total ms + route/provider label only — never raw draft/transcript); the in-app panel
    /// stays DEBUG-only. This is the on-device observation point for #568's latency run.
    static func intentPipeline(_ trace: IntentLatencyTrace, route: String?, provider: String?) {
        guard let event = DiagnosticEvent.intentPipeline(
            trace, route: route, provider: provider, timestamp: Date()) else { return }
        oslog(.info, category: .pipeline, title: event.title, fields: event.fields, error: nil)
        #if DEBUG
        Task { @MainActor in DiagnosticsCenter.shared.record(event) }
        #endif
    }

    static func autolearn(
        _ level: DiagnosticEvent.Level, _ title: String,
        fields: [String: String] = [:], error: String? = nil
    ) {
        emit(.autolearn, level, title, fields, error)
    }

    /// #574: intent-pipeline failure category (enum names only — "verify-invalidRelationship",
    /// "decode-typeMismatch"). Release OSLog: the safe-unavailable capsule shows one generic
    /// line per family, so without this the on-device sub-reason is unrecoverable.
    static func intentFailure(_ category: String) {
        oslog(.error, category: .llm, title: "intent failed", fields: ["category": category], error: nil)
        #if DEBUG
        let event = DiagnosticEvent(
            timestamp: Date(), category: .llm, level: .error,
            title: "intent failed", fields: ["category": category], errorMessage: nil)
        Task { @MainActor in DiagnosticsCenter.shared.record(event) }
        #endif
    }

    private static func emit(
        _ category: DiagnosticEvent.Category, _ level: DiagnosticEvent.Level,
        _ title: String, _ fields: [String: String], _ error: String?
    ) {
        if category == .tts {
            oslog(level, category: category, title: title, fields: fields, error: error)
        }

        #if DEBUG
        let event = DiagnosticEvent(
            timestamp: Date(), category: category, level: level,
            title: title, fields: fields, errorMessage: error)
        Task { @MainActor in DiagnosticsCenter.shared.record(event) }
        #endif
    }

    private static func oslog(
        _ level: DiagnosticEvent.Level,
        category: DiagnosticEvent.Category,
        title: String,
        fields: [String: String],
        error: String?
    ) {
        let fieldsLine = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let line = "\(category.rawValue) \(title) \(fieldsLine) error=\(error ?? "")"
        switch level {
        case .info:
            logger.info("\(line, privacy: .public)")
        case .warning:
            logger.warning("\(line, privacy: .public)")
        case .error:
            logger.error("\(line, privacy: .public)")
        }
    }
}
