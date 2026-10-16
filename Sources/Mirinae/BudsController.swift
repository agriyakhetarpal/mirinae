// SPDX-License-Identifier: Apache-2.0
import Foundation
import AppKit
import IOBluetooth
import BudsProtocol

enum Side: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct LogEntry: Identifiable {
    enum Direction { case incoming, outgoing, note }
    let id = UUID()
    let date = Date()
    let direction: Direction
    let text: String
}

enum Preferences {
    static let selectedDevice = "selectedDevice"
    static let autoConnect = "autoConnect"
    static let hideDockIcon = "hideDockIcon"
    static let presentAsSamsung = "presentAsSamsung"
    static let customActionLeft = "customActionLeft"
    static let customActionRight = "customActionRight"
    static let knownModelPrefix = "knownModel."
    static let lastCasePrefix = "lastCase."
    static let personalNamePrefix = "personalName."
    static let autoRefreshInterval = "autoRefreshInterval"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            autoConnect: true, presentAsSamsung: true, hideDockIcon: false, autoRefreshInterval: 60.0,
        ])
    }
}

@MainActor
final class BudsController: ObservableObject {
    static let shared = BudsController()

    enum ConnectionState: Equatable {
        case disconnected, connecting, connected
        case failed(String)

        var label: String {
            switch self {
            case .disconnected: return "Not connected"
            case .connecting: return "Connecting…"
            case .connected: return "Connected"
            case .failed(let why): return why
            }
        }
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published var selectedAddress: String? {
        didSet { UserDefaults.standard.set(selectedAddress, forKey: Preferences.selectedDevice) }
    }
    @Published private(set) var deviceName = ""
    @Published private(set) var model: BudsModel = .buds2
    @Published private(set) var modelSource = "assumed"

    @Published private(set) var status: ExtendedStatus?
    @Published private(set) var sku: SkuInfo?
    @Published private(set) var serials: SerialNumbers?
    @Published private(set) var buildInfo: String?
    @Published private(set) var batteryTypes: BatteryTypes?
    @Published private(set) var cradle: CradleInfo?
    @Published private(set) var batteryCycles: BatteryCycles?
    @Published private(set) var debugData: DebugAllData?
    @Published private(set) var usage: UsageReport?
    @Published private(set) var fitResult: FitTestResult?
    @Published private(set) var fitTestRunning = false
    @Published private(set) var selfTest: SelfTestResult?
    @Published private(set) var versionInfoRaw: [UInt8]?
    @Published private(set) var lastResponse: GenericResponse?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var lastKnownCase: (level: Int, date: Date)?
    @Published private(set) var isRefreshing = false
    @Published private(set) var availableFirmware: [FirmwareBuild] = []
    @Published private(set) var firmwareCheckStatus: String?
    @Published private(set) var isCheckingFirmware = false
    @Published private(set) var firmwareTransfer: FirmwareTransfer?
    @Published private(set) var renameStatus: String?
    @Published private(set) var isRenaming = false
    @Published private(set) var renameSucceeded = false
    /// The name stored on the earbuds, known after a rename. macOS keeps showing the paired name.
    @Published private(set) var personalName: String?
    private var renameSession: RenameSession?
    private var reconnectAfterRename = false
    @Published private(set) var customEqualiserActive = false
    @Published private(set) var customEqualiserGains: [Int] = Array(repeating: 0, count: 9)

    @Published private(set) var isFinding = false
    @Published private(set) var mutedLeft = false
    @Published private(set) var mutedRight = false

    @Published private(set) var headTrackingActive = false
    @Published private(set) var orientation: (w: Float, x: Float, y: Float, z: Float)?
    @Published private(set) var orientationSamples = 0

    @Published private(set) var log: [LogEntry] = []
    @Published var showRawFrames = false

    private let transport = RFCOMMTransport()
    private let events = BluetoothEvents()
    private var parser = FrameParser()
    private var rawExtendedStatus: [UInt8]?
    private var sentManagerInfo = false
    private var keepAlive: Timer?
    private var refreshTimer: Timer?
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var refreshRequested = false
    private var autoRefreshTimer: Timer?
    private var connectTimeout: Task<Void, Never>?

    init() {
        Preferences.registerDefaults()
        selectedAddress = UserDefaults.standard.string(forKey: Preferences.selectedDevice)
        wireTransport()
        refreshDevices()
        if selectedAddress == nil { selectedAddress = devices.first?.address }
        events.onConnect = { [weak self] device in
            Task { @MainActor in self?.deviceCameOnline(device) }
        }
        events.onDisconnect = { [weak self] device in
            Task { @MainActor in self?.note("\(device.name ?? "Device") disconnected from this Mac") }
        }
        if UserDefaults.standard.bool(forKey: Preferences.autoConnect) { connect() }
    }

    // MARK: Connection

    var selectedDevice: DiscoveredDevice? {
        devices.first { $0.address == selectedAddress }
    }

    var isConnected: Bool { state == .connected }

    func refreshDevices() {
        devices = BluetoothFinder.pairedCandidates()
        if let selectedAddress, !devices.contains(where: { $0.address == selectedAddress }) {
            self.selectedAddress = devices.first?.address
        }
    }

    func connect() {
        guard !isRenaming else { return }
        refreshDevices()
        guard let device = selectedDevice else {
            state = .failed("No paired Galaxy Buds found")
            return
        }
        reconnectTask?.cancel()
        deviceName = device.name
        if let stored = UserDefaults.standard.object(forKey: Preferences.knownModelPrefix + device.address) as? Int,
            let known = BudsModel(rawValue: stored)
        {
            setModel(known, source: "remembered")
        } else if let guessed = BudsModel.from(deviceName: device.name) {
            setModel(guessed, source: "device name")
        } else {
            setModel(device.serviceUUID == ServiceUUID.sppNew ? .buds2 : .budsPlus, source: "assumed")
        }
        state = .connecting
        sentManagerInfo = false
        parser = FrameParser(framing: model.framing)
        personalName = UserDefaults.standard.string(forKey: Preferences.personalNamePrefix + device.address)
        if let saved = UserDefaults.standard.array(forKey: Preferences.lastCasePrefix + device.address) as? [Double],
            saved.count == 2
        {
            lastKnownCase = (Int(saved[0]), Date(timeIntervalSince1970: saved[1]))
        }
        note("Connecting to \(device.name)")
        transport.open(address: device.address, serviceUUID: device.serviceUUID)
        connectTimeout?.cancel()
        connectTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.state == .connecting else { return }
            self.transport.close()
            self.state = .failed("The earbuds did not answer. Try again, or take them out of the case.")
            self.note("Connection attempt timed out")
            self.scheduleReconnect()
        }
    }

    func cancelConnect() {
        connectTimeout?.cancel()
        reconnectTask?.cancel()
        transport.close()
        state = .disconnected
        note("Connection cancelled")
    }

    func disconnect() {
        connectTimeout?.cancel()
        reconnectTask?.cancel()
        stopHeadTracking()
        transport.close()
        state = .disconnected
    }

    // MARK: Rename

    private var pendingName = ""

    private var renameCloseFallback: Task<Void, Never>?

    func rename(to name: String) {
        guard !isRenaming, selectedDevice != nil else { return }
        pendingName = name
        isRenaming = true
        renameSucceeded = false
        renameStatus = "Closing the control channel"
        connectTimeout?.cancel()
        reconnectTask?.cancel()
        refreshRequested = false
        stopHeadTracking()
        if transport.isOpen {
            transport.close()
            // If the close callback never arrives, carry on anyway. The channel object is gone either way.
            renameCloseFallback = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self, self.isRenaming, self.renameSession == nil else { return }
                self.note("Close callback missing, starting the rename session anyway")
                self.startRenameSession()
            }
        } else {
            state = .disconnected
            startRenameSession()
        }
    }

    func cancelRename() {
        renameCloseFallback?.cancel()
        renameSession = nil
        guard isRenaming else { renameStatus = nil; return }
        isRenaming = false
        renameStatus = nil
        note("Rename cancelled")
        if !isConnected { connect() }
    }

    private func startRenameSession() {
        guard renameSession == nil else { return }
        guard let address = selectedDevice?.address else {
            finishRename(.failure(TransportError.unknownDevice)); return
        }
        let session = RenameSession(
            newName: pendingName,
            progress: { [weak self] text in
                self?.renameStatus = text
                self?.note("Rename: \(text)")
            },
            completion: { [weak self] result in
                self?.finishRename(result)
            })
        renameSession = session
        session.start(address: address)
    }

    private func finishRename(_ result: Result<String?, Error>) {
        renameCloseFallback?.cancel()
        renameSession = nil
        isRenaming = false
        switch result {
        case .success:
            renameStatus = nil
            renameSucceeded = true
            personalName = pendingName
            if let selectedAddress {
                UserDefaults.standard.set(pendingName, forKey: Preferences.personalNamePrefix + selectedAddress)
            }
            note(
                "Renamed the earbuds to \(pendingName). Paired devices keep showing the old name until they pair again."
            )
        case .failure(let error):
            renameSucceeded = false
            renameStatus = error.localizedDescription
            note("Rename failed: \(error.localizedDescription)")
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.connect()
        }
    }

    func clearRenameStatus() { renameStatus = nil; renameSucceeded = false }

    /// Disconnects the earbuds from the Mac entirely, the same as the Bluetooth menu.
    func disconnectBluetooth() {
        connectTimeout?.cancel()
        reconnectTask?.cancel()
        stopHeadTracking()
        transport.disconnectLink()
        state = .disconnected
        note("Disconnected the earbuds from this Mac")
    }

    /// Called on quit. Leaving the channel open makes the firmware refuse the next client for a while.
    func shutDown() {
        autoRefreshTimer?.invalidate()
        disconnect()
    }

    private func wireTransport() {
        transport.onOpen = { [weak self] in
            Task { @MainActor in self?.channelOpened() }
        }
        transport.onClose = { [weak self] in
            Task { @MainActor in self?.channelClosed() }
        }
        transport.onData = { [weak self] bytes in
            Task { @MainActor in self?.receive(bytes) }
        }
        transport.onNote = { [weak self] text in
            Task { @MainActor in self?.note(text) }
        }
        transport.onError = { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.connectTimeout?.cancel()
                self.state = .failed(error.localizedDescription)
                self.note("Error: \(error.localizedDescription)")
                self.scheduleReconnect()
            }
        }
    }

    private func channelOpened() {
        connectTimeout?.cancel()
        state = .connected
        reconnectAttempts = 0
        if let device = transport.device { events.watchDisconnect(of: device) }
        note("Channel open")
        startAutoRefresh()
        send(Commands.debugSku)
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isConnected else { return }
                self.send(Commands.debugAllData)
            }
        }
    }

    private func channelClosed() {
        let wasConnected = state == .connected
        state = .disconnected
        keepAlive?.invalidate()
        headTrackingActive = false
        refreshTimer?.invalidate()
        isFinding = false
        firmwareTransfer?.connectionDropped()
        if refreshRequested {
            refreshRequested = false
            connect()
            return
        }
        if isRenaming {
            note("Control channel closed for renaming")
            renameCloseFallback?.cancel()
            if renameSession == nil { startRenameSession() }
            return
        }
        note("Channel closed")
        if wasConnected { scheduleReconnect() }
    }

    /// The firmware only sends its status when the channel opens, so a refresh reopens it.
    func refreshStatus() {
        guard isConnected, !refreshRequested, !isRenaming, firmwareTransfer?.isActive != true else { return }
        refreshRequested = true
        isRefreshing = true
        stopHeadTracking()
        note("Refreshing status")
        transport.close()
    }

    func startAutoRefresh() {
        autoRefreshTimer?.invalidate()
        let interval = UserDefaults.standard.double(forKey: Preferences.autoRefreshInterval)
        guard interval > 0 else { return }
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isConnected, !self.headTrackingActive, !self.isFinding else { return }
                self.refreshStatus()
            }
        }
    }

    private func deviceCameOnline(_ device: IOBluetoothDevice) {
        guard device.addressString == selectedAddress, !isConnected,
            UserDefaults.standard.bool(forKey: Preferences.autoConnect)
        else { return }
        note("\(device.name ?? "Earbuds") connected to this Mac")
        reconnectAttempts = 0
        scheduleReconnect(after: 2)
    }

    private func scheduleReconnect(after seconds: Double? = nil) {
        guard UserDefaults.standard.bool(forKey: Preferences.autoConnect) else { return }
        guard let device = selectedDevice, IOBluetoothDevice(addressString: device.address)?.isConnected() == true
        else { return }
        reconnectTask?.cancel()
        let delay = seconds ?? min(3 * pow(2, Double(reconnectAttempts)), 60)
        reconnectAttempts += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.isConnected else { return }
            self.connect()
        }
    }

    private func setModel(_ newModel: BudsModel, source: String) {
        model = newModel
        modelSource = source
        parser.framing = newModel.framing
        if let selectedAddress {
            UserDefaults.standard.set(newModel.rawValue, forKey: Preferences.knownModelPrefix + selectedAddress)
        }
    }

    // MARK: Sending

    func send(_ message: SPPMessage, note text: String? = nil) {
        guard isConnected else { return }
        let bytes = message.encoded(framing: model.framing)
        if transport.write(bytes) {
            append(.outgoing, text ?? "\(message)", raw: bytes)
        } else {
            append(.note, "Write failed for \(message.id)")
        }
    }

    func sendRaw(id: UInt8, payload: [UInt8], asResponse: Bool) {
        send(SPPMessage(id: MessageID(id), payload: payload, isResponse: asResponse))
    }

    // MARK: Receiving

    private func receive(_ bytes: [UInt8]) {
        Self.logFile?.write(Data("\(Date()) raw \(bytes.hexString)\n".utf8))
        for message in parser.feed(bytes) {
            if showRawFrames {
                append(.incoming, "\(message)")
            } else if !Self.chattyIDs.contains(message.id) {
                append(.incoming, "\(message)")
            }
            handle(message)
        }
    }

    private static let chattyIDs: Set<MessageID> = [
        .debugEvent, MessageID(244), .meteringReport, .usageReport, .spatialAudioData, MessageID(39),
    ]

    private func handle(_ m: SPPMessage) {
        switch m.id {
        case .extendedStatusUpdated:
            rawExtendedStatus = m.payload
            decodeExtendedStatus(m.payload)
            if !sentManagerInfo {
                sentManagerInfo = true
                send(
                    Commands.managerInfo(
                        samsungDevice: UserDefaults.standard.bool(forKey: Preferences.presentAsSamsung)))
                send(Commands.updateTime())
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(600))
                    self?.refreshDiagnostics()
                }
            }
        case .statusUpdated:
            if let basic = BasicStatus.decode(m.payload, model: model) {
                if var s = status {
                    s.basic.batteryLeft = basic.batteryLeft
                    s.basic.batteryRight = basic.batteryRight
                    s.basic.batteryCase = basic.batteryCase ?? s.basic.batteryCase
                    s.basic.isCoupled = basic.isCoupled
                    s.basic.mainIsLeft = basic.mainIsLeft
                    s.basic.placementLeft = basic.placementLeft
                    s.basic.placementRight = basic.placementRight
                    if model.supports(.chargingState, revision: s.revision) {
                        s.basic.isLeftCharging = basic.isLeftCharging
                        s.basic.isRightCharging = basic.isRightCharging
                        s.basic.isCaseCharging = basic.isCaseCharging
                    }
                    status = s
                }
                lastUpdate = Date()
                rememberCase(basic.batteryCase)
            }
        case .noiseControlsUpdate, .noiseReductionModeUpdate:
            if let update = NoiseControlUpdate(m.payload) { status?.noiseControlMode = update.mode }
        case .touchUpdated:
            if let first = m.payload.first { status?.touchpadLocked = first != 0 }
        case .ambientVolume where !m.isResponse:
            if let first = m.payload.first { status?.ambientSoundVolume = Int(first) }
        case .acknowledgement:
            if let ack = Acknowledgement(m.payload) { apply(ack) }
        case .response:
            if let response = GenericResponse(m.payload) {
                lastResponse = response
                if !response.succeeded { note("\(response.requestID.name) failed: \(response.resultName)") }
            }
        case .debugSku:
            if let info = SkuInfo(m.payload) {
                sku = info
                if let detected = info.model, detected != model {
                    setModel(detected, source: "SKU")
                    if let raw = rawExtendedStatus { decodeExtendedStatus(raw) }
                } else if info.model != nil {
                    modelSource = "SKU"
                }
            }
        case .debugSerialNumber: serials = SerialNumbers(m.payload)
        case .debugBuildInfo: buildInfo = ByteReader.ascii(m.payload)
        case .batteryType: batteryTypes = BatteryTypes(m.payload)
        case .cradleSerialNumber: cradle = CradleInfo(m.payload)
        case .socBatteryCycle: batteryCycles = BatteryCycles(m.payload)
        case .debugGetAllData: debugData = DebugAllData(m.payload, model: model)
        case .usageReport: usage = UsageReport(m.payload)
        case .versionInfo: versionInfoRaw = m.payload
        case .checkTheFitOfEarbudsResult:
            fitResult = FitTestResult(m.payload)
            fitTestRunning = false
        case .selfTest: selfTest = SelfTestResult(m.payload)
        case .muteEarbudStatusUpdated where m.payload.count >= 2:
            mutedLeft = m.payload[0] != 0
            mutedRight = m.payload[1] != 0
        case .findMyEarbudsStop where !m.isResponse:
            isFinding = false
        case .spatialAudioData:
            if case let .orientation(w, x, y, z)? = SpatialAudioEvent(m.payload) {
                orientation = (w, x, y, z)
                orientationSamples += 1
            }
        case .setTouchpadOtherOption:
            if let first = m.payload.first, let action = model.touchMap.action(for: first) {
                runCustomAction(for: action == .otherLeft ? .left : .right)
            }
        case .fotaOpen, .fotaControl, .fotaDownloadData, .fotaUpdate, .fotaResult:
            firmwareTransfer?.handle(m)
        default:
            break
        }
    }

    // MARK: Firmware

    var currentFirmware: FirmwareBuild? {
        debugData.flatMap { FirmwareBuild(name: $0.softwareVersion) }
    }

    var newerFirmware: FirmwareBuild? {
        guard let current = currentFirmware, let newest = availableFirmware.first, newest > current else { return nil }
        return newest
    }

    func checkForFirmware() {
        guard !isCheckingFirmware else { return }
        isCheckingFirmware = true
        firmwareCheckStatus = nil
        let model = self.model
        Task { [weak self] in
            do {
                let builds = try await FirmwareArchive.builds(for: model)
                guard let self else { return }
                self.availableFirmware = builds
                if let newer = self.newerFirmware {
                    self.firmwareCheckStatus =
                        "\(newer.name) is available (\(newer.year)-\(String(format: "%02d", newer.month)))."
                } else if let newest = builds.first {
                    self.firmwareCheckStatus = "Up to date. Newest in the archive: \(newest.name)."
                } else {
                    self.firmwareCheckStatus = "The archive has no builds for \(model.displayName)."
                }
                self.note("Firmware check: \(self.firmwareCheckStatus ?? "")")
            } catch {
                self?.firmwareCheckStatus = error.localizedDescription
            }
            self?.isCheckingFirmware = false
        }
    }

    var firmwarePreflightProblem: String? {
        guard isConnected, let s = status else { return FirmwareError.notConnected.localizedDescription }
        if s.basic.batteryLeft < 30 || s.basic.batteryRight < 30 {
            return FirmwareError.lowBattery.localizedDescription
        }
        if firmwareTransfer?.isActive == true { return FirmwareError.busy.localizedDescription }
        return nil
    }

    func installFirmware(_ build: FirmwareBuild) {
        guard firmwarePreflightProblem == nil else { return }
        firmwareCheckStatus = "Downloading \(build.name)…"
        let model = self.model
        Task { [weak self] in
            do {
                let image = try await FirmwareArchive.download(build, expecting: model)
                self?.installFirmware(image: image)
            } catch {
                self?.firmwareCheckStatus = error.localizedDescription
            }
        }
    }

    func installFirmware(image: FirmwareImage, dryRun: Bool = false) {
        guard firmwarePreflightProblem == nil else { return }
        stopHeadTracking()
        autoRefreshTimer?.invalidate()
        let transfer = FirmwareTransfer(
            image: image,
            send: { [weak self] message in
                self?.send(message, note: message.id == .fotaDownloadData ? "FOTA_DOWNLOAD_DATA chunk" : nil)
            },
            log: { [weak self] text in
                self?.note(text)
            })
        transfer.dryRun = dryRun
        transfer.onDryRunComplete = { [weak self] in
            // Dropping the channel makes the firmware abort the pending session.
            self?.refreshStatus()
        }
        firmwareTransfer = transfer
        firmwareCheckStatus = nil
        transfer.start()
    }

    /// Developer aid: downloads the build the earbuds already run and walks the session up to
    /// the first data request.
    func firmwareDryRun() {
        guard let current = currentFirmware else { note("Dry run: firmware version not known yet"); return }
        let model = self.model
        Task { [weak self] in
            do {
                let image = try await FirmwareArchive.download(current, expecting: model)
                self?.installFirmware(image: image, dryRun: true)
            } catch {
                self?.note("Dry run: \(error.localizedDescription)")
            }
        }
    }

    func clearFirmwareTransfer() {
        firmwareTransfer?.cancel()
        firmwareTransfer = nil
        startAutoRefresh()
    }

    private func rememberCase(_ level: Int?) {
        guard let level, level > 0 else { return }
        lastKnownCase = (level, Date())
        if let selectedAddress {
            UserDefaults.standard.set(
                [Double(level), Date().timeIntervalSince1970], forKey: Preferences.lastCasePrefix + selectedAddress)
        }
    }

    private func decodeExtendedStatus(_ payload: [UInt8]) {
        if selectedDevice?.serviceUUID == ServiceUUID.sppNew, payload.count > 15,
            let color = ByteReader.int16(payload, at: 14).map({ DeviceColor(id: UInt16(bitPattern: $0)) }),
            let detected = color.model, detected != model, modelSource != "SKU"
        {
            setModel(detected, source: "colour code")
        }
        status = ExtendedStatus.decode(payload, model: model)
        lastUpdate = Date()
        isRefreshing = false
        rememberCase(status?.basic.batteryCase)
    }

    private func apply(_ ack: Acknowledgement) {
        guard var s = status, let first = ack.parameters.first else { return }
        switch ack.requestID {
        case .noiseControls: s.noiseControlMode = NoiseControlMode(rawValue: first)
        case .equalizer: s.equalizerPreset = EqualizerPreset(rawValue: Int(first)); s.equalizerRaw = Int(first)
        case .ambientVolume: s.ambientSoundVolume = Int(first)
        case .setSidetone: s.sidetone = first != 0
        case .setAncWithOneEarbud: s.noiseControlsWithOneEarbud = first != 0
        case .outsideDoubleTap: s.outsideDoubleTap = first != 0
        case .extraHighAmbient: s.extraHighAmbient = first != 0
        case .setVoiceWakeUp: s.voiceWakeUp = first != 0
        case .setSeamlessConnection: s.seamlessConnection = first == 0
        case .setCallPathControl: s.callPathControl = first == 0
        case .setHearingEnhancements: s.stereoBalance = Int(first)
        default: return
        }
        status = s
    }

    // MARK: Settings

    func setNoiseControl(_ mode: NoiseControlMode) {
        status?.noiseControlMode = mode
        send(Commands.noiseControls(mode))
    }

    func setAmbientVolume(_ level: Int) {
        status?.ambientSoundVolume = level
        send(Commands.ambientVolume(level))
    }

    func setExtraHighAmbient(_ on: Bool) {
        status?.extraHighAmbient = on
        send(Commands.extraHighAmbient(on))
        if !on, let volume = status?.ambientSoundVolume, volume > model.maximumAmbientVolume {
            setAmbientVolume(model.maximumAmbientVolume)
        }
    }

    func setCustomAmbient(enabled: Bool? = nil, left: Int? = nil, right: Int? = nil, tone: Int? = nil) {
        guard var s = status else { return }
        s.ambientCustomEnabled = enabled ?? s.ambientCustomEnabled ?? false
        s.ambientCustomVolumeLeft = left ?? s.ambientCustomVolumeLeft ?? 0
        s.ambientCustomVolumeRight = right ?? s.ambientCustomVolumeRight ?? 0
        s.ambientCustomTone = tone ?? s.ambientCustomTone ?? 2
        status = s
        send(
            Commands.customizeAmbient(
                enabled: s.ambientCustomEnabled!, left: s.ambientCustomVolumeLeft!,
                right: s.ambientCustomVolumeRight!, tone: s.ambientCustomTone!))
    }

    func setEqualizer(_ preset: EqualizerPreset) {
        customEqualiserActive = false
        status?.equalizerPreset = preset
        status?.equalizerRaw = preset.rawValue
        send(Commands.equalizer(preset))
    }

    func setCustomEqualiser(_ gains: [Int]) {
        customEqualiserGains = gains
        customEqualiserActive = true
        send(Commands.customEqualiser(gains))
        send(Commands.equalizerCustom)
    }

    func setStereoBalance(_ value: Int) {
        status?.stereoBalance = value
        send(Commands.stereoBalance(value))
    }

    func setSidetone(_ on: Bool) { status?.sidetone = on; send(Commands.sidetone(on)) }
    func setNoiseControlsWithOneEarbud(_ on: Bool) {
        status?.noiseControlsWithOneEarbud = on; send(Commands.noiseControlsWithOneEarbud(on))
    }
    func setOutsideDoubleTap(_ on: Bool) { status?.outsideDoubleTap = on; send(Commands.outsideDoubleTap(on)) }
    func setSeamlessConnection(_ on: Bool) { status?.seamlessConnection = on; send(Commands.seamlessConnection(on)) }
    func setCallPathControl(_ on: Bool) { status?.callPathControl = on; send(Commands.callPathControl(on)) }
    func setVoiceWakeUp(_ on: Bool) { status?.voiceWakeUp = on; send(Commands.voiceWakeUp(on)) }
    func setVoiceWakeUpLanguage(_ code: Int) {
        status?.voiceWakeUpLanguage = code; send(Commands.voiceWakeUpLanguage(code))
    }
    func setSpeakSeamlessly(_ on: Bool) { status?.speakSeamlessly = on; send(Commands.speakSeamlessly(on)) }
    func setDetectConversations(_ on: Bool) { status?.detectConversations = on; send(Commands.detectConversations(on)) }
    func setExtraClearCallSound(_ on: Bool) { status?.extraClearCallSound = on; send(Commands.extraClearCallSound(on)) }
    func setAdjustSoundSync(_ on: Bool) { status?.adjustSoundSync = on; send(Commands.adjustSoundSync(on)) }

    func setTouchActions(left: TouchAction? = nil, right: TouchAction? = nil) {
        guard var s = status else { return }
        let l = left ?? s.touchActionLeft ?? .noiseControls
        let r = right ?? s.touchActionRight ?? .noiseControls
        guard let message = Commands.touchActions(left: l, right: r, map: model.touchMap) else { return }
        s.touchActionLeft = l
        s.touchActionRight = r
        status = s
        send(message)
    }

    func setTouchLock(
        lockAll: Bool? = nil, singleTap: Bool? = nil, doubleTap: Bool? = nil, tripleTap: Bool? = nil,
        touchHold: Bool? = nil, doubleTapForCalls: Bool? = nil, touchHoldForCalls: Bool? = nil
    ) {
        guard var s = status else { return }
        if !model.supports(.advancedTouchLock, revision: s.revision) {
            let locked = lockAll ?? s.touchpadLocked
            s.touchpadLocked = locked
            status = s
            send(Commands.touchLock(locked))
            return
        }
        s.touchpadLocked = lockAll ?? s.touchpadLocked
        s.singleTapEnabled = singleTap ?? s.singleTapEnabled ?? true
        s.doubleTapEnabled = doubleTap ?? s.doubleTapEnabled ?? true
        s.tripleTapEnabled = tripleTap ?? s.tripleTapEnabled ?? true
        s.touchHoldEnabled = touchHold ?? s.touchHoldEnabled ?? true
        let calls = model.supports(.advancedTouchLockForCalls, revision: s.revision)
        if calls {
            s.doubleTapForCallEnabled = doubleTapForCalls ?? s.doubleTapForCallEnabled ?? true
            s.touchHoldForCallEnabled = touchHoldForCalls ?? s.touchHoldForCallEnabled ?? true
        }
        status = s
        send(
            Commands.touchLock(
                lockAll: s.touchpadLocked, singleTap: s.singleTapEnabled!, doubleTap: s.doubleTapEnabled!,
                tripleTap: s.tripleTapEnabled!, touchHold: s.touchHoldEnabled!,
                doubleTapForCalls: calls ? s.doubleTapForCallEnabled : nil,
                touchHoldForCalls: calls ? s.touchHoldForCallEnabled : nil))
    }

    func setNoiseControlCycle(left: NoiseControlCycle? = nil, right: NoiseControlCycle? = nil) {
        guard var s = status else { return }
        let l = left ?? s.noiseControlCycleLeft ?? .ancAndAmbient
        let dual = model.supports(.noiseControlModeDualSide, revision: s.revision)
        let r = dual ? (right ?? s.noiseControlCycleRight ?? .ancAndAmbient) : l
        s.noiseControlCycleLeft = l
        s.noiseControlCycleRight = r
        status = s
        send(Commands.touchAndHoldNoiseControls(left: l, right: dual ? r : nil, model: model))
    }

    func enterPairingMode() {
        note("Asked the earbuds to enter pairing mode")
        send(Commands.pairingMode)
    }

    func switchMainBud() {
        guard let s = status else { return }
        send(Commands.switchMainBud(toLeft: !s.basic.mainIsLeft))
    }

    // MARK: Find my earbuds

    func startFinding() {
        isFinding = true
        send(
            Commands.findMyEarbudsStart(
                ringWhileWearing: model.supports(.fmgRingWhileWearing, revision: status?.revision)))
    }

    func stopFinding() {
        isFinding = false
        mutedLeft = false
        mutedRight = false
        send(Commands.findMyEarbudsStop)
    }

    func setMute(left: Bool? = nil, right: Bool? = nil) {
        mutedLeft = left ?? mutedLeft
        mutedRight = right ?? mutedRight
        send(Commands.muteEarbuds(left: mutedLeft, right: mutedRight))
    }

    // MARK: Diagnostics

    func refreshDiagnostics() {
        send(Commands.debugAllData)
        send(Commands.debugSerialNumber)
        send(Commands.debugBuildInfo)
        send(Commands.batteryType)
        send(Commands.versionInfo)
        if model.supports(.cradleSerialNumber, revision: status?.revision) { send(Commands.cradleSerialNumber) }
        send(Commands.batteryCycles)
    }

    func runFitTest() {
        fitResult = nil
        fitTestRunning = true
        send(Commands.fitTest(true))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, self.fitTestRunning else { return }
            self.fitTestRunning = false
            self.send(Commands.fitTest(false))
        }
    }

    func cancelFitTest() {
        fitTestRunning = false
        send(Commands.fitTest(false))
    }

    func runSelfTest() {
        selfTest = nil
        send(Commands.selfTest)
    }

    func factoryReset() {
        note("Factory reset requested")
        send(Commands.factoryReset)
    }

    // MARK: Head tracking

    func startHeadTracking() {
        guard isConnected else { return }
        headTrackingActive = true
        orientationSamples = 0
        send(Commands.spatialAudio(true))
        send(Commands.spatialControl(.attach))
        keepAlive?.invalidate()
        keepAlive = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.send(Commands.spatialControl(.keepAlive)) }
        }
    }

    func stopHeadTracking() {
        keepAlive?.invalidate()
        keepAlive = nil
        guard headTrackingActive else { return }
        headTrackingActive = false
        orientation = nil
        send(Commands.spatialControl(.detach))
        send(Commands.spatialAudio(false))
    }

    // MARK: Custom tap-and-hold actions

    private func runCustomAction(for side: Side) {
        let key = side == .left ? Preferences.customActionLeft : Preferences.customActionRight
        guard let command = UserDefaults.standard.string(forKey: key),
            !command.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            note("Custom tap-and-hold on the \(side.rawValue) bud, but no command is configured")
            return
        }
        note("Running custom action for the \(side.rawValue) bud")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        do { try process.run() } catch { note("Could not run command: \(error.localizedDescription)") }
    }

    // MARK: Log

    // Set MIRINAE_LOG_FILE=/path/to/file to mirror the console to disk.
    private static let logFile: FileHandle? = {
        guard let path = ProcessInfo.processInfo.environment["MIRINAE_LOG_FILE"] else { return nil }
        FileManager.default.createFile(atPath: path, contents: nil)
        let handle = FileHandle(forWritingAtPath: path)
        handle?.seekToEndOfFile()
        return handle
    }()

    func note(_ text: String) { append(.note, text) }

    func clearLog() { log.removeAll() }

    private func append(_ direction: LogEntry.Direction, _ text: String, raw: [UInt8]? = nil) {
        var line = text
        if showRawFrames, let raw { line += "  <\(raw.hexString)>" }
        log.append(LogEntry(direction: direction, text: line))
        Self.logFile?.write(Data("\(Date()) \(direction) \(line)\n".utf8))
        if log.count > 600 { log.removeFirst(log.count - 600) }
    }
}
