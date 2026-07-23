import Foundation
import Testing
@testable import ResponsayCore

@Test func captureMode_decodesLegacyPolishAlias() throws {
    let data = #""polish""#.data(using: .utf8)!
    let mode = try JSONDecoder().decode(CaptureMode.self, from: data)
    #expect(mode == .polishSameLanguage)
}

@Test func captureMode_decodesLegacyTeachingAlias() throws {
    let data = #""teachingFeedback""#.data(using: .utf8)!
    let mode = try JSONDecoder().decode(CaptureMode.self, from: data)
    #expect(mode == .expressInEnglish)
}

@Test func captureMode_encodesCanonicalRawValue() throws {
    let data = try JSONEncoder().encode(CaptureMode.polishSameLanguage)
    let encoded = String(data: data, encoding: .utf8)
    #expect(encoded == #""polishSameLanguage""#)
}

@Test func captureMode_roundTripsIntentAwareIdentity() throws {
    let data = try JSONEncoder().encode(CaptureMode.intentAwareDictation)
    #expect(try JSONDecoder().decode(CaptureMode.self, from: data) == .intentAwareDictation)
}
