// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import BudsProtocol

@Suite struct FrameTests {
    @Test func testChecksumMatchesKnownVector() {
        // Captured from a Buds+ extended status. The device appended 0F F3 (little-endian 0xF30F).
        let data: [UInt8] = [0x61, 0x02, 0x00, 0x4B, 0x5F, 0x01, 0x00, 0x00, 0x00, 0x01, 0x05, 0x00, 0x02, 0x00, 0x13]
        #expect(CRC16.xmodem(data) == 0xF30F)
    }

    @Test func testEncodeMatchesDeviceAcceptedFrame() {
        // The buds answered this exact DEBUG_SKU frame during development.
        #expect(Commands.debugSku.encoded() == [0xFD, 0x03, 0x00, 0x22, 0x20, 0x04, 0xDD])
    }

    @Test func testRoundTrip() {
        let message = SPPMessage(id: .lockTouchpad, payload: [1, 1, 0, 1, 1, 1, 0], isResponse: true)
        let parser = FrameParser()
        let decoded = parser.feed(message.encoded())
        #expect(decoded == [message])
    }

    @Test func testParserHandlesSplitAndConcatenatedFrames() {
        let a = Commands.noiseControls(.ambientSound).encoded()
        let b = Commands.ambientVolume(2).encoded()
        let stream = a + b + a
        let parser = FrameParser()
        var out: [SPPMessage] = []
        // Deliver one byte at a time.
        for byte in stream { out += parser.feed([byte]) }
        #expect(out.count == 3)
        #expect(out[1].id == .ambientVolume)
        #expect(parser.droppedBytes == 0)
    }

    @Test func testParserResynchronisesAfterGarbage() {
        let good = Commands.debugSku.encoded()
        let parser = FrameParser()
        let out = parser.feed([0x00, 0xFD, 0x01, 0x00] + good)
        #expect(out == [Commands.debugSku])
        #expect(parser.droppedBytes > 0)
    }

    @Test func testLegacyFraming() {
        let message = SPPMessage(id: .statusUpdated, payload: [1, 2, 3])
        let bytes = message.encoded(framing: .legacy)
        #expect(bytes.first == 0xFE)
        #expect(bytes.last == 0xEE)
        #expect(bytes[1] == 0)  // request
        #expect(bytes[2] == 6)  // id + 3 payload + crc
        #expect(FrameParser(framing: .legacy).feed(bytes) == [message])
    }
}
