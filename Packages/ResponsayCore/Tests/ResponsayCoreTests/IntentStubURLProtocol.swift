import Foundation

// Own stub class + static state so this suite never races the other LLM stub suites
// (each direct-API suite owns its URLProtocol subclass — see LLMActionsStubURLProtocol).
final class IntentStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var data = Data()
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requestBody = Data()
    nonisolated(unsafe) static var requestURL: URL?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestURL = request.url
        Self.requestBody = request.httpBody ?? Self.readStream(request.httpBodyStream)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status,
            httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func readStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
