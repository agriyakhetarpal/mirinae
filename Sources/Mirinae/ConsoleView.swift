// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import BudsProtocol

struct ConsoleView: View {
    @EnvironmentObject private var controller: BudsController
    @StateObject private var ui = UIState()

    final class UIState: ObservableObject {
        @Published var idText = ""
        @Published var payloadText = ""
        @Published var asResponse = false
        @Published var sendError: String?
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(controller.log) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .foregroundStyle(.tertiary)
                        Text(verbatim: symbol(entry.direction))
                            .foregroundStyle(color(entry.direction))
                            .frame(width: 14)
                        Text(verbatim: entry.text).textSelection(.enabled)
                    }
                    .font(.callout.monospaced())
                    .listRowSeparator(.hidden)
                    .id(entry.id)
                }
                .listStyle(.plain)
                .onChange(of: controller.log.count) {
                    if let last = controller.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            composer
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $controller.showRawFrames) { Label("Raw frames", systemImage: "number") }
                Button {
                    controller.clearLog()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Message ID (decimal or 0x..)", text: $ui.idText)
                    .frame(width: 180)
                TextField("Payload bytes, hex (optional)", text: $ui.payloadText)
                Toggle("As response", isOn: $ui.asResponse)
                Button("Send") { send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!controller.isConnected || ui.idText.isEmpty)
            }
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            HStack {
                if let error = ui.sendError {
                    Text(error).foregroundStyle(.red)
                } else if let id = parsedID {
                    Text(verbatim: "→ \(MessageID(id).description)").foregroundStyle(.secondary)
                }
                Spacer()
                Text("Anything you send goes straight to the firmware. Avoid IDs you do not recognise.")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
        }
        .padding(12)
    }

    private var parsedID: UInt8? {
        let t = ui.idText.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("0x") { return UInt8(t.dropFirst(2), radix: 16) }
        return UInt8(t)
    }

    private func send() {
        guard let id = parsedID else { ui.sendError = "Bad message ID"; return }
        guard let payload = ui.payloadText.isEmpty ? [] : [UInt8](hexString: ui.payloadText) else {
            ui.sendError = "Bad payload hex"; return
        }
        ui.sendError = nil
        controller.sendRaw(id: id, payload: payload, asResponse: ui.asResponse)
    }

    private func symbol(_ d: LogEntry.Direction) -> String {
        switch d {
        case .incoming: return "←"
        case .outgoing: return "→"
        case .note: return "•"
        }
    }

    private func color(_ d: LogEntry.Direction) -> Color {
        switch d {
        case .incoming: return .blue
        case .outgoing: return .green
        case .note: return .secondary
        }
    }
}
