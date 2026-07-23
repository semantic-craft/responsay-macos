import Foundation
import Testing
@testable import ResponsayCore

/// The Volcengine bidirectional-streaming ASR protocol gzip-compresses both the
/// request JSON and every audio frame, and the server gzips its responses — so a
/// real gzip codec is a hard prerequisite (Foundation ships none). These pin that
/// the codec is *standard* gzip (interoperable with the server / `gzip(1)`), not a
/// self-consistent private format.
@Suite("Gzip")
struct GzipTests {

    /// Interop: a stream produced by the system `gzip(1)` must decompress to the
    /// original bytes. Vector = `printf 'hello, 火山 gzip 你好世界' | gzip -c`.
    @Test func decompressesStandardGzipVector() throws {
        let gz = Self.hex(
            "1f8b0800b1fa476a0003011f00e0ff68656c6c6f2c20e781abe5b1b120" +
            "677a697020e4bda0e5a5bde4b896e7958cdc3a62da1f000000")
        let out = try Gzip.decompress(gz)
        #expect(String(data: out, encoding: .utf8) == "hello, 火山 gzip 你好世界")
    }

    @Test func roundTripsUnicodeAndBinary() throws {
        let payload = Data(("{\"model_name\":\"bigmodel\",\"text\":\"你好，法言\"}" +
                            String(repeating: "A", count: 4096)).utf8)
        let restored = try Gzip.decompress(Gzip.compress(payload))
        #expect(restored == payload)
    }

    @Test func compressEmitsGzipMagic() throws {
        let out = Gzip.compress(Data("x".utf8))
        #expect(Array(out.prefix(3)) == [0x1f, 0x8b, 0x08])
    }

    private static func hex(_ s: String) -> Data {
        var data = Data(capacity: s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            data.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return data
    }
}
