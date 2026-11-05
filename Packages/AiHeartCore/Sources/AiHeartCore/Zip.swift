import Compression
import Foundation

// Minimal ZIP container (M11 export). STORED entries only (no compression), UTF-8 names,
// CRC-32, local headers + central directory + end record. Opens in Archive Utility and Numbers.
// Limits: no ZIP64, so at most 65,535 entries and under 4 GiB in total.

public enum ZipError: Error, Equatable {
    case notAZip
    case truncated
    case unsupported(String)
    case badChecksum(String)
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for b in buf { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func appendLE32(_ v: UInt32) { for s in stride(from: 0, to: 32, by: 8) { append(UInt8((v >> UInt32(s)) & 0xFF)) } }
}

public struct ZipWriter {
    private struct Entry {
        var name: Data
        var crc: UInt32
        var size: UInt32
        var offset: UInt32
    }

    private var body = Data()
    private var entries: [Entry] = []

    public init() {}

    /// 1980-01-01 00:00, so the same input always gives the same bytes.
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = 0x0021
    private static let utf8Flag: UInt16 = 0x0800

    public mutating func add(_ path: String, _ data: Data) {
        let name = Data(path.utf8)
        let entry = Entry(name: name, crc: CRC32.checksum(data), size: UInt32(truncatingIfNeeded: data.count),
                          offset: UInt32(truncatingIfNeeded: body.count))
        body.appendLE32(0x0403_4B50)
        body.appendLE16(20)                      // version needed
        body.appendLE16(Self.utf8Flag)
        body.appendLE16(0)                       // method: stored
        body.appendLE16(Self.dosTime)
        body.appendLE16(Self.dosDate)
        body.appendLE32(entry.crc)
        body.appendLE32(entry.size)              // compressed
        body.appendLE32(entry.size)              // uncompressed
        body.appendLE16(UInt16(truncatingIfNeeded: name.count))
        body.appendLE16(0)                       // extra length
        body.append(name)
        body.append(data)
        entries.append(entry)
    }

    public func finish() -> Data {
        var out = body
        let centralStart = out.count
        for e in entries {
            out.appendLE32(0x0201_4B50)
            out.appendLE16(20)                   // version made by
            out.appendLE16(20)                   // version needed
            out.appendLE16(Self.utf8Flag)
            out.appendLE16(0)
            out.appendLE16(Self.dosTime)
            out.appendLE16(Self.dosDate)
            out.appendLE32(e.crc)
            out.appendLE32(e.size)
            out.appendLE32(e.size)
            out.appendLE16(UInt16(truncatingIfNeeded: e.name.count))
            out.appendLE16(0)                    // extra
            out.appendLE16(0)                    // comment
            out.appendLE16(0)                    // disk
            out.appendLE16(0)                    // internal attrs
            out.appendLE32(0)                    // external attrs
            out.appendLE32(e.offset)
            out.append(e.name)
        }
        let centralSize = out.count - centralStart
        out.appendLE32(0x0605_4B50)
        out.appendLE16(0); out.appendLE16(0)
        out.appendLE16(UInt16(truncatingIfNeeded: entries.count))
        out.appendLE16(UInt16(truncatingIfNeeded: entries.count))
        out.appendLE32(UInt32(truncatingIfNeeded: centralSize))
        out.appendLE32(UInt32(truncatingIfNeeded: centralStart))
        out.appendLE16(0)                        // comment length
        return out
    }
}

public enum ZipReader {
    /// True if the bytes start like a ZIP file.
    public static func isZip(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    /// Reads stored entries (what `ZipWriter` writes) and deflated entries (what Netflix, Spotify and
    /// Google send). Checks every CRC. Directory entries are skipped. `include` picks which names to
    /// read, so a large data download only inflates the files that are needed.
    public static func entries(_ data: Data, include: (String) -> Bool = { _ in true }) throws -> [String: Data] {
        let b = [UInt8](data)
        func u16(_ i: Int) throws -> Int {
            guard i >= 0, i + 2 <= b.count else { throw ZipError.truncated }
            return Int(b[i]) | Int(b[i + 1]) << 8
        }
        func u32(_ i: Int) throws -> Int {
            guard i >= 0, i + 4 <= b.count else { throw ZipError.truncated }
            return Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24
        }
        guard b.count >= 22 else { throw ZipError.notAZip }
        // End record: scan backwards (it may be followed by a comment of up to 65,535 bytes).
        var eocd = -1
        var i = b.count - 22
        let lowest = max(0, b.count - 22 - 65535)
        while i >= lowest {
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 0x05, b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let count = try u16(eocd + 10)
        var p = try u32(eocd + 16)
        var result: [String: Data] = [:]
        for _ in 0..<count {
            guard try u32(p) == 0x0201_4B50 else { throw ZipError.notAZip }
            let method = try u16(p + 10)
            let crc = UInt32(try u32(p + 16))
            let csize = try u32(p + 20)
            let usize = try u32(p + 24)
            let nlen = try u16(p + 28), xlen = try u16(p + 30), clen = try u16(p + 32)
            let local = try u32(p + 42)
            guard p + 46 + nlen <= b.count else { throw ZipError.truncated }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            p += 46 + nlen + xlen + clen
            if name.hasSuffix("/") || !include(name) { continue }
            guard method == 0 || method == 8 else { throw ZipError.unsupported("compression method \(method) for \(name)") }
            if method == 0, csize != usize { throw ZipError.unsupported("stored entry with two sizes: \(name)") }
            guard try u32(local) == 0x0403_4B50 else { throw ZipError.notAZip }
            let start = local + 30 + (try u16(local + 26)) + (try u16(local + 28))
            guard start + csize <= b.count else { throw ZipError.truncated }
            let raw = Data(b[start..<(start + csize)])
            let payload: Data
            if method == 8 {
                guard let out = inflate(raw, size: usize) else { throw ZipError.badChecksum(name) }
                payload = out
            } else {
                payload = raw
            }
            guard CRC32.checksum(payload) == crc else { throw ZipError.badChecksum(name) }
            result[name] = payload
        }
        return result
    }
}

extension ZipReader {
    /// Raw DEFLATE (ZIP method 8) to `size` bytes, with Apple's Compression (COMPRESSION_ZLIB is raw deflate).
    static func inflate(_ data: Data, size: Int) -> Data? {
        if size == 0 { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == size ? out : nil
    }

    /// Raw DEFLATE, for tests and small files.
    static func deflate(_ data: Data) -> Data {
        var out = Data(count: max(64, data.count + 1024))
        let n = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, dst.count,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return out.prefix(n)
    }
}
