// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import BudsProtocol

@Suite struct DecoderTests {
    /// Real EXTENDED_STATUS_UPDATED payload from a pair of Galaxy Buds2 on firmware R177XXU0AYF1.
    let buds2Status: [UInt8] = [
        0x0b, 0x03, 0x61, 0x61, 0x01, 0x00, 0x11, 0x00, 0x00, 0x03, 0xbf, 0x22, 0x00, 0x00, 0x39, 0x01, 0x39, 0x01,
        0x00, 0x00, 0x03, 0x66, 0x00, 0x01, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x11, 0x02, 0x00, 0x01, 0x00, 0x00,
        0x40, 0x00, 0x00,
    ]

    @Test func testBuds2ExtendedStatus() throws {
        let s = try #require(ExtendedStatus.decode(buds2Status, model: .buds2))
        #expect(s.revision == 11)
        #expect(s.basic.batteryLeft == 97)
        #expect(s.basic.batteryRight == 97)
        #expect(s.basic.isCoupled)
        #expect(!s.basic.mainIsLeft)
        #expect(s.basic.placementLeft == .wearing)
        #expect(s.basic.placementRight == .wearing)
        #expect(s.equalizerPreset == .dynamic)
        #expect(!s.touchpadLocked)
        #expect(s.singleTapEnabled == true)
        #expect(s.doubleTapEnabled == true)
        #expect(s.tripleTapEnabled == true)
        #expect(s.touchHoldEnabled == true)
        #expect(s.doubleTapForCallEnabled == true)
        #expect(s.touchHoldForCallEnabled == true)
        #expect(s.touchActionLeft == .noiseControls)
        #expect(s.touchActionRight == .noiseControls)
        #expect(s.noiseControlMode == .off)
        #expect(s.colorLeft?.model == .buds2)
        #expect(s.colorLeft?.name == "White")
        #expect(s.seamlessConnection == true)
        #expect(s.noiseControlCycleLeft == .ancAndAmbient)
        #expect(s.noiseControlCycleRight == .ancAndAmbient)
        #expect(s.ambientSoundVolume == 1)
        #expect(s.stereoBalance == 16)
        #expect(s.ambientCustomEnabled == false)
        #expect(s.ambientCustomVolumeLeft == 1)
        #expect(s.ambientCustomVolumeRight == 1)
        #expect(s.ambientCustomTone == 2)
        #expect(s.sidetone == true)
        #expect(s.callPathControl == true)
        #expect(s.spatialAudio == false)
        #expect(!s.basic.isLeftCharging)
        #expect(s.unparsedTail == [0x00, 0x00])
    }

    @Test func testSkuIdentifiesModel() throws {
        let sku = try #require(SkuInfo(Array("SM-R177NZWAINSSM-R177NZWAINS".utf8)))
        #expect(sku.model == .buds2)
        #expect(sku.left == "SM-R177NZWAINS")
        #expect(sku.regionCode == "INS")
        #expect(BudsModel.from(sku: "SM-R400NZAAEUA") == .budsFE)
        #expect(BudsModel.from(sku: "SM-R510NZAAXAR") == .buds2Pro)
    }

    @Test func testDebugAllDataFirmwareString() throws {
        // Captured reply, addresses zeroed.
        var payload: [UInt8] = [0x00, 0x04, 0x01, 0xa5, 0x01, 0xc4]
        payload += [UInt8](repeating: 0, count: 12)  // two addresses
        payload += [UInt8](repeating: 0, count: 108 - payload.count)
        let data = try #require(DebugAllData(payload, model: .buds2))
        #expect(data.softwareVersion == "R177XXU0AYF1")
        #expect(data.hardwareVersion == "rev0.4")
        #expect(data.touchSoftwareVersion == "0xC4")
    }

    @Test func testUsageReport() throws {
        let payload: [UInt8] = [
            0x02, 0x46, 0x42, 0x44, 0x41, 0x00, 0x03, 0x00, 0x00, 0x00,
            0x42, 0x53, 0x43, 0x4c, 0x00, 0x05, 0x16, 0x00, 0x00,
        ]
        let report = try #require(UsageReport(payload))
        #expect(report.entries.count == 2)
        #expect(report.entries[0].key == "FBDA")
        #expect(report.entries[0].value == 3)
        #expect(report.entries[1].key == "BSCL")
        #expect(report.entries[1].value == 0x1605)
    }

    @Test func testInvertedFlags() {
        #expect(Commands.seamlessConnection(true).payload == [0])
        #expect(Commands.callPathControl(false).payload == [1])
        #expect(
            Commands.touchLock(
                lockAll: true, singleTap: false, doubleTap: false, tripleTap: false,
                touchHold: false, doubleTapForCalls: nil, touchHoldForCalls: nil
            ).payload == [0, 0, 0, 0, 0])
    }

    @Test func testTouchAndHoldCyclePayload() {
        let m = Commands.touchAndHoldNoiseControls(left: .ancAndOff, right: .ambientAndOff, model: .buds2)
        #expect(m.payload == [1, 0, 1, 0, 1, 1])
    }

    @Test func testSelfTestMask() throws {
        let ok = try #require(SelfTestResult([0, 0, 0, 0]))
        #expect(ok.allPassed)
        let bad = try #require(SelfTestResult([0x08, 0, 0, 0]))
        #expect(!bad.passed(3))
        #expect(bad.passed(2))
    }

    @Test func testSpatialOrientation() throws {
        let event = try #require(SpatialAudioEvent([32, 0x10, 0x27, 0, 0, 0, 0, 0, 0, 0]))
        guard case let .orientation(w, x, _, _) = event else { Issue.record("wrong event"); return }
        #expect(abs(w - 1.0) <= 0.0001)
        #expect(x == 0)
    }
}
