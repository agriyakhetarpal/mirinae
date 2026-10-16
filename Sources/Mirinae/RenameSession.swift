// SPDX-License-Identifier: Apache-2.0
import Foundation
import BudsProtocol

/// Renames the earbuds over the secondary channel. The main control channel must be closed
/// first. The firmware serves one client at a time.
@MainActor
final class RenameSession {
    enum Failure: LocalizedError {
        case unsupported, tooLong(Int), timeout, transport(String)

        var errorDescription: String? {
            switch self {
            case .unsupported: return "These earbuds do not support renaming."
            case .tooLong(let limit): return "The name must be shorter than \(limit) bytes."
            case .timeout: return "The earbuds did not confirm the new name."
            case .transport(let why): return why
            }
        }
    }

    private let transport = RFCOMMTransport()
    private let parser = FrameParser(framing: .alternative)
    private var finished = false
    private var limit: Int?
    private var timeout: Task<Void, Never>?
    private let newName: String
    private let progress: (String) -> Void
    private let completion: (Result<String?, Error>) -> Void
    private(set) var previousName: String?

    init(newName: String, progress: @escaping (String) -> Void, completion: @escaping (Result<String?, Error>) -> Void)
    {
        self.newName = newName
        self.progress = progress
        self.completion = completion
    }

    func start(address: String) {
        transport.onOpen = { [weak self] in Task { @MainActor in self?.opened() } }
        transport.onNote = { [weak self] text in Task { @MainActor in self?.progress(text) } }
        transport.onData = { [weak self] bytes in Task { @MainActor in self?.receive(bytes) } }
        transport.onError = { [weak self] error in
            Task { @MainActor in self?.finish(.failure(Failure.transport(error.localizedDescription))) }
        }
        transport.onClose = { [weak self] in Task { @MainActor in self?.finish(.failure(Failure.timeout)) } }
        progress("Opening the secondary channel")
        transport.open(address: address, serviceUUID: ServiceUUID.smep)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.finish(.failure(Failure.timeout))
        }
    }

    private func opened() {
        progress("Checking what the earbuds allow")
        send(AltCommands.read(.supportedFeatures))
        send(AltCommands.read(.allCurrentStates))
    }

    private func send(_ message: SPPMessage) {
        transport.write(message.encoded(framing: .alternative))
    }

    private func receive(_ bytes: [UInt8]) {
        for message in parser.feed(bytes) {
            if let response = AltReadResponse(message) {
                switch response.requested {
                case .supportedFeatures:
                    guard let value = response.value(.featureChangeDeviceName), let first = value.first else {
                        finish(.failure(Failure.unsupported))
                        return
                    }
                    limit = Int(first)
                    guard newName.utf8.count < limit! else {
                        finish(.failure(Failure.tooLong(limit!)))
                        return
                    }
                    progress("Sending the new name")
                    send(AltCommands.rename(newName))
                case .allCurrentStates:
                    if let name = response.value(.stateCurrentName) { previousName = ByteReader.ascii(name) }
                default:
                    break
                }
            } else if message.id == AltMessage.frameID, message.payload.first == MessageID.acknowledgement.rawValue {
                // The acknowledgement echoes the properties that were written.
                finish(.success(previousName))
            }
        }
    }

    private func finish(_ result: Result<String?, Error>) {
        guard !finished else { return }
        finished = true
        timeout?.cancel()
        transport.onClose = nil
        transport.close()
        completion(result)
    }
}
