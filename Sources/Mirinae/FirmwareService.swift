// SPDX-License-Identifier: Apache-2.0
import Foundation
import BudsProtocol

/// Talks to the community firmware archive, which mirrors Samsung's official images.
enum FirmwareArchive {
    static let base = URL(string: "https://fw.timschneeberger.me/v3/firmware")!

    struct Entry: Decodable {
        let buildName: String
        let year: Int
        let month: Int
        let revision: Int

        var build: FirmwareBuild { FirmwareBuild(name: buildName, year: year, month: month, revision: revision) }
    }

    static func archiveName(for model: BudsModel) -> String {
        switch model {
        case .buds: return "Buds"
        case .budsPlus: return "BudsPlus"
        case .budsLive: return "BudsLive"
        case .budsPro: return "BudsPro"
        case .buds2: return "Buds2"
        case .buds2Pro: return "Buds2Pro"
        case .budsFE: return "BudsFe"
        case .budsCore: return "BudsCore"
        case .buds3: return "Buds3"
        case .buds3Pro: return "Buds3Pro"
        case .buds3FE: return "Buds3Fe"
        case .buds4: return "Buds4"
        case .buds4Pro: return "Buds4Pro"
        }
    }

    static func builds(for model: BudsModel) async throws -> [FirmwareBuild] {
        let url = base.appendingPathComponent(archiveName(for: model))
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FirmwareError.archiveUnavailable }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        return entries.filter { $0.buildName.hasPrefix(model.buildPrefix) }.map(\.build).sorted(by: >)
    }

    static func download(_ build: FirmwareBuild, expecting model: BudsModel) async throws -> FirmwareImage {
        let url = base.appendingPathComponent("download").appendingPathComponent(build.name)
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FirmwareError.archiveUnavailable }
        guard data.count <= 32_000_000 else { throw FirmwareError.imageTooLarge }
        let image = try FirmwareImage([UInt8](data))
        guard image.model == model else { throw FirmwareError.wrongModel(image.model) }
        return image
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        configuration.httpAdditionalHeaders = ["User-Agent": "Mirinae"]
        return URLSession(configuration: configuration)
    }()
}

enum FirmwareError: LocalizedError {
    case archiveUnavailable, imageTooLarge, wrongModel(BudsModel?), notConnected, lowBattery, busy
    case sessionRejected(Int), timeout(String), copyFailed(Int), verifyFailed(Int), disconnected

    var errorDescription: String? {
        switch self {
        case .archiveUnavailable: return "The firmware archive did not answer."
        case .imageTooLarge: return "The downloaded file is larger than any known firmware image."
        case .wrongModel(let model):
            return "That image is for \(model?.displayName ?? "a different model"), not these earbuds."
        case .notConnected: return "The earbuds are not connected."
        case .lowBattery: return "Both earbuds need at least 30% battery before updating."
        case .busy: return "A transfer is already running."
        case .sessionRejected(let code): return "The earbuds refused the update session (code \(code))."
        case .timeout(let stage): return "The earbuds stopped answering while \(stage)."
        case .copyFailed(let code): return "The earbuds reported a copy error (code \(code))."
        case .verifyFailed(let code): return "The earbuds could not verify the image (code \(code))."
        case .disconnected: return "The connection dropped during the transfer."
        }
    }
}

/// Drives one firmware transfer. The earbuds pull the image: they ask for a chunk size, say
/// which segment they want, request packets, report progress, and finally reboot to flash.
@MainActor
final class FirmwareTransfer: ObservableObject {
    enum Phase: Equatable {
        case idle, opening, negotiating, sending, flashing, done
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .opening: return "Opening the update session"
            case .negotiating: return "Waiting for the earbuds"
            case .sending: return "Sending the image"
            case .flashing: return "The earbuds are installing the update"
            case .done: return "Done. The earbuds will restart and reconnect."
            case .failed(let why): return why
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var percent = 0
    @Published private(set) var bytesSent = 0
    @Published private(set) var totalBytes = 0

    private let image: FirmwareImage
    private let send: (SPPMessage) -> Void
    private let log: (String) -> Void
    /// Stops at the first data request. Used to exercise the session without flashing anything.
    var dryRun = false
    var onDryRunComplete: (() -> Void)?
    private var mtu = 0
    private var segment: FirmwareImage.Segment?
    private var watchdog: Task<Void, Never>?

    var isActive: Bool {
        switch phase {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    init(image: FirmwareImage, send: @escaping (SPPMessage) -> Void, log: @escaping (String) -> Void) {
        self.image = image
        self.send = send
        self.log = log
        totalBytes = image.segments.reduce(0) { $0 + $1.data.count }
    }

    func start() {
        phase = .opening
        log("Firmware: opening session for \(image.segments.count) segment(s), \(totalBytes) bytes")
        send(Fota.open(image))
        arm("opening the session")
    }

    func cancel(_ reason: String = "Cancelled") {
        watchdog?.cancel()
        if isActive { phase = .failed(reason) }
    }

    func connectionDropped() {
        guard isActive else { return }
        watchdog?.cancel()
        if phase == .flashing {
            phase = .done
        } else {
            phase = .failed(FirmwareError.disconnected.localizedDescription)
        }
    }

    func handle(_ message: SPPMessage) {
        guard isActive else { return }
        switch message.id {
        case .fotaOpen:
            let code = Int(message.payload.first ?? 1)
            if code == 0 {
                phase = .negotiating
                log("Firmware: session accepted")
                arm("negotiating")
            } else {
                fail(FirmwareError.sessionRejected(code))
            }
        case .fotaControl:
            guard let request = Fota.ControlRequest(message.payload) else { return }
            switch request.control {
            case .sendMTU:
                mtu = min(request.value, Fota.maximumMTU)
                log("Firmware: chunk size \(mtu)")
            case .readyToDownload:
                segment = image.segment(id: UInt8(truncatingIfNeeded: request.value))
                log("Firmware: earbuds want segment \(request.value)")
            }
            send(Fota.controlResponse(request.control, value: request.control == .sendMTU ? mtu : request.value))
            arm("negotiating")
        case .fotaDownloadData:
            guard let request = Fota.DownloadRequest(message.payload), let segment, mtu > 0 else { return }
            if dryRun {
                watchdog?.cancel()
                log(
                    "Firmware dry run: earbuds asked for \(request.packets) packet(s) from offset \(request.offset) of segment \(segment.id) (\(segment.data.count) bytes), chunk \(mtu). Stopping here."
                )
                phase = .failed("Dry run complete, nothing was sent")
                onDryRunComplete?()
                return
            }
            phase = .sending
            for i in 0..<request.packets {
                let offset = request.offset + mtu * i
                guard offset < segment.data.count else { break }
                send(Fota.downloadChunk(segment: segment, offset: offset, mtu: mtu))
                bytesSent = min(offset + mtu, segment.data.count)
            }
            arm("sending the image")
        case .fotaUpdate:
            guard let notice = Fota.UpdateNotice(message.payload) else { return }
            switch notice.kind {
            case .percent:
                percent = notice.value
                arm("sending the image")
            case .stateChange:
                send(Fota.updateAck)
                if notice.value == 0 {
                    log("Firmware: transfer complete, earbuds are flashing")
                    watchdog?.cancel()
                    phase = .flashing
                } else {
                    fail(FirmwareError.copyFailed(notice.resultCode))
                }
            }
        case .fotaResult:
            guard let result = Fota.Result(message.payload) else { return }
            send(Fota.resultAck)
            if result.succeeded {
                log("Firmware: verified, earbuds will restart")
                watchdog?.cancel()
                phase = .flashing
            } else {
                fail(FirmwareError.verifyFailed(result.errorCode))
            }
        default:
            break
        }
    }

    private func fail(_ error: FirmwareError) {
        watchdog?.cancel()
        log("Firmware: \(error.localizedDescription)")
        phase = .failed(error.localizedDescription)
    }

    private func arm(_ stage: String) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.isActive else { return }
            self.fail(FirmwareError.timeout(stage))
        }
    }
}
