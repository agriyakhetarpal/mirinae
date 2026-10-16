// SPDX-License-Identifier: Apache-2.0
import Foundation

public enum Feature: String, CaseIterable, Sendable {
    case seamlessConnection, ambientExtraLoud, ambientVoiceFocus, ambientSidetone, ambientPassthrough
    case ambientSound, anc, noiseControl, noiseControlModeDualSide, noiseControlAdaptive
    case extraClearCallSound, bixbyWakeup, detectConversations, gamingMode, doubleTapVolume
    case caseBattery, batteryType, voltage, current, fragmentedMessages, stereoPan, firmwareUpdates
    case spatialSensor, ambientCustomize, ambientCustomizeLegacy, noiseControlsWithOneEarbud
    case ancNoiseReductionLevels, advancedTouchLock, advancedTouchLockForCalls, advancedTouchLockSwipe
    case callPathControl, chargingState, fmgRingWhileWearing, legacyAmbientSoundVolumeLevels, buildInfo
    case gearFitTest, debugSku, pairingMode, ambientSoundVolume, autoAdjustSound, headTracking
    case cradleSerialNumber, sppLegacyMessageHeader, deviceColor, rename, smartThingsFind, usageReport
    case hotCommandLanguageUpdate, hiddenAtMode, customEqualizer
}

public enum ServiceUUID {
    public static let sppLegacy = UUID(uuidString: "00001102-0000-1000-8000-00805F9B34FD")!
    public static let sppStandard = UUID(uuidString: "00001101-0000-1000-8000-00805F9B34FB")!
    /// Buds2 and newer ("GEARMANAGER" in the SDP record).
    public static let sppNew = UUID(uuidString: "2E73A4AD-332D-41FC-90E2-16BEF06523F2")!
    public static let smep = UUID(uuidString: "F8620674-A1ED-41AB-A8B9-DE9AD655729D")!
    public static let handsfree = UUID(uuidString: "0000111E-0000-1000-8000-00805F9B34FB")!
    public static let leAudio = UUID(uuidString: "0000184E-0000-1000-8000-00805F9B34FB")!
}

public enum TouchAction: String, CaseIterable, Sendable, Identifiable {
    case voiceAssistant, quickAmbientSound, volume, ambientSound, anc, noiseControls, spotify, otherLeft, otherRight

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .voiceAssistant: return "Voice assistant"
        case .quickAmbientSound: return "Quick ambient sound"
        case .volume: return "Volume"
        case .ambientSound: return "Ambient sound"
        case .anc: return "Active noise cancelling"
        case .noiseControls: return "Noise controls"
        case .spotify: return "Spotify Tap"
        case .otherLeft, .otherRight: return "Custom (handled by the host)"
        }
    }
}

public enum TouchMap: Sendable {
    case standard, buds, budsPlus, budsLive

    public var table: [TouchAction: UInt8] {
        switch self {
        case .standard:
            return [.voiceAssistant: 1, .noiseControls: 2, .volume: 3, .spotify: 4, .otherLeft: 5, .otherRight: 6]
        case .buds:
            return [
                .voiceAssistant: 0, .quickAmbientSound: 1, .volume: 2, .ambientSound: 3, .spotify: 4, .otherLeft: 5,
                .otherRight: 6,
            ]
        case .budsPlus:
            return [.voiceAssistant: 1, .ambientSound: 2, .volume: 3, .spotify: 4, .otherLeft: 5, .otherRight: 6]
        case .budsLive:
            return [.voiceAssistant: 1, .anc: 2, .volume: 3, .spotify: 4, .otherLeft: 5, .otherRight: 6]
        }
    }

    public func action(for byte: UInt8) -> TouchAction? {
        table.first { $0.value == byte }?.key
    }

    public func byte(for action: TouchAction) -> UInt8? {
        table[action]
    }

    public func choices(forLeft: Bool) -> [TouchAction] {
        TouchAction.allCases.filter { action in
            guard table[action] != nil else { return false }
            if action == .otherLeft { return forLeft }
            if action == .otherRight { return !forLeft }
            return true
        }
    }
}

/// Ordered by generation. Decoders compare with `<` and `>=`.
public enum BudsModel: Int, CaseIterable, Sendable, Identifiable, Comparable, Codable {
    case buds = 1, budsPlus, budsLive, budsPro, buds2, buds2Pro, budsFE, budsCore, buds3, buds3Pro, buds3FE, buds4,
        buds4Pro

    public var id: Int { rawValue }

    public static func < (lhs: BudsModel, rhs: BudsModel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .buds: return "Galaxy Buds"
        case .budsPlus: return "Galaxy Buds+"
        case .budsLive: return "Galaxy Buds Live"
        case .budsPro: return "Galaxy Buds Pro"
        case .buds2: return "Galaxy Buds2"
        case .buds2Pro: return "Galaxy Buds2 Pro"
        case .budsFE: return "Galaxy Buds FE"
        case .budsCore: return "Galaxy Buds Core"
        case .buds3: return "Galaxy Buds3"
        case .buds3Pro: return "Galaxy Buds3 Pro"
        case .buds3FE: return "Galaxy Buds3 FE"
        case .buds4: return "Galaxy Buds4"
        case .buds4Pro: return "Galaxy Buds4 Pro"
        }
    }

    public var skuPattern: String {
        switch self {
        case .buds: return "R170"
        case .budsPlus: return "SM-R175"
        case .budsLive: return "SM-R180"
        case .budsPro: return "SM-R190"
        case .buds2: return "SM-R177"
        case .buds2Pro: return "SM-R510"
        case .budsFE: return "SM-R400N"
        case .budsCore: return "SM-R410"
        case .buds3: return "SM-R530"
        case .buds3Pro: return "SM-R630"
        case .buds3FE: return "SM-R420"
        case .buds4: return "SM-R540"
        case .buds4Pro: return "SM-R640"
        }
    }

    public var buildPrefix: String {
        skuPattern.replacingOccurrences(of: "SM-", with: "")
    }

    public var defaultNameFragment: String {
        switch self {
        case .buds: return "Galaxy Buds ("
        case .budsPlus: return "Galaxy Buds+ ("
        case .budsLive: return "Buds Live"
        case .budsPro: return "Buds Pro"
        case .buds2: return "Buds2"
        case .buds2Pro: return "Buds2 Pro"
        case .budsFE: return "Buds FE"
        case .budsCore: return "Buds Core"
        case .buds3: return "Buds3"
        case .buds3Pro: return "Buds3 Pro"
        case .buds3FE: return "Buds3 FE"
        case .buds4: return "Buds4"
        case .buds4Pro: return "Buds4 Pro"
        }
    }

    public var framing: Framing { self == .buds ? .legacy : .standard }

    public var serviceUUID: UUID {
        switch self {
        case .buds: return ServiceUUID.sppLegacy
        case .budsPlus, .budsLive, .budsPro: return ServiceUUID.sppStandard
        default: return ServiceUUID.sppNew
        }
    }

    public var touchMap: TouchMap {
        switch self {
        case .buds: return .buds
        case .budsPlus: return .budsPlus
        case .budsLive: return .budsLive
        default: return .standard
        }
    }

    public var maximumAmbientVolume: Int {
        switch self {
        case .buds, .buds4Pro: return 4
        case .budsLive: return 0
        case .budsPro: return 3
        default: return 2
        }
    }

    /// nil = always, number = minimum extended status revision.
    public var featureRules: [Feature: Int?] {
        switch self {
        case .buds:
            return [
                .seamlessConnection: 3, .ambientVoiceFocus: nil, .ambientSound: nil,
                .legacyAmbientSoundVolumeLevels: nil,
                .buildInfo: nil, .batteryType: nil, .voltage: nil, .current: nil, .pairingMode: nil,
                .ambientSoundVolume: nil,
                .sppLegacyMessageHeader: nil, .usageReport: nil,
            ]
        case .budsPlus:
            return [
                .ambientSound: nil, .ambientSidetone: 8, .ambientExtraLoud: 9, .seamlessConnection: 11,
                .firmwareUpdates: 8,
                .gamingMode: nil, .doubleTapVolume: nil, .caseBattery: nil, .fragmentedMessages: nil, .buildInfo: nil,
                .voltage: nil, .callPathControl: 13, .pairingMode: nil, .ambientSoundVolume: nil, .deviceColor: nil,
                .smartThingsFind: 12, .usageReport: nil, .hiddenAtMode: nil,
            ]
        case .budsLive:
            return [
                .seamlessConnection: 3, .ambientPassthrough: 5, .anc: nil, .gamingMode: nil, .caseBattery: nil,
                .fragmentedMessages: nil, .stereoPan: 7, .spatialSensor: 9, .bixbyWakeup: 1, .firmwareUpdates: nil,
                .buildInfo: nil, .voltage: nil, .debugSku: nil, .callPathControl: 8, .pairingMode: nil,
                .ambientSoundVolume: nil, .deviceColor: nil, .smartThingsFind: 4, .usageReport: nil, .hiddenAtMode: nil,
            ]
        case .budsPro:
            return [
                .seamlessConnection: nil, .stereoPan: 5, .doubleTapVolume: 7, .firmwareUpdates: nil,
                .detectConversations: nil,
                .noiseControl: nil, .gamingMode: nil, .caseBattery: nil, .fragmentedMessages: nil, .spatialSensor: nil,
                .voltage: nil, .bixbyWakeup: nil, .ambientSound: nil, .anc: nil, .ancNoiseReductionLevels: nil,
                .buildInfo: nil,
                .ambientSidetone: 8, .ambientCustomize: 8, .ambientCustomizeLegacy: 8, .debugSku: nil,
                .callPathControl: 10,
                .noiseControlModeDualSide: 8, .pairingMode: nil, .ambientSoundVolume: nil,
                .noiseControlsWithOneEarbud: 8,
                .deviceColor: nil, .smartThingsFind: nil, .usageReport: nil, .hiddenAtMode: nil,
            ]
        case .buds2:
            return [
                .seamlessConnection: nil, .stereoPan: nil, .firmwareUpdates: nil, .noiseControl: nil,
                .ambientSound: nil,
                .anc: nil, .gamingMode: nil, .caseBattery: nil, .fragmentedMessages: nil, .bixbyWakeup: nil,
                .gearFitTest: nil,
                .doubleTapVolume: 5, .advancedTouchLock: 4, .advancedTouchLockForCalls: 7,
                .noiseControlsWithOneEarbud: 3,
                .ambientCustomize: 5, .ambientSidetone: 6, .fmgRingWhileWearing: 9, .debugSku: nil, .callPathControl: 7,
                .chargingState: 10, .noiseControlModeDualSide: 5, .pairingMode: nil, .ambientSoundVolume: nil,
                .deviceColor: nil, .rename: nil, .spatialSensor: 10, .smartThingsFind: nil, .usageReport: nil,
            ]
        case .buds2Pro:
            return [
                .seamlessConnection: nil, .stereoPan: nil, .doubleTapVolume: nil, .firmwareUpdates: nil,
                .detectConversations: nil,
                .noiseControl: nil, .noiseControlModeDualSide: nil, .gamingMode: nil, .caseBattery: nil,
                .fragmentedMessages: nil,
                .spatialSensor: nil, .bixbyWakeup: nil, .gearFitTest: nil, .extraClearCallSound: 13,
                .ambientExtraLoud: 13,
                .ambientSound: nil, .anc: nil, .ambientSidetone: 1, .ambientCustomize: nil,
                .noiseControlsWithOneEarbud: nil,
                .debugSku: nil, .advancedTouchLock: nil, .advancedTouchLockForCalls: 1, .fmgRingWhileWearing: 4,
                .callPathControl: 1, .chargingState: 11, .autoAdjustSound: 3, .headTracking: 8,
                .cradleSerialNumber: nil,
                .deviceColor: nil, .rename: nil, .smartThingsFind: nil, .usageReport: nil,
            ]
        case .budsFE, .budsCore:
            return [
                .seamlessConnection: nil, .stereoPan: nil, .doubleTapVolume: nil, .firmwareUpdates: nil,
                .noiseControl: nil,
                .gamingMode: nil, .caseBattery: nil, .gearFitTest: nil, .fragmentedMessages: nil, .bixbyWakeup: nil,
                .ambientSound: nil, .anc: nil, .ancNoiseReductionLevels: nil, .ambientSidetone: nil,
                .ambientCustomize: nil,
                .noiseControlsWithOneEarbud: nil, .debugSku: nil, .advancedTouchLock: nil,
                .advancedTouchLockForCalls: nil,
                .callPathControl: nil, .fmgRingWhileWearing: nil, .chargingState: nil, .noiseControlModeDualSide: nil,
                .deviceColor: nil, .rename: nil, .smartThingsFind: nil, .usageReport: nil,
            ]
        case .buds3FE:
            return [
                .seamlessConnection: nil, .stereoPan: nil, .customEqualizer: nil, .doubleTapVolume: nil,
                .firmwareUpdates: nil,
                .noiseControl: nil, .gamingMode: nil, .caseBattery: nil, .gearFitTest: nil, .fragmentedMessages: nil,
                .bixbyWakeup: nil, .ambientSound: nil, .anc: nil, .ancNoiseReductionLevels: nil, .ambientSidetone: nil,
                .ambientCustomize: nil, .noiseControlsWithOneEarbud: nil, .debugSku: nil, .advancedTouchLock: nil,
                .advancedTouchLockForCalls: nil, .callPathControl: nil, .fmgRingWhileWearing: nil, .chargingState: nil,
                .noiseControlModeDualSide: nil, .deviceColor: nil, .rename: nil, .smartThingsFind: nil,
                .usageReport: nil,
            ]
        case .buds3, .buds4:
            return [
                .seamlessConnection: nil, .stereoPan: nil, .customEqualizer: nil, .firmwareUpdates: nil,
                .noiseControl: nil,
                .ambientSound: nil, .anc: nil, .gamingMode: nil, .caseBattery: nil, .fragmentedMessages: nil,
                .bixbyWakeup: nil,
                .gearFitTest: nil, .doubleTapVolume: nil, .advancedTouchLock: nil, .advancedTouchLockForCalls: nil,
                .noiseControlsWithOneEarbud: nil, .ambientCustomize: nil, .ambientSidetone: nil,
                .fmgRingWhileWearing: nil,
                .debugSku: nil, .callPathControl: nil, .chargingState: nil, .noiseControlModeDualSide: nil,
                .pairingMode: nil,
                .ambientSoundVolume: nil, .deviceColor: nil, .rename: nil, .spatialSensor: nil, .smartThingsFind: nil,
                .usageReport: nil, .hotCommandLanguageUpdate: 2, .noiseControlAdaptive: nil,
            ]
        case .buds3Pro, .buds4Pro:
            return [
                .seamlessConnection: nil, .stereoPan: nil, .customEqualizer: nil, .doubleTapVolume: nil,
                .firmwareUpdates: nil,
                .detectConversations: nil, .noiseControl: nil, .noiseControlModeDualSide: nil, .gamingMode: nil,
                .caseBattery: nil,
                .fragmentedMessages: nil, .spatialSensor: nil, .bixbyWakeup: nil, .gearFitTest: nil,
                .extraClearCallSound: nil,
                .ambientExtraLoud: nil, .ambientSound: nil, .ambientSoundVolume: nil, .anc: nil, .ambientSidetone: nil,
                .ambientCustomize: nil, .noiseControlsWithOneEarbud: nil, .debugSku: nil, .advancedTouchLock: nil,
                .advancedTouchLockForCalls: nil, .fmgRingWhileWearing: nil, .callPathControl: nil, .chargingState: nil,
                .autoAdjustSound: nil, .headTracking: nil, .cradleSerialNumber: nil, .deviceColor: nil, .rename: nil,
                .smartThingsFind: nil, .usageReport: nil, .hotCommandLanguageUpdate: 2, .noiseControlAdaptive: nil,
            ]
        }
    }

    public func supports(_ feature: Feature, revision: Int? = nil) -> Bool {
        guard let rule = featureRules[feature] else { return false }
        guard let minimum = rule else { return true }
        guard let revision else { return true }
        return revision >= minimum
    }

    public static func from(sku: String) -> BudsModel? {
        allCases.sorted { $0.skuPattern.count > $1.skuPattern.count }.first { sku.contains($0.skuPattern) }
    }

    public static func from(buildString: String) -> BudsModel? {
        allCases.sorted { $0.buildPrefix.count > $1.buildPrefix.count }.first { buildString.hasPrefix($0.buildPrefix) }
    }

    public static func from(deviceName: String) -> BudsModel? {
        allCases.sorted { $0.defaultNameFragment.count > $1.defaultNameFragment.count }.first {
            deviceName.contains($0.defaultNameFragment)
        }
    }
}

public struct DeviceColor: Hashable, Sendable {
    public let id: UInt16

    public init(id: UInt16) { self.id = id }

    public var name: String? { DeviceColor.names[id]?.1 }
    public var model: BudsModel? { DeviceColor.names[id]?.0 }

    public static let names: [UInt16: (BudsModel, String)] = [
        257: (.buds, "Default"), 14336: (.buds, "Unknown"),
        258: (.budsPlus, "Blue"), 259: (.budsPlus, "Pink"), 260: (.budsPlus, "Black"), 261: (.budsPlus, "White"),
        262: (.budsPlus, "Thom Browne"), 263: (.budsPlus, "Red"), 264: (.budsPlus, "Deep Blue"),
        265: (.budsPlus, "Olympic"),
        266: (.budsPlus, "Purple"),
        278: (.budsLive, "Black"), 279: (.budsLive, "White"), 280: (.budsLive, "Bronze"), 281: (.budsLive, "Red"),
        282: (.budsLive, "Blue"), 283: (.budsLive, "Thom Browne"), 284: (.budsLive, "Grey"),
        298: (.budsPro, "Black"), 299: (.budsPro, "Silver"), 300: (.budsPro, "Violet"), 301: (.budsPro, "White"),
        313: (.buds2, "White"), 314: (.buds2, "Black"), 315: (.buds2, "Yellow"), 316: (.buds2, "Green"),
        317: (.buds2, "Violet"),
        318: (.buds2, "Thom Browne"), 319: (.buds2, "Maison Kitsuné"), 320: (.buds2, "Absolute Black"),
        321: (.buds2, "Grey"),
        14337: (.buds2, "Unknown"),
        322: (.budsCore, "Onyx"), 323: (.budsCore, "White"),
        325: (.buds2Pro, "Unknown"), 326: (.buds2Pro, "Grey"), 327: (.buds2Pro, "White"), 328: (.buds2Pro, "Violet"),
        330: (.budsFE, "Graphite"), 331: (.budsFE, "White"),
        333: (.buds3, "Silver"), 334: (.buds3, "White"),
        340: (.buds3Pro, "Silver"), 341: (.buds3Pro, "White"),
        347: (.buds3FE, "Silver"), 348: (.buds3FE, "White"),
        355: (.buds4, "Black"), 356: (.buds4, "White"),
        359: (.buds4Pro, "Black"), 360: (.buds4Pro, "White"), 361: (.buds4Pro, "Apricot"),
    ]
}
