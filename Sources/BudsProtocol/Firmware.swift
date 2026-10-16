// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A firmware image as distributed for the earbuds: a small table of segments, each with an
/// id, a CRC-32, an offset, and a size, followed by the segment bytes.
public struct FirmwareImage: Sendable {
    public struct Segment: Sendable {
        public let id: UInt8
        public let crc32: UInt32
        public let position: Int
        public let data: [UInt8]
    }

    public static let magic: UInt32 = 0xCAFECAFE

    public let totalSize: Int
    public let segments: [Segment]
    public let trailingCRC: UInt32
    public let bytes: [UInt8]

    public enum ParseError: Error { case tooShort, badMagic, noSegments, truncated, checksum(segment: UInt8) }

    public init(_ bytes: [UInt8]) throws {
        guard bytes.count >= 16 else { throw ParseError.tooShort }
        var r = ByteReader(bytes)
        guard r.int32().map({ UInt32(bitPattern: $0) }) == Self.magic else { throw ParseError.badMagic }
        let total = Int(r.int32() ?? 0)
        let count = Int(r.int32() ?? 0)
        guard count > 0, count < 64 else { throw ParseError.noSegments }
        var segments: [Segment] = []
        for _ in 0..<count {
            guard let id = r.int32(), let crc = r.int32(), let position = r.int32(), let size = r.int32() else {
                throw ParseError.truncated
            }
            let start = Int(position), length = Int(size)
            guard start >= 0, length >= 0, start + length <= bytes.count else { throw ParseError.truncated }
            let data = Array(bytes[start..<start + length])
            guard CRC32.checksum(data) == UInt32(bitPattern: crc) else {
                throw ParseError.checksum(segment: UInt8(truncatingIfNeeded: id))
            }
            segments.append(
                Segment(id: UInt8(truncatingIfNeeded: id), crc32: UInt32(bitPattern: crc), position: start, data: data))
        }
        self.bytes = bytes
        totalSize = total
        self.segments = segments
        trailingCRC = bytes.suffix(4).enumerated().reduce(UInt32(0)) {
            $0 | UInt32($1.element) << (8 * UInt32($1.offset))
        }
    }

    public func segment(id: UInt8) -> Segment? { segments.first { $0.id == id } }

    /// The model this image is for, found by its SKU pattern in the image.
    public var model: BudsModel? {
        BudsModel.allCases.sorted { $0.skuPattern.count > $1.skuPattern.count }.first { model in
            bytes.contains(sequence: Array(model.buildPrefix.utf8))
        }
    }
}

public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in bytes { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}

extension Array where Element == UInt8 {
    func contains(sequence needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, count >= needle.count else { return false }
        var i = 0
        while i + needle.count <= count {
            if self[i] == needle[0], Array(self[i..<i + needle.count]) == needle { return true }
            i += 1
        }
        return false
    }
}

/// Firmware build names such as "R177XXU0AYF1": model, region, variant, then year, month, and
/// revision as single characters.
public struct FirmwareBuild: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let name: String
    public let year: Int
    public let month: Int
    public let revision: Int

    public init?(name: String) {
        guard name.count >= 12 else { return nil }
        let chars = Array(name.suffix(3))
        let years = Array("OPQRSTUVWXYZ"), months = Array("ABCDEFGHIJKL")
        let revisions = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard let y = years.firstIndex(of: chars[0]), let m = months.firstIndex(of: chars[1]),
            let r = revisions.firstIndex(of: chars[2])
        else { return nil }
        self.name = name
        year = 2015 + y
        month = m + 1
        revision = r
    }

    public init(name: String, year: Int, month: Int, revision: Int) {
        self.name = name
        self.year = year
        self.month = month
        self.revision = revision
    }

    public static func < (lhs: FirmwareBuild, rhs: FirmwareBuild) -> Bool {
        (lhs.year, lhs.month, lhs.revision) < (rhs.year, rhs.month, rhs.revision)
    }

    public var description: String { name }
}

/// Messages exchanged during a firmware transfer.
public enum Fota {
    public enum Control: UInt8, Sendable { case sendMTU = 0, readyToDownload = 1 }
    public enum Update: UInt8, Sendable { case percent = 0, stateChange = 1 }
    public static let maximumMTU = 650

    /// Opens a session: image CRC, segment count, then id, size, and CRC per segment.
    public static func open(_ image: FirmwareImage) -> SPPMessage {
        var payload: [UInt8] = le32(image.trailingCRC) + [UInt8(image.segments.count)]
        for s in image.segments {
            payload += [s.id] + le32(UInt32(s.data.count)) + le32(s.crc32)
        }
        return SPPMessage(id: .fotaOpen, payload: payload)
    }

    /// Echo of a control request. The earbuds send one. We answer with the same id and value.
    public static func controlResponse(_ control: Control, value: Int) -> SPPMessage {
        let v = control == .sendMTU ? min(value, maximumMTU) : value
        return SPPMessage(
            id: .fotaControl, payload: [control.rawValue, UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)], isResponse: true)
    }

    /// One chunk of segment data. The 4-byte header carries the offset. The top bit is set on
    /// every fragment except the last one of the segment.
    public static func downloadChunk(segment: FirmwareImage.Segment, offset: Int, mtu: Int) -> SPPMessage {
        let remaining = segment.data.count - offset
        let last = remaining <= mtu
        let length = max(0, last ? remaining : mtu)
        var header = UInt32(offset & 0x7FFF_FFFF)
        if !last { header |= 0x8000_0000 }
        let chunk = length > 0 ? Array(segment.data[offset..<offset + length]) : []
        return SPPMessage(id: .fotaDownloadData, payload: le32(header) + chunk, isResponse: true, isFragment: true)
    }

    public static let updateAck = SPPMessage(id: .fotaUpdate, payload: [1], isResponse: true)
    public static let resultAck = SPPMessage(id: .fotaResult, payload: [1], isResponse: true)

    public struct ControlRequest: Sendable {
        public let control: Control
        public let value: Int
        public init?(_ payload: [UInt8]) {
            guard payload.count >= 3, let control = Control(rawValue: payload[0]) else { return nil }
            self.control = control
            value = Int(payload[1]) | Int(payload[2]) << 8
        }
    }

    public struct DownloadRequest: Sendable {
        public let offset: Int
        public let packets: Int
        public let nak: Bool
        public init?(_ payload: [UInt8]) {
            guard payload.count >= 5 else { return nil }
            nak = payload[3] & 0x80 != 0
            offset = Int(payload[0]) | Int(payload[1]) << 8 | Int(payload[2]) << 16 | Int(payload[3] & 0x7F) << 24
            packets = Int(payload[4])
        }
    }

    public struct UpdateNotice: Sendable {
        public let kind: Update
        public let value: Int
        public let resultCode: Int
        public init?(_ payload: [UInt8]) {
            guard payload.count >= 3, let kind = Update(rawValue: payload[0]) else { return nil }
            self.kind = kind
            value = Int(payload[1])
            resultCode = Int(payload[2])
        }
    }

    public struct Result: Sendable {
        public let succeeded: Bool
        public let errorCode: Int
        public init?(_ payload: [UInt8]) {
            guard payload.count >= 2 else { return nil }
            succeeded = payload[0] == 0
            errorCode = Int(payload[1])
        }
    }

    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
}

public extension MessageID {
    static let fotaDeviceInfoSoftwareVersion = MessageID(180)
    static let fotaResult = MessageID(185)
    static let fotaOpen = MessageID(187)
    static let fotaControl = MessageID(188)
    static let fotaDownloadData = MessageID(189)
    static let fotaUpdate = MessageID(190)
}
