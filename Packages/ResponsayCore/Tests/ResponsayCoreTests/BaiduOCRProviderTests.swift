import CoreGraphics
import Foundation
import Testing
@testable import ResponsayCore

// Baidu OCR provider (general_basic / accurate_basic). Two-step auth: client_id+client_secret →
// access_token, then call OCR. Real HTTP is E2E (needs a key); here we cover the pure seams — URL
// construction, token parsing, words_result join, form-body urlencode, and the injected path.
struct BaiduOCRProviderTests {

    private func tinyImage() -> CGImage {
        let ctx = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return ctx.makeImage()!
    }

    @Test func tokenURLCarriesCredentials() {
        let url = BaiduOCRProvider.tokenURL(apiKey: "KKK", secretKey: "SSS")!.absoluteString
        #expect(url.hasPrefix("https://aip.baidubce.com/oauth/2.0/token"))
        #expect(url.contains("grant_type=client_credentials"))
        #expect(url.contains("client_id=KKK"))
        #expect(url.contains("client_secret=SSS"))
    }

    @Test func ocrURLAccurateVsBasic() {
        #expect(BaiduOCRProvider.ocrURL(accessToken: "T", accurate: false)!.absoluteString
            .hasPrefix("https://aip.baidubce.com/rest/2.0/ocr/v1/general_basic?access_token=T"))
        #expect(BaiduOCRProvider.ocrURL(accessToken: "T", accurate: true)!.absoluteString
            .hasPrefix("https://aip.baidubce.com/rest/2.0/ocr/v1/accurate_basic?access_token=T"))
    }

    @Test func parseTokenExtractsAccessToken() throws {
        let json = #"{"access_token":"24.abc","expires_in":2592000}"#
        #expect(try BaiduOCRProvider.parseToken(Data(json.utf8)) == "24.abc")
    }

    @Test func parseTokenThrowsOnError() {
        let json = #"{"error":"invalid_client","error_description":"unknown client id"}"#
        #expect(throws: CloudOCRError.self) {
            _ = try BaiduOCRProvider.parseToken(Data(json.utf8))
        }
    }

    @Test func parseOCRJoinsWordsResult() throws {
        let json = #"{"words_result":[{"words":"第一行"},{"words":"第二行"}],"words_result_num":2}"#
        #expect(try BaiduOCRProvider.parseOCRResponse(Data(json.utf8)) == "第一行\n第二行")
    }

    @Test func parseOCRThrowsOnErrorCode() {
        let json = #"{"error_code":110,"error_msg":"Access token invalid or no longer valid"}"#
        #expect(throws: CloudOCRError.self) {
            _ = try BaiduOCRProvider.parseOCRResponse(Data(json.utf8))
        }
    }

    @Test func formBodyURLEncodesBase64() {
        let body = BaiduOCRProvider.formBody(base64: "ab+/=")
        #expect(String(data: body, encoding: .utf8) == "image=ab%2B%2F%3D")
    }

    @Test func recognizeUsesInjectedTranscriber() async throws {
        let provider = BaiduOCRProvider { _, _ in "百度转写正文" }
        let result = try await provider.recognize(tinyImage())
        #expect(result.text == "百度转写正文")
        #expect(result.regions.isEmpty)
        #expect(result.textStructure == .rawLines)
        #expect(!result.isEmpty)
    }

    @Test func notConfiguredThrows() async {
        let provider = BaiduOCRProvider(credentialsProvider: { nil })
        await #expect(throws: CloudOCRError.notConfigured) {
            _ = try await provider.recognize(tinyImage())
        }
    }

    @Test func engineIdentity() {
        #expect(BaiduOCRProvider { _, _ in "" }.id == "baidu-ocr")
    }
}
