// SPDX-License-Identifier: Apache-2.0
import Foundation
import IOBluetooth
import BudsProtocol

struct DiscoveredDevice: Identifiable, Hashable {
    let address: String
    let name: String
    let serviceUUID: UUID
    let isConnected: Bool
    var id: String { address }
}

enum BluetoothFinder {
    static let controlUUIDs = [ServiceUUID.sppNew, ServiceUUID.sppStandard, ServiceUUID.sppLegacy]

    static func pairedCandidates() -> [DiscoveredDevice] {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return devices.compactMap { device in
            guard let address = device.addressString, let name = device.name else { return nil }
            for uuid in controlUUIDs where device.getServiceRecord(for: sdpUUID(uuid)) != nil {
                // Lots of unrelated devices expose plain SPP, so for the older UUIDs require a Buds-like name.
                if uuid != ServiceUUID.sppNew && BudsModel.from(deviceName: name) == nil { continue }
                return DiscoveredDevice(
                    address: address, name: name, serviceUUID: uuid, isConnected: device.isConnected())
            }
            return nil
        }
    }

    static func sdpUUID(_ uuid: UUID) -> IOBluetoothSDPUUID {
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        return IOBluetoothSDPUUID(bytes: bytes, length: 16)
    }
}

final class BluetoothEvents: NSObject {
    var onConnect: ((IOBluetoothDevice) -> Void)?
    var onDisconnect: ((IOBluetoothDevice) -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    override init() {
        super.init()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    deinit {
        connectNotification?.unregister()
        disconnectNotifications.values.forEach { $0.unregister() }
    }

    func watchDisconnect(of device: IOBluetoothDevice) {
        guard let address = device.addressString, disconnectNotifications[address] == nil else { return }
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onConnect?(device)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onDisconnect?(device)
    }
}

enum TransportError: LocalizedError {
    case unknownDevice, noServiceRecord, noChannel, openFailed(IOReturn), linkFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .unknownDevice: return "The Bluetooth device could not be found. Is it paired?"
        case .noServiceRecord: return "The earbuds did not advertise a control channel. Try reconnecting them."
        case .noChannel: return "The service record has no RFCOMM channel."
        case .openFailed(let code): return "Opening the channel failed (IOReturn \(code))."
        case .linkFailed(let code):
            return "The earbuds did not connect to this Mac (IOReturn \(code)). Are they out of the case and in range?"
        }
    }
}

final class RFCOMMTransport: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onData: (([UInt8]) -> Void)?
    var onError: ((Error) -> Void)?
    var onNote: ((String) -> Void)?

    private(set) var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var pendingUUID: UUID?

    var isOpen: Bool { channel?.isOpen() ?? false }

    func open(address: String, serviceUUID: UUID) {
        close()
        guard let device = IOBluetoothDevice(addressString: address) else {
            onError?(TransportError.unknownDevice)
            return
        }
        self.device = device
        pendingUUID = serviceUUID
        if !device.isConnected() {
            onNote?("Connecting the earbuds to this Mac")
            let result = device.openConnection(self)
            if result != kIOReturnSuccess { onError?(TransportError.openFailed(result)) }
            return
        }
        lookUpServiceAndOpen()
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        guard status == kIOReturnSuccess else {
            onError?(TransportError.linkFailed(status))
            return
        }
        lookUpServiceAndOpen()
    }

    private func lookUpServiceAndOpen() {
        guard let device, let serviceUUID = pendingUUID else { return }
        if device.getServiceRecord(for: BluetoothFinder.sdpUUID(serviceUUID)) != nil {
            openChannel()
        } else {
            onNote?("No cached service record, running an SDP query")
            device.performSDPQuery(self)
        }
    }

    /// Drops the Bluetooth link itself, not just the control channel.
    func disconnectLink() {
        close()
        device?.closeConnection()
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        guard status == kIOReturnSuccess else {
            onError?(TransportError.openFailed(status))
            return
        }
        openChannel()
    }

    private func openChannel() {
        guard let device, let uuid = pendingUUID else { return }
        guard let record = device.getServiceRecord(for: BluetoothFinder.sdpUUID(uuid)) else {
            onError?(TransportError.noServiceRecord)
            return
        }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
            onError?(TransportError.noChannel)
            return
        }
        var newChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
        guard result == kIOReturnSuccess, let newChannel else {
            onError?(TransportError.openFailed(result))
            return
        }
        onNote?("Opening RFCOMM channel \(channelID)")
        channel = newChannel
    }

    func close() {
        channel?.close()
        channel = nil
    }

    @discardableResult
    func write(_ bytes: [UInt8]) -> Bool {
        guard let channel, channel.isOpen() else { return false }
        var copy = bytes
        return channel.writeSync(&copy, length: UInt16(copy.count)) == kIOReturnSuccess
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess {
            onOpen?()
        } else {
            channel = nil
            onNote?("Channel open failed with IOReturn \(error)")
            onError?(TransportError.openFailed(error))
        }
    }

    func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int
    ) {
        let bytes = Array(
            UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        onData?(bytes)
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        channel = nil
        onClose?()
    }
}
