// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Bounds-checked cursor over a payload. Reads past the end return nil.
public struct ByteReader {
    public let bytes: [UInt8]
    public private(set) var offset: Int

    public init(_ bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    public var remaining: Int { max(bytes.count - offset, 0) }
    public var isAtEnd: Bool { remaining == 0 }

    public subscript(index: Int) -> UInt8? {
        bytes.indices.contains(index) ? bytes[index] : nil
    }

    public mutating func byte() -> UInt8? {
        guard let value = self[offset] else { return nil }
        offset += 1
        return value
    }

    public mutating func bool() -> Bool? {
        byte().map { $0 != 0 }
    }

    public mutating func int16() -> Int16? {
        guard remaining >= 2 else { return nil }
        let value = Int16(bitPattern: UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)
        offset += 2
        return value
    }

    public mutating func uint16() -> UInt16? {
        int16().map { UInt16(bitPattern: $0) }
    }

    public mutating func int32() -> Int32? {
        guard remaining >= 4 else { return nil }
        var value: UInt32 = 0
        for i in 0..<4 { value |= UInt32(bytes[offset + i]) << (8 * UInt32(i)) }
        offset += 4
        return Int32(bitPattern: value)
    }

    public mutating func bytes(_ count: Int) -> [UInt8]? {
        guard remaining >= count else { return nil }
        let slice = Array(bytes[offset..<offset + count])
        offset += count
        return slice
    }

    public mutating func ascii(_ count: Int) -> String? {
        bytes(count).map { Self.ascii($0) }
    }

    public mutating func skip(_ count: Int) {
        offset = min(offset + count, bytes.count)
    }

    public static func ascii(_ bytes: [UInt8]) -> String {
        String(decoding: bytes.filter { $0 != 0 }, as: UTF8.self)
    }

    public static func int16(_ bytes: [UInt8], at index: Int) -> Int16? {
        var reader = ByteReader(bytes, offset: index)
        return reader.int16()
    }

    public static func macAddress(_ bytes: [UInt8], at index: Int) -> String? {
        guard bytes.count >= index + 6 else { return nil }
        return bytes[index..<index + 6].map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

public extension Array where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    init?(hexString: String) {
        let cleaned = hexString.filter { !$0.isWhitespace && $0 != "," }
        guard cleaned.count % 2 == 0 else { return nil }
        var result: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        self = result
    }
}
