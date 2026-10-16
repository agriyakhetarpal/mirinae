// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Marker bytes and header style. See docs/protocol.md.
public struct Framing: Hashable, Sendable {
    public var startOfMessage: UInt8
    public var endOfMessage: UInt8
    public var usesLegacyHeader: Bool

    public init(startOfMessage: UInt8, endOfMessage: UInt8, usesLegacyHeader: Bool) {
        self.startOfMessage = startOfMessage
        self.endOfMessage = endOfMessage
        self.usesLegacyHeader = usesLegacyHeader
    }

    public static let standard = Framing(startOfMessage: 0xFD, endOfMessage: 0xDD, usesLegacyHeader: false)
    public static let legacy = Framing(startOfMessage: 0xFE, endOfMessage: 0xEE, usesLegacyHeader: true)
    public static let alternative = Framing(startOfMessage: 0xFC, endOfMessage: 0xCC, usesLegacyHeader: false)
}

/// One message without framing.
/// Wire: FD | size lo | size hi + flags | id | payload | crc lo | crc hi | DD
public struct SPPMessage: Hashable, Sendable {
    public var id: MessageID
    public var payload: [UInt8]
    public var isResponse: Bool
    public var isFragment: Bool

    public init(id: MessageID, payload: [UInt8] = [], isResponse: Bool = false, isFragment: Bool = false) {
        self.id = id
        self.payload = payload
        self.isResponse = isResponse
        self.isFragment = isFragment
    }

    public init(_ rawID: UInt8, _ payload: [UInt8] = []) {
        self.init(id: MessageID(rawID), payload: payload)
    }

    public var size: Int { 1 + payload.count + 2 }

    public func encoded(framing: Framing = .standard) -> [UInt8] {
        var out: [UInt8] = [framing.startOfMessage]
        if framing.usesLegacyHeader {
            out.append(isResponse ? 1 : 0)
            out.append(UInt8(truncatingIfNeeded: size))
        } else {
            var header = UInt16(size & 0x3FF)
            if isFragment { header |= 0x2000 }
            if isResponse { header |= 0x1000 }
            out.append(UInt8(header & 0xFF))
            out.append(UInt8(header >> 8))
        }
        out.append(id.rawValue)
        out.append(contentsOf: payload)
        let crc = CRC16.xmodem([id.rawValue] + payload)
        out.append(UInt8(crc & 0xFF))
        out.append(UInt8(crc >> 8))
        out.append(framing.endOfMessage)
        return out
    }
}

extension SPPMessage: CustomStringConvertible {
    public var description: String {
        let kind = isFragment ? "fragment" : (isResponse ? "response" : "request")
        return "\(id) \(kind) [\(payload.hexString)]"
    }
}

/// Incremental parser over the RFCOMM byte stream.
public final class FrameParser {
    public var framing: Framing
    public private(set) var droppedBytes = 0
    private var buffer: [UInt8] = []

    private static let maximumFrameSize = 1024 + 4
    private static let maximumBufferedBytes = 16 * 1024

    public init(framing: Framing = .standard) {
        self.framing = framing
    }

    public func reset() {
        buffer.removeAll()
    }

    public func feed(_ bytes: [UInt8]) -> [SPPMessage] {
        buffer.append(contentsOf: bytes)
        if buffer.count > Self.maximumBufferedBytes {
            droppedBytes += buffer.count
            buffer.removeAll()
            return []
        }

        var messages: [SPPMessage] = []
        while !buffer.isEmpty {
            guard buffer[0] == framing.startOfMessage else {
                dropLeadingByte()
                continue
            }
            guard buffer.count >= 3 else { break }

            let size: Int
            let isResponse: Bool
            let isFragment: Bool
            if framing.usesLegacyHeader {
                isResponse = buffer[1] == 1
                isFragment = false
                size = Int(buffer[2])
            } else {
                let header = UInt16(buffer[1]) | UInt16(buffer[2]) << 8
                size = Int(header & 0x3FF)
                isResponse = header & 0x1000 != 0
                isFragment = header & 0x2000 != 0
            }

            guard size >= 3, size + 4 <= Self.maximumFrameSize else {
                dropLeadingByte()
                continue
            }
            let total = 1 + 2 + size + 1
            guard buffer.count >= total else { break }

            let id = buffer[3]
            let payload = Array(buffer[4..<(4 + size - 3)])
            let receivedCRC = UInt16(buffer[total - 3]) | UInt16(buffer[total - 2]) << 8
            let computedCRC = CRC16.xmodem([id] + payload)
            guard receivedCRC == computedCRC, buffer[total - 1] == framing.endOfMessage else {
                dropLeadingByte()
                continue
            }

            messages.append(
                SPPMessage(id: MessageID(id), payload: payload, isResponse: isResponse, isFragment: isFragment))
            buffer.removeFirst(total)
        }
        return messages
    }

    private func dropLeadingByte() {
        buffer.removeFirst()
        droppedBytes += 1
    }
}
