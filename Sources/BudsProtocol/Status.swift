// SPDX-License-Identifier: Apache-2.0
import Foundation

public enum Placement: UInt8, Sendable, CustomStringConvertible {
    case disconnected = 0, wearing = 1, idle = 2, inCase = 3, closedCase = 4
    case unknown = 0xFF

    public init(nibble: UInt8) {
        self = Placement(rawValue: nibble) ?? .unknown
    }

    public var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .wearing: return "In ear"
        case .idle: return "Out of ear"
        case .inCase: return "In case"
        case .closedCase: return "In closed case"
        case .unknown: return "Unknown"
        }
    }
}

public enum NoiseControlMode: UInt8, CaseIterable, Sendable, Identifiable {
    case off = 0, noiseCancelling = 1, ambientSound = 2, adaptive = 3

    public var id: UInt8 { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .noiseCancelling: return "Noise cancelling"
        case .ambientSound: return "Ambient sound"
        case .adaptive: return "Adaptive"
        }
    }
}

/// Which modes a tap-and-hold on a bud cycles through when it is assigned to "Noise controls".
public struct NoiseControlCycle: Hashable, Sendable {
    public var noiseCancelling: Bool
    public var ambientSound: Bool
    public var off: Bool

    public init(noiseCancelling: Bool, ambientSound: Bool, off: Bool) {
        self.noiseCancelling = noiseCancelling
        self.ambientSound = ambientSound
        self.off = off
    }

    public static let ancAndAmbient = NoiseControlCycle(noiseCancelling: true, ambientSound: true, off: false)
    public static let ancAndOff = NoiseControlCycle(noiseCancelling: true, ambientSound: false, off: true)
    public static let ambientAndOff = NoiseControlCycle(noiseCancelling: false, ambientSound: true, off: true)
    public static let all = NoiseControlCycle(noiseCancelling: true, ambientSound: true, off: true)

    public init(nibble: UInt8) {
        off = nibble & 1 != 0
        ambientSound = nibble & 2 != 0
        noiseCancelling = nibble & 4 != 0
    }

    public var displayName: String {
        var parts: [String] = []
        if noiseCancelling { parts.append("ANC") }
        if ambientSound { parts.append("Ambient") }
        if off { parts.append("Off") }
        return parts.isEmpty ? "Nothing" : parts.joined(separator: " / ")
    }
}

public enum EqualizerPreset: Int, CaseIterable, Sendable, Identifiable {
    case normal = 0, bassBoost, soft, dynamic, clear, trebleBoost

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .bassBoost: return "Bass boost"
        case .soft: return "Soft"
        case .dynamic: return "Dynamic"
        case .clear: return "Clear"
        case .trebleBoost: return "Treble boost"
        }
    }
}

public struct BasicStatus: Hashable, Sendable {
    public var revision: Int
    public var batteryLeft: Int
    public var batteryRight: Int
    public var batteryCase: Int?
    public var isCoupled: Bool
    public var mainIsLeft: Bool
    public var placementLeft: Placement
    public var placementRight: Placement
    public var isLeftCharging: Bool
    public var isRightCharging: Bool
    public var isCaseCharging: Bool

    public static func decode(_ payload: [UInt8], model: BudsModel) -> BasicStatus? {
        var r = ByteReader(payload)
        if model == .buds {
            guard payload.count >= 6 else { return nil }
            _ = r.byte()  // ear type
            let l = Int(r.byte() ?? 0), rt = Int(r.byte() ?? 0)
            let coupled = r.bool() ?? false
            let main = (r.byte() ?? 0) == 1
            let wear = r.byte() ?? 0
            return BasicStatus(
                revision: 0, batteryLeft: l, batteryRight: rt, batteryCase: nil, isCoupled: coupled,
                mainIsLeft: main, placementLeft: wear & 0x10 != 0 ? .wearing : .idle,
                placementRight: wear & 0x01 != 0 ? .wearing : .idle,
                isLeftCharging: false, isRightCharging: false, isCaseCharging: false)
        }
        guard payload.count >= 7 else { return nil }
        let revision = Int(r.byte() ?? 0)
        let l = Int(r.byte() ?? 0), rt = Int(r.byte() ?? 0)
        let coupled = r.bool() ?? false
        let main = (r.byte() ?? 0) == 1
        let placement = r.byte() ?? 0
        let caseLevel = Int(r.byte() ?? 0)
        var status = BasicStatus(
            revision: revision, batteryLeft: l, batteryRight: rt, batteryCase: caseLevel, isCoupled: coupled,
            mainIsLeft: main, placementLeft: Placement(nibble: placement >> 4),
            placementRight: Placement(nibble: placement & 0x0F),
            isLeftCharging: false, isRightCharging: false, isCaseCharging: false)
        if model.supports(.chargingState, revision: nil), let charging = r.byte() {
            status.applyCharging(charging)
        }
        return status
    }

    mutating func applyCharging(_ byte: UInt8) {
        isLeftCharging = byte & 0x10 != 0
        isRightCharging = byte & 0x04 != 0
        isCaseCharging = byte & 0x01 != 0
    }
}

/// EXTENDED_STATUS_UPDATED. Fields a model does not carry stay nil.
public struct ExtendedStatus: Hashable, Sendable {
    public var basic: BasicStatus
    public var earType: Int

    public var equalizerPreset: EqualizerPreset?
    public var equalizerRaw: Int
    public var adjustSoundSync: Bool?

    public var touchpadLocked: Bool
    public var singleTapEnabled: Bool?
    public var doubleTapEnabled: Bool?
    public var tripleTapEnabled: Bool?
    public var touchHoldEnabled: Bool?
    public var doubleTapForCallEnabled: Bool?
    public var touchHoldForCallEnabled: Bool?
    public var swipeEnabled: Bool?
    public var touchActionLeft: TouchAction?
    public var touchActionRight: TouchAction?
    public var touchActionLeftRaw: UInt8
    public var touchActionRightRaw: UInt8
    public var touchType: Int?
    public var outsideDoubleTap: Bool?

    public var noiseControlMode: NoiseControlMode?
    public var noiseCancellingEnabled: Bool?  // Buds Live only
    public var ambientSoundEnabled: Bool?  // Buds and Buds+
    public var ambientSoundVolume: Int?
    public var extraHighAmbient: Bool?
    public var ambientCustomEnabled: Bool?
    public var ambientCustomVolumeLeft: Int?
    public var ambientCustomVolumeRight: Int?
    public var ambientCustomTone: Int?
    public var noiseReductionLevel: Int?
    public var noiseControlsWithOneEarbud: Bool?
    public var noiseControlCycleLeft: NoiseControlCycle?
    public var noiseControlCycleRight: NoiseControlCycle?
    public var speakSeamlessly: Bool?
    public var detectConversations: Bool?
    public var detectConversationsDuration: Int?

    public var voiceWakeUp: Bool?
    public var voiceWakeUpLanguage: Int?
    public var colorLeft: DeviceColor?
    public var colorRight: DeviceColor?
    public var seamlessConnection: Bool?
    public var fmmRevision: Int?
    public var sidetone: Bool?
    public var callPathControl: Bool?
    public var spatialAudio: Bool?
    public var stereoBalance: Int?  // 0...32, 16 is centred ("hearing enhancements")
    public var hearingEnhancementsRaw: Int?
    public var autoSwitchAudioOutput: Bool?

    // Buds2 Pro and newer
    public var conversationBoost: Bool?
    public var customNoiseReductionLevel: Int?
    public var neckStretchCalibration: Bool?
    public var bixbyKeyword: Int?
    public var hearingTestValue: Int?
    public var autoAdjustSound: Bool?
    public var headTracking: Bool?
    public var extraClearCallSound: Bool?
    public var autoPauseResume: Bool?
    public var hotCommandEnabled: Bool?
    public var hotCommandLanguage: Int?
    public var peqMode: Int?
    public var adaptiveVolume: Bool?
    public var adaptSound: Bool?
    public var lightingControl: Int?
    public var doublePinchAndHold: Int?
    public var sirenDetect: Bool?

    public var unparsedTail: [UInt8]
    public var payload: [UInt8]

    public var revision: Int { basic.revision }

    // MARK: Decoding

    public static func decode(_ payload: [UInt8], model: BudsModel) -> ExtendedStatus? {
        guard payload.count >= 8 else { return nil }
        let revision = Int(payload[0])
        var basic = BasicStatus(
            revision: revision, batteryLeft: Int(payload[2]), batteryRight: Int(payload[3]),
            batteryCase: nil, isCoupled: payload[4] != 0, mainIsLeft: payload[5] == 1,
            placementLeft: .unknown, placementRight: .unknown,
            isLeftCharging: false, isRightCharging: false, isCaseCharging: false)
        var s = ExtendedStatus(
            basic: basic, earType: Int(payload[1]), equalizerPreset: nil, equalizerRaw: 0,
            touchpadLocked: false, touchActionLeftRaw: 0, touchActionRightRaw: 0,
            unparsedTail: [], payload: payload)
        let r = ByteReader(payload)
        var consumed = 0

        func eq(_ raw: UInt8?) {
            guard let raw else { return }
            s.equalizerRaw = Int(raw)
            s.equalizerPreset = EqualizerPreset(rawValue: Int(raw))
        }
        func touchOptions(_ byte: UInt8?) {
            guard let byte else { return }
            s.touchActionLeftRaw = byte >> 4
            s.touchActionRightRaw = byte & 0x0F
            s.touchActionLeft = model.touchMap.action(for: byte >> 4)
            s.touchActionRight = model.touchMap.action(for: byte & 0x0F)
        }
        func color(_ index: Int) -> DeviceColor? {
            ByteReader.int16(payload, at: index).map { DeviceColor(id: UInt16(bitPattern: $0)) }
        }

        if model == .buds {
            let wear = r[6] ?? 0
            basic.placementLeft = wear & 0x10 != 0 ? .wearing : .idle
            basic.placementRight = wear & 0x01 != 0 ? .wearing : .idle
            s.ambientSoundEnabled = r[7].map { $0 != 0 }
            s.ambientSoundVolume = r[9].map(Int.init)
            s.equalizerRaw = Int(r[11] ?? 0)
            s.equalizerPreset = (r[10] ?? 0) != 0 ? EqualizerPreset(rawValue: (Int(r[11] ?? 0) % 5) + 1) : .normal
            if payload.count > 13 {
                s.touchpadLocked = (r[12] ?? 0) != 0
                touchOptions(r[13])
                if revision >= 3 { s.seamlessConnection = r[14].map { $0 == 0 } }
                consumed = 15
            } else {
                s.touchpadLocked = ((r[12] ?? 0) & 0xF0) != 0
                if revision >= 3 { s.seamlessConnection = r[13].map { $0 == 0 } }
                consumed = 14
            }
            s.basic = basic
            s.unparsedTail = consumed < payload.count ? Array(payload[consumed...]) : []
            return s
        }

        let placement = r[6] ?? 0
        basic.placementLeft = Placement(nibble: placement >> 4)
        basic.placementRight = Placement(nibble: placement & 0x0F)
        basic.batteryCase = r[7].map(Int.init)

        if model == .budsPlus {
            s.ambientSoundEnabled = r[8].map { $0 != 0 }
            s.ambientSoundVolume = r[9].map(Int.init)
            s.adjustSoundSync = r[10].map { $0 == 1 }
            eq(r[11])
            s.touchpadLocked = (r[12] ?? 0) != 0
            touchOptions(r[13])
            s.outsideDoubleTap = r[14].map { $0 == 1 }
            s.colorLeft = color(15)
            s.colorRight = color(17)
            consumed = 19
            if revision >= 8 { s.sidetone = r[19].map { $0 == 1 }; consumed = 20 }
            if revision >= 9 { s.extraHighAmbient = r[20].map { $0 == 1 }; consumed = 21 }
            if revision >= 11 { s.seamlessConnection = r[21].map { $0 == 0 }; consumed = 22 }
            if revision >= 12 { s.fmmRevision = r[22].map(Int.init); consumed = 23 }
            if revision >= 13 { s.callPathControl = r[23].map { $0 == 0 }; consumed = 24 }
            s.basic = basic
            s.unparsedTail = consumed < payload.count ? Array(payload[consumed...]) : []
            return s
        }

        s.adjustSoundSync = r[8].map { $0 == 1 }
        eq(r[9])
        let lock = r[10] ?? 0
        if model.supports(.advancedTouchLock, revision: revision) {
            s.touchHoldEnabled = lock & 0x01 != 0
            s.tripleTapEnabled = lock & 0x02 != 0
            s.doubleTapEnabled = lock & 0x04 != 0
            s.singleTapEnabled = lock & 0x08 != 0
            s.touchpadLocked = lock & 0x80 == 0
            if model.supports(.advancedTouchLockForCalls, revision: revision) {
                s.doubleTapForCallEnabled = lock & 0x10 != 0
                s.touchHoldForCallEnabled = lock & 0x20 != 0
            }
            if model.supports(.advancedTouchLockSwipe, revision: revision) {
                s.swipeEnabled = lock & 0x40 != 0
            }
        } else {
            s.touchpadLocked = lock == 1
        }
        touchOptions(r[11])
        if model == .budsLive {
            s.noiseCancellingEnabled = r[12].map { $0 == 1 }
        } else {
            s.noiseControlMode = r[12].flatMap(NoiseControlMode.init(rawValue:))
        }
        s.voiceWakeUp = r[13].map { $0 == 1 }
        s.colorLeft = color(14)
        s.colorRight = color(16)
        s.voiceWakeUpLanguage = r[18].map(Int.init)
        consumed = 19
        if model.supports(.seamlessConnection, revision: nil) {
            s.seamlessConnection = r[19].map { $0 == 0 }; consumed = 20
        }
        if model.supports(.smartThingsFind, revision: nil) { s.fmmRevision = r[20].map(Int.init); consumed = 21 }

        if model == .budsLive {
            if revision >= 5 { consumed = 22 }  // "relieve ambient"
            if revision >= 7 { s.hearingEnhancementsRaw = r[22].map(Int.init); consumed = 23 }
            if revision >= 8 { s.callPathControl = r[23].map { $0 == 0 }; consumed = 24 }
            if revision >= 9 { s.spatialAudio = r[24].map { $0 == 1 }; consumed = 25 }
            s.basic = basic
            s.unparsedTail = consumed < payload.count ? Array(payload[consumed...]) : []
            return s
        }

        if let cycle = r[21] {
            if model.supports(.noiseControlAdaptive, revision: nil) {
                func decodeNew(_ n: UInt8) -> NoiseControlCycle {
                    NoiseControlCycle(noiseCancelling: n & 8 != 0, ambientSound: n & 1 != 0, off: n & 4 != 0)
                }
                s.noiseControlCycleRight = decodeNew(cycle & 0x0F)
                s.noiseControlCycleLeft = decodeNew(cycle >> 4)
            } else {
                s.noiseControlCycleRight = NoiseControlCycle(nibble: cycle & 0x0F)
                if model.supports(.noiseControlModeDualSide, revision: revision) {
                    s.noiseControlCycleLeft = NoiseControlCycle(nibble: cycle >> 4)
                } else {
                    s.noiseControlCycleLeft = s.noiseControlCycleRight
                }
            }
        }
        if model == .budsPro && revision < 3 {
            s.extraHighAmbient = r[22].map { $0 == 1 }
        } else {
            s.speakSeamlessly = r[22].map { $0 == 1 }
        }
        s.ambientSoundVolume = r[23].map(Int.init)
        s.noiseReductionLevel = r[24].map(Int.init)
        consumed = 25

        switch model {
        case .budsPro:
            s.autoSwitchAudioOutput = r[25].map { $0 == 1 }
            s.detectConversations = r[26].map { $0 == 1 }
            s.detectConversationsDuration = r[27].map { Int($0) > 2 ? 1 : Int($0) }
            consumed = 28
            if revision > 1 { s.spatialAudio = r[28].map { $0 == 1 }; consumed = 29 }
            if revision >= 5 {
                s.hearingEnhancementsRaw = r[29].map(Int.init); s.stereoBalance = s.hearingEnhancementsRaw;
                consumed = 30
            }
            if revision >= 6 { s.extraHighAmbient = r[30].map { $0 == 1 }; consumed = 31 }
            if revision >= 7 { s.outsideDoubleTap = r[31].map { $0 == 1 }; consumed = 32 }
            if revision >= 8 {
                s.noiseControlsWithOneEarbud = r[32].map { $0 == 1 }
                s.ambientCustomEnabled = r[33].map { $0 == 1 }
                s.ambientCustomVolumeLeft = r[34].map { Int($0 >> 4) }
                s.ambientCustomVolumeRight = r[34].map { Int($0 & 0x0F) }
                s.ambientCustomTone = r[35].map(Int.init)
                consumed = 36
            }
            if revision >= 9 { s.sidetone = r[36].map { $0 == 1 }; consumed = 37 }
            if revision >= 10 { s.callPathControl = r[37].map { $0 == 0 }; consumed = 38 }

        case .buds2:
            s.hearingEnhancementsRaw = r[25].map(Int.init)
            s.stereoBalance = s.hearingEnhancementsRaw
            s.extraHighAmbient = r[26].map { $0 == 1 }
            consumed = 27
            if revision >= 2 { s.touchType = r[27].map(Int.init); consumed = 28 }
            if revision >= 3 { s.noiseControlsWithOneEarbud = r[28].map { $0 == 1 }; consumed = 29 }
            if revision >= 5 {
                s.ambientCustomEnabled = r[29].map { $0 == 1 }
                s.ambientCustomVolumeLeft = r[30].map { Int($0 >> 4) }
                s.ambientCustomVolumeRight = r[30].map { Int($0 & 0x0F) }
                s.ambientCustomTone = r[31].map(Int.init)
                s.outsideDoubleTap = r[32].map { $0 == 1 }
                consumed = 33
            }
            if revision >= 6 { s.sidetone = r[33].map { $0 == 1 }; consumed = 34 }
            if revision >= 7 { s.callPathControl = r[34].map { $0 == 0 }; consumed = 35 }
            if revision >= 8 { s.spatialAudio = r[35].map { $0 == 1 }; consumed = 36 }
            if revision >= 10, let charging = r[36] { basic.applyCharging(charging); consumed = 37 }

        default:
            s.hearingEnhancementsRaw = r[25].map(Int.init)
            s.stereoBalance = s.hearingEnhancementsRaw
            s.detectConversations = r[26].map { $0 == 1 }
            s.detectConversationsDuration = r[27].map { Int($0) > 2 ? 1 : Int($0) }
            s.noiseControlsWithOneEarbud = r[28].map { $0 == 1 }
            s.ambientCustomEnabled = r[29].map { $0 == 1 }
            s.ambientCustomVolumeLeft = r[30].map { Int($0 >> 4) }
            s.ambientCustomVolumeRight = r[30].map { Int($0 & 0x0F) }
            s.ambientCustomTone = r[31].map(Int.init)
            s.outsideDoubleTap = r[32].map { $0 == 1 }
            s.sidetone = r[33].map { $0 == 1 }
            var t = ByteReader(payload, offset: 34)

            if model == .buds2Pro {
                if revision >= 1 {
                    s.callPathControl = t.byte().map { $0 == 0 }
                    s.spatialAudio = t.bool()
                    s.conversationBoost = t.bool()
                    s.customNoiseReductionLevel = t.byte().map(Int.init)
                    s.neckStretchCalibration = t.bool()
                    s.bixbyKeyword = t.byte().map(Int.init)
                    s.hearingTestValue = t.byte().map(Int.init)
                }
                if revision >= 3 {
                    s.autoAdjustSound = t.bool()
                } else if let v = s.hearingTestValue {
                    s.autoAdjustSound = !(v == 0 || v == 1)
                }
                if revision >= 8 { s.headTracking = t.bool() }
                if revision >= 11, let charging = t.byte() { basic.applyCharging(charging) }
                if revision >= 13 {
                    s.extraClearCallSound = t.bool()
                    s.extraHighAmbient = t.bool()
                }
            } else {
                s.callPathControl = t.byte().map { $0 == 0 }
                s.spatialAudio = t.bool()
                s.conversationBoost = t.bool()
                s.customNoiseReductionLevel = t.byte().map(Int.init)
                s.neckStretchCalibration = t.bool()
                s.bixbyKeyword = t.byte().map(Int.init)
                s.hearingTestValue = t.byte().map(Int.init)
                if let v = s.hearingTestValue { s.autoAdjustSound = !(v == 0 || v == 1) }
                if model == .budsFE || model == .budsCore || model == .buds3FE {
                    t.skip(1)  // amplify ambient sound, unused
                    s.headTracking = t.bool()
                    if let charging = t.byte() { basic.applyCharging(charging) }
                } else {
                    s.headTracking = t.bool()
                    if let charging = t.byte() { basic.applyCharging(charging) }
                    s.extraClearCallSound = t.bool()
                    s.extraHighAmbient = t.bool()
                    s.autoPauseResume = t.bool()
                    s.hotCommandEnabled = t.bool()
                    s.hotCommandLanguage = t.byte().map(Int.init)
                    s.peqMode = t.byte().map(Int.init)
                    s.adaptiveVolume = t.bool()
                    if model == .buds3 || model == .buds4 {
                        s.adaptSound = t.bool()
                        if model.supports(.hotCommandLanguageUpdate, revision: revision) { t.skip(3) }
                    } else {
                        s.lightingControl = t.byte().map(Int.init)
                        s.doublePinchAndHold = t.byte().map(Int.init)
                        s.sirenDetect = t.bool()
                        s.adaptSound = t.bool()
                        if model.supports(.hotCommandLanguageUpdate, revision: revision) { t.skip(3) }
                    }
                }
            }
            consumed = t.offset
        }

        s.basic = basic
        s.unparsedTail = consumed < payload.count ? Array(payload[consumed...]) : []
        return s
    }
}
