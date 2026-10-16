// SPDX-License-Identifier: Apache-2.0
import Foundation

/// The secondary "SMEP" channel speaks a property protocol: every frame carries message id 1,
/// and the first payload byte says whether it reads, writes, or notifies properties.
public enum AltMessage {
    public static let frameID = MessageID(1)
    public static let writeProperty: UInt8 = 67
    public static let readProperty: UInt8 = 68
    public static let notifyProperty: UInt8 = 69
}

public struct AltProperty: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(_ rawValue: UInt16) { self.rawValue = rawValue }

    public static let supportedFeatures = AltProperty(256)
    public static let featureChangeDeviceName = AltProperty(281)
    public static let allCurrentStates = AltProperty(512)
    public static let stateCurrentName = AltProperty(550)
    public static let personalizedNameTimestamp = AltProperty(775)
    public static let personalizedNameValue = AltProperty(776)
}

/// Type (16-bit little-endian), length, data.
public struct AltPropertyValue: Hashable, Sendable {
    public var type: AltProperty
    public var data: [UInt8]

    public init(_ type: AltProperty, _ data: [UInt8]) {
        self.type = type
        self.data = data
    }

    public func encoded() -> [UInt8] {
        [UInt8(type.rawValue & 0xFF), UInt8(type.rawValue >> 8), UInt8(truncatingIfNeeded: data.count)] + data
    }

    public static func decodeList(_ bytes: [UInt8]) -> [AltPropertyValue] {
        var result: [AltPropertyValue] = []
        var i = 0
        while i + 3 <= bytes.count {
            let type = AltProperty(UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8)
            let length = min(Int(bytes[i + 2]), bytes.count - i - 3)
            result.append(AltPropertyValue(type, Array(bytes[(i + 3)..<(i + 3 + length)])))
            i += 3 + length
        }
        return result
    }
}

/// Reply to a read: the property that was asked for, then the values.
public struct AltReadResponse: Hashable, Sendable {
    public var requested: AltProperty
    public var values: [AltPropertyValue]

    public init?(_ message: SPPMessage) {
        guard message.id == AltMessage.frameID, message.payload.count >= 3,
            message.payload[0] == AltMessage.readProperty
        else { return nil }
        requested = AltProperty(UInt16(message.payload[1]) | UInt16(message.payload[2]) << 8)
        values = AltPropertyValue.decodeList(Array(message.payload.dropFirst(3)))
    }

    public func value(_ type: AltProperty) -> [UInt8]? {
        values.first { $0.type == type }?.data
    }
}

public enum AltCommands {
    public static func read(_ property: AltProperty) -> SPPMessage {
        SPPMessage(
            id: AltMessage.frameID,
            payload: [AltMessage.readProperty, UInt8(property.rawValue & 0xFF), UInt8(property.rawValue >> 8)])
    }

    public static func write(_ values: [AltPropertyValue]) -> SPPMessage {
        SPPMessage(id: AltMessage.frameID, payload: [AltMessage.writeProperty] + values.flatMap { $0.encoded() })
    }

    /// Name plus a timestamp, each prefixed with two zero bytes as Samsung's app does.
    public static func rename(_ name: String, date: Date = Date()) -> SPPMessage {
        let seconds = UInt64(date.timeIntervalSince1970)
        var stamp: [UInt8] = [0, 0]
        for i in 0..<8 { stamp.append(UInt8((seconds >> (8 * UInt64(i))) & 0xFF)) }
        return write([
            AltPropertyValue(.personalizedNameTimestamp, stamp),
            AltPropertyValue(.personalizedNameValue, [0, 0] + Array(name.utf8)),
        ])
    }
}
