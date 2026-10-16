// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import BudsProtocol

@Suite struct FirmwareTests {
    static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    static func image(segments: [(UInt8, [UInt8])]) -> [UInt8] {
        var table: [UInt8] = []
        var blobs: [UInt8] = []
        let headerSize = 12 + 16 * segments.count
        for (id, data) in segments {
            table +=
                le32(UInt32(id)) + le32(CRC32.checksum(data)) + le32(UInt32(headerSize + blobs.count))
                + le32(UInt32(data.count))
            blobs += data
        }
        var out =
            le32(FirmwareImage.magic) + le32(UInt32(headerSize + blobs.count + 4)) + le32(UInt32(segments.count))
            + table + blobs
        out += le32(CRC32.checksum(out))
        return out
    }

    @Test func crc32MatchesKnownVector() {
        #expect(CRC32.checksum(Array("123456789".utf8)) == 0xCBF43926)
    }

    @Test func parsesContainerAndVerifiesSegments() throws {
        let data = Array("R177XXU0AYF1 firmware body".utf8) + [UInt8](repeating: 0xAB, count: 1000)
        let image = try FirmwareImage(Self.image(segments: [(6, data)]))
        #expect(image.segments.count == 1)
        #expect(image.segments[0].id == 6)
        #expect(image.segments[0].data == data)
        #expect(image.model == .buds2)
    }

    @Test func rejectsCorruptSegment() {
        var bytes = Self.image(segments: [(6, [1, 2, 3, 4])])
        bytes[bytes.count - 6] ^= 0xFF
        #expect(throws: FirmwareImage.ParseError.self) { try FirmwareImage(bytes) }
    }

    @Test func openPayloadLayout() throws {
        let image = try FirmwareImage(Self.image(segments: [(6, [9, 9, 9])]))
        let open = Fota.open(image)
        #expect(open.id == .fotaOpen)
        #expect(open.payload.count == 4 + 1 + 9)
        #expect(open.payload[4] == 1)
        #expect(open.payload[5] == 6)
        #expect(Array(open.payload[6..<10]) == [3, 0, 0, 0])
    }

    @Test func chunkHeadersMarkTheLastFragment() throws {
        let image = try FirmwareImage(Self.image(segments: [(6, [UInt8](repeating: 7, count: 10))]))
        let seg = image.segments[0]
        let first = Fota.downloadChunk(segment: seg, offset: 0, mtu: 4)
        let last = Fota.downloadChunk(segment: seg, offset: 8, mtu: 4)
        #expect(first.isFragment && first.isResponse)
        #expect(first.payload[3] & 0x80 != 0)
        #expect(first.payload.count == 8)
        #expect(last.payload[3] & 0x80 == 0)
        #expect(last.payload.count == 6)
    }

    @Test func decodesRequestsFromTheEarbuds() {
        let control = Fota.ControlRequest([0, 0x8A, 0x02])
        #expect(control?.control == .sendMTU)
        #expect(control?.value == 650)
        let download = Fota.DownloadRequest([0x10, 0x00, 0x00, 0x80, 3])
        #expect(download?.offset == 16)
        #expect(download?.nak == true)
        #expect(download?.packets == 3)
        let update = Fota.UpdateNotice([0, 42, 0])
        #expect(update?.kind == .percent)
        #expect(update?.value == 42)
    }

    @Test func buildNamesCompare() {
        let current = FirmwareBuild(name: "R177XXU0AYF1")
        let older = FirmwareBuild(name: "R177XXU0AYA1")
        #expect(current?.year == 2025 && current?.month == 6 && current?.revision == 1)
        #expect(older! < current!)
        #expect(FirmwareBuild(name: "short") == nil)
    }
}

@Suite struct RealFirmwareTests {
    /// Set MIRINAE_FIRMWARE_FILE to a downloaded image to run this against the real thing.
    @Test func parsesRealImageWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["MIRINAE_FIRMWARE_FILE"],
            let data = FileManager.default.contents(atPath: path)
        else { return }
        let image = try FirmwareImage([UInt8](data))
        #expect(!image.segments.isEmpty)
        #expect(image.model != nil)
        let open = Fota.open(image)
        #expect(open.payload.count == 5 + 9 * image.segments.count)
    }
}
