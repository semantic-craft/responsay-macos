import Compression
import Foundation

/// Standard gzip (RFC 1952). Foundation ships no gzip, and the Volcengine
/// bidirectional-streaming ASR protocol gzips both the request JSON and every audio
/// frame (and the server gzips its responses) — so this wraps the `Compression`
/// framework's raw DEFLATE (`COMPRESSION_ZLIB` = RFC 1951, no wrapper) with the gzip
/// header + CRC32/ISIZE trailer. Scoped to the realtime ASR path, not a general codec.
enum Gzip {
    enum Failure: Error, Sendable { case notGzip, truncated, inflateFailed }

    /// gzip header: magic, DEFLATE method, no flags, mtime 0, no extra flags, OS unknown.
    private static let header: [UInt8] = [0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff]

    static func compress(_ data: Data) -> Data {
        // Empty input has no DEFLATE output from `Compression`; the canonical empty raw
        // stream is the fixed-Huffman end-of-block `03 00` (matches `printf '' | gzip`).
        let body = data.isEmpty ? Data([0x03, 0x00]) : rawDeflate(data)
        var out = Data(header)
        out.append(body)
        appendLE(crc32(data), to: &out)
        appendLE(UInt32(truncatingIfNeeded: data.count), to: &out)
        return out
    }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08 else {
            throw Failure.notGzip
        }
        let flg = bytes[3]
        var offset = 10
        if flg & 0x04 != 0 {   // FEXTRA
            guard offset + 2 <= bytes.count else { throw Failure.truncated }
            let xlen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flg & 0x08 != 0 { offset = try skipZeroTerminated(bytes, from: offset) }  // FNAME
        if flg & 0x10 != 0 { offset = try skipZeroTerminated(bytes, from: offset) }  // FCOMMENT
        if flg & 0x02 != 0 { offset += 2 }                                           // FHCRC
        guard offset <= bytes.count - 8 else { throw Failure.truncated }

        let deflate = bytes[offset..<(bytes.count - 8)]
        let isize = Int(readLE(bytes, at: bytes.count - 4))
        let out = try rawInflate(deflate, expectedSize: isize)
        guard crc32(out) == readLE(bytes, at: bytes.count - 8) else { throw Failure.inflateFailed }
        return out
    }

    // MARK: - DEFLATE via Compression framework (raw, no zlib/gzip wrapper)

    private static func rawDeflate(_ data: Data) -> Data {
        let src = [UInt8](data)
        let capacity = src.count + src.count / 2 + 128   // headroom over stored-block worst case
        var dst = [UInt8](repeating: 0, count: capacity)
        let written = compression_encode_buffer(&dst, capacity, src, src.count, nil, COMPRESSION_ZLIB)
        return Data(dst.prefix(written))
    }

    private static func rawInflate(_ body: ArraySlice<UInt8>, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        let src = Array(body)
        var dst = [UInt8](repeating: 0, count: expectedSize)
        let written = compression_decode_buffer(&dst, expectedSize, src, src.count, nil, COMPRESSION_ZLIB)
        guard written == expectedSize else { throw Failure.inflateFailed }
        return Data(dst.prefix(written))
    }

    // MARK: - Helpers

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
        var i = start
        while i < bytes.count, bytes[i] != 0 { i += 1 }
        guard i < bytes.count else { throw Failure.truncated }
        return i + 1   // step past the terminating NUL
    }

    private static func appendLE(_ value: UInt32, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func readLE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }

    /// IEEE CRC-32 (reflected poly 0xEDB88320) — the gzip trailer checksum.
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}
