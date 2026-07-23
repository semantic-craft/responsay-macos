import Foundation
@testable import ResponsayCore

@MainActor
final class MockSpeechCaptureService: SpeechCaptureService {
    var transcriptToReturn = ""
    var startError: Error?
    private(set) var started = false
    private(set) var stopCalls = 0
    private(set) var captureProfiles: [SpeechCaptureProfile] = []

    let levels: AsyncStream<Float>
    private let levelCont: AsyncStream<Float>.Continuation
    init() { (levels, levelCont) = AsyncStream.makeStream(of: Float.self) }

    /// 测试用:推一个电平值。
    func emitLevel(_ v: Float) { levelCont.yield(v) }

    func start(locale: CaptureLocale) throws {
        if let startError { throw startError }
        started = true
    }
    func stop() async throws -> String {
        stopCalls += 1
        return transcriptToReturn
    }
}

extension MockSpeechCaptureService: SpeechCaptureProfileConfigurable {
    func setCaptureProfile(_ profile: SpeechCaptureProfile) {
        captureProfiles.append(profile)
    }
}

struct MockCoachAPI: CoachAPI {
    var result: ExpressionResult?
    var error: CoachAPIError?

    func express(
        _ intent: String,
        context: ExpressionContext?,
        target: TranslationTargetLanguage
    ) async throws -> ExpressionResult {
        if let error { throw error }
        return result ?? ExpressionResult(idiomatic: "", original: intent, reasons: [])
    }
    func ask(_ question: String, context: String) async throws -> ExpressionResult {
        if let error { throw error }
        return result ?? ExpressionResult(idiomatic: "", original: question, reasons: [])
    }
}

struct MockTextPolishAPI: TextPolishAPI {
    var result: PolishResult?
    var error: CoachAPIError?

    func polish(_ text: String) async throws -> PolishResult {
        if let error { throw error }
        return result ?? PolishResult(text: text, original: text)
    }
}

struct MockTextTranslationAPI: TextTranslationAPI {
    var result: TranslationResult?
    var error: CoachAPIError?

    func translate(
        _ text: String,
        target: TranslationTargetLanguage,
        style: TextTranslationStyle
    ) async throws -> TranslationResult {
        if let error { throw error }
        return result ?? TranslationResult(text: text, original: text, targetLanguage: target.rawValue)
    }
}

@MainActor
final class MockTextInserter: TextInserter {
    private(set) var inserted: [String] = []
    var error: InsertError?
    func insert(_ text: String) async throws {
        if let error { throw error }
        inserted.append(text)
    }
}
