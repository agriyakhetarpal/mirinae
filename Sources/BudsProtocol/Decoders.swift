// SPDX-License-Identifier: Apache-2.0
import Foundation

public struct SkuInfo: Hashable, Sendable {
    public var left: String?
    public var right: String?

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 14 else { return nil }
        left = ByteReader.ascii(Array(payload[0..<14]))
        right = payload.count >= 28 ? ByteReader.ascii(Array(payload[14..<28])) : nil
    }

    public var model: BudsModel? {
        (left ?? right).flatMap(BudsModel.from(sku:))
    }

    public var colorCode: String? { left.map { String($0.dropFirst(8).prefix(3)) } }
    public var regionCode: String? { left.map { String($0.suffix(3)) } }
}

public struct SerialNumbers: Hashable, Sendable {
    public var left: String
    public var right: String

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 22 else { return nil }
        left = ByteReader.ascii(Array(payload[0..<11]))
        right = ByteReader.ascii(Array(payload[11..<22]))
    }
}

public struct BatteryTypes: Hashable, Sendable {
    public var left: String
    public var right: String

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 4 else { return nil }
        left = ByteReader.ascii(Array(payload[0..<2]))
        right = ByteReader.ascii(Array(payload[2..<4]))
    }
}

public struct CradleInfo: Hashable, Sendable {
    public var softwareVersion: String
    public var serialNumber: String

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 20 else { return nil }
        softwareVersion = ByteReader.ascii(Array(payload[0..<9]))
        serialNumber = ByteReader.ascii(Array(payload[9..<20]))
    }
}

public struct BatteryCycles: Hashable, Sendable {
    public var left: Double
    public var right: Double

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 16 else { return nil }
        func be64(_ slice: ArraySlice<UInt8>) -> Double {
            Double(slice.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }) / 10000
        }
        left = be64(payload[0..<8])
        right = be64(payload[8..<16])
    }
}

public struct DebugAllData: Hashable, Sendable {
    public var messageVersion: Int
    public var hardwareVersion: String
    public var softwareVersion: String
    public var touchSoftwareVersion: String
    public var localAddress: String?
    public var peerAddress: String?
    public var leftAccelerometer: (x: Int16, y: Int16, z: Int16)
    public var rightAccelerometer: (x: Int16, y: Int16, z: Int16)
    public var leftProximity: Int16, leftProximityOffset: Int16
    public var rightProximity: Int16, rightProximityOffset: Int16
    public var leftTemperature: Double, rightTemperature: Double  // °C
    public var leftStateOfCharge: Int16, rightStateOfCharge: Int16  // %
    public var leftCellVoltage: Double, rightCellVoltage: Double  // V
    public var leftCurrent: Double, rightCurrent: Double  // mA, negative while charging
    public var leftTouchAbsolute: Int16, rightTouchAbsolute: Int16
    public var leftHall: UInt8, rightHall: UInt8
    public var leftInCradle: UInt8, rightInCradle: UInt8
    public var leftCradleBattery: UInt8, rightCradleBattery: UInt8

    public static func == (lhs: DebugAllData, rhs: DebugAllData) -> Bool {
        lhs.softwareVersion == rhs.softwareVersion && lhs.leftCellVoltage == rhs.leftCellVoltage
            && lhs.rightCellVoltage == rhs.rightCellVoltage && lhs.leftCurrent == rhs.leftCurrent
            && lhs.rightCurrent == rhs.rightCurrent && lhs.leftTemperature == rhs.leftTemperature
            && lhs.rightTemperature == rhs.rightTemperature
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(softwareVersion); hasher.combine(leftCellVoltage); hasher.combine(rightCellVoltage)
    }

    public init?(_ p: [UInt8], model: BudsModel) {
        guard model != .buds, p.count >= 5 else { return nil }
        var r = ByteReader(p)
        messageVersion = Int(r.byte() ?? 0)
        let hw = r.byte() ?? 0
        hardwareVersion = String(format: "rev%X.%X", hw >> 4, hw & 0x0F)

        let swLength: Int
        if model >= .buds3 {
            softwareVersion = r.ascii(20) ?? ""
            swLength = 20
        } else {
            let b0 = r.byte() ?? 0, b1 = r.byte() ?? 0, b2 = r.byte() ?? 0
            let years = Array("OPQRSTUVWXYZ"), months = Array("ABCDEFGHIJKL")
            let releases = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            let variant = (b0 & 1) == 0 ? "E" : "U"
            let year = Int(b1 >> 4) < years.count ? String(years[Int(b1 >> 4)]) : "?"
            let month = Int(b1 & 0x0F) < months.count ? String(months[Int(b1 & 0x0F)]) : "?"
            let release = Int(b2) < releases.count ? String(releases[Int(b2)]) : "?"
            softwareVersion = "\(model.buildPrefix)XX\(variant)0A\(year)\(month)\(release)"
            swLength = 3
        }
        let base = 2 + swLength
        guard p.count >= base + 81 else { return nil }
        touchSoftwareVersion = String(format: "0x%X", p[base])
        localAddress = ByteReader.macAddress(p, at: base + 1)
        peerAddress = ByteReader.macAddress(p, at: base + 7)
        func i16(_ o: Int) -> Int16 { ByteReader.int16(p, at: base + o) ?? 0 }
        leftAccelerometer = (i16(13), i16(15), i16(17))
        rightAccelerometer = (i16(19), i16(21), i16(23))
        leftProximity = i16(25); leftProximityOffset = i16(27)
        rightProximity = i16(29); rightProximityOffset = i16(31)
        leftTemperature = Double(i16(33)) * 0.1
        rightTemperature = Double(i16(35)) * 0.1
        leftStateOfCharge = i16(37)
        leftCellVoltage = Double(i16(39)) * 0.01
        leftCurrent = Double(i16(41)) * -0.1
        rightStateOfCharge = i16(43)
        rightCellVoltage = Double(i16(45)) * 0.01
        rightCurrent = Double(i16(47)) * -0.1
        leftTouchAbsolute = i16(49); rightTouchAbsolute = i16(51)
        leftHall = p[base + 65]; rightHall = p[base + 66]
        leftInCradle = p[base + 75]; rightInCradle = p[base + 76]
        leftCradleBattery = p[base + 77]; rightCradleBattery = p[base + 78]
    }
}

public struct UsageReport: Hashable, Sendable {
    public struct Entry: Hashable, Sendable, Identifiable {
        public var key: String
        public var value: UInt32
        public var id: String { key }
        public var label: String { UsageReport.labels[key] ?? key }
    }

    public var entries: [Entry]

    public init?(_ payload: [UInt8]) {
        guard let count = payload.first else { return nil }
        guard payload.count >= 1 + Int(count) * 9 else { return nil }
        var result: [Entry] = []
        var r = ByteReader(payload, offset: 1)
        for _ in 0..<Int(count) {
            guard let key = r.ascii(5), let value = r.int32() else { break }
            result.append(Entry(key: key, value: UInt32(bitPattern: value)))
        }
        entries = result
    }

    public static let labels: [String: String] = [
        "PLAY": "Single tap: play", "PAUS": "Single tap: pause", "NEXT": "Double tap: next",
        "PREV": "Triple tap: previous",
        "AMBD": "Ambient sound duration", "AMBC": "Ambient sound count", "A2DD": "Music streaming duration",
        "A2DC": "Music streaming count", "WEAD": "Wearing duration", "WEAC": "Wearing count",
        "LOWB": "Low battery events",
        "DISC": "Discharging errors", "CHAR": "Charging errors", "EAST": "CPU assertion exceptions",
        "LRLP": "Long press on both buds", "ANSC": "Calls answered by tap", "ENDC": "Calls ended by tap",
        "WLOD": "Wearing duration (left)", "WROD": "Wearing duration (right)", "WALD": "Wearing duration (both)",
        "MDSW": "Primary bud switches", "DCIC": "Disconnects during incoming call", "DCDC": "Disconnects during call",
        "ANCD": "Noise cancelling duration", "BSCR": "Battery charge cycles (right, x0.01)",
        "BSCL": "Battery charge cycles (left, x0.01)",
        "WDCL": "Wired charges (left)", "WDCR": "Wired charges (right)", "WLCL": "Wireless charges (left)",
        "WLCR": "Wireless charges (right)",
        "PSCL": "PowerShare charges (left)", "PSCR": "PowerShare charges (right)", "FBDA": "Firmware boots (A)",
        "FBDB": "Firmware boots (B)",
    ]
}

public struct GenericResponse: Hashable, Sendable {
    public var requestID: MessageID
    public var resultCode: UInt8
    public var extra: UInt8?

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 2 else { return nil }
        requestID = MessageID(payload[0])
        resultCode = payload[1]
        extra = payload.count > 2 ? payload[2] : nil
    }

    public var succeeded: Bool { resultCode == 0 }

    public var resultName: String {
        switch resultCode {
        case 0: return "Success"
        case 1: return "Failed"
        case 2: return "Fatal error"
        case 3: return "No resources"
        case 4: return "Resource busy"
        case 5: return "Timeout"
        case 6: return "Not found"
        case 9: return "Invalid parameter"
        case 10: return "I/O error"
        case 23: return "Invalid state"
        case 27: return "Rejected"
        case 137: return "Undefined message ID"
        case 152: return "Not allowed"
        case 155: return "Low battery"
        default: return "Code \(resultCode)"
        }
    }
}

public struct Acknowledgement: Hashable, Sendable {
    public var requestID: MessageID
    public var parameters: [UInt8]

    public init?(_ payload: [UInt8]) {
        guard let first = payload.first else { return nil }
        requestID = MessageID(first)
        parameters = Array(payload.dropFirst())
    }
}

public struct NoiseControlUpdate: Hashable, Sendable {
    public var mode: NoiseControlMode?
    public var rawMode: UInt8

    public init?(_ payload: [UInt8]) {
        guard let first = payload.first else { return nil }
        rawMode = first
        mode = NoiseControlMode(rawValue: first)
    }
}

public enum FitResult: UInt8, Sendable, CustomStringConvertible {
    case bad = 0, good = 1, failed = 2, unknown = 0xFF

    public var description: String {
        switch self {
        case .bad: return "Adjust the fit"
        case .good: return "Good fit"
        case .failed: return "Test failed"
        case .unknown: return "Unknown"
        }
    }
}

public struct FitTestResult: Hashable, Sendable {
    public var left: FitResult
    public var right: FitResult

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 2 else { return nil }
        left = FitResult(rawValue: payload[0]) ?? .unknown
        right = FitResult(rawValue: payload[1]) ?? .unknown
    }
}

/// A set bit means that check failed.
public struct SelfTestResult: Hashable, Sendable {
    public static let checks = [
        "Hardware version", "Software version", "Touch firmware version", "Left serial number", "Right serial number",
        "Left Bluetooth address", "Right Bluetooth address", "Left accelerometer X", "Left accelerometer Y",
        "Left accelerometer Z",
        "Right accelerometer X", "Right accelerometer Y", "Right accelerometer Z", "Left proximity", "Right proximity",
        "Left thermistor", "Right thermistor", "Left state of charge", "Left cell voltage", "Left current",
        "Right state of charge", "Right cell voltage", "Right current", "Left hall sensor", "Right hall sensor",
    ]

    public var mask: UInt32

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 4 else { return nil }
        mask = payload[0..<4].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }

    public var allPassed: Bool { mask & 0x01FF_FFFF == 0 }
    public func passed(_ index: Int) -> Bool { mask & (1 << UInt32(index)) == 0 }
    public var results: [(name: String, passed: Bool)] {
        Self.checks.enumerated().map { ($0.element, passed($0.offset)) }
    }
}

public enum SpatialAudioEvent: Hashable, Sendable {
    case orientation(w: Float, x: Float, y: Float, z: Float)
    case wearOn, wearOff
    case gyroscopeCalibration([Int16])
    case sensorStuck(UInt8)
    case sensorSupported(Bool)
    case other(UInt8, [UInt8])

    public init?(_ payload: [UInt8]) {
        guard let event = payload.first else { return nil }
        let data = Array(payload.dropFirst())
        switch event {
        case 32:
            guard data.count >= 8 else { return nil }
            func q(_ i: Int) -> Float { Float(ByteReader.int16(data, at: i) ?? 0) / 10000 }
            self = .orientation(w: q(0), x: q(2), y: q(4), z: q(6))
        case 33: self = .wearOn
        case 34: self = .wearOff
        case 35:
            var r = ByteReader(data)
            var values: [Int16] = []
            while let v = r.int16() { values.append(v) }
            self = .gyroscopeCalibration(values)
        case 36: self = .sensorStuck(data.first ?? 0)
        case 37: self = .sensorSupported((data.first ?? 0) != 0)
        default: self = .other(event, data)
        }
    }
}

public enum SpatialAudioControl: UInt8, Sendable {
    case attach = 0, detach = 1, attachSuccess = 2, detachSuccess = 3, keepAlive = 4, wearOnOff = 5
    case querySensorSupported = 6
}
