// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import BudsProtocol

struct DeviceView: View {
    @EnvironmentObject private var controller: BudsController
    @StateObject private var ui = UIState()

    final class UIState: ObservableObject {
        @Published var confirmReset = false
        @Published var showUsage = false
        @Published var confirmInstall = false
        @Published var pendingBuild: FirmwareBuild?
        @Published var pendingImage: FirmwareImage?
    }

    var body: some View {
        Form {
            identity
            firmware
            battery
            sensors
            tests
            danger
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem {
                Button {
                    controller.refreshDiagnostics()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!controller.isConnected)
            }
        }
    }

    private var identity: some View {
        SwiftUI.Section("Identity") {
            LabeledContent("Name") { Text(verbatim: controller.deviceName.isEmpty ? "–" : controller.deviceName) }
            LabeledContent("Model") {
                HStack {
                    Text(verbatim: controller.model.displayName)
                    Text(localizing: "via \(controller.modelSource)").foregroundStyle(.secondary)
                }
            }
            if let sku = controller.sku {
                MonoRow("SKU", sku.left ?? sku.right ?? "–")
                if let region = sku.regionCode { LabeledContent("Region code", value: region) }
            }
            if let color = controller.status?.colorLeft {
                LabeledContent("Colour", value: "\(color.name ?? "Unknown") (\(color.id))")
            }
            if let serials = controller.serials {
                MonoRow("Serial (left)", serials.left)
                MonoRow("Serial (right)", serials.right)
            }
            if let address = controller.selectedDevice?.address {
                MonoRow("Bluetooth address", address.uppercased().replacingOccurrences(of: "-", with: ":"))
            }
            if let data = controller.debugData {
                if let local = data.localAddress { MonoRow("Primary bud radio", local) }
                if let peer = data.peerAddress { MonoRow("Secondary bud radio", peer) }
            }
        }
    }

    @ViewBuilder
    private var firmware: some View {
        SwiftUI.Section("Firmware") {
            if let data = controller.debugData {
                MonoRow("Version", data.softwareVersion)
                LabeledContent("Hardware revision", value: data.hardwareVersion)
                MonoRow("Touch controller firmware", data.touchSoftwareVersion)
            }
            if let build = controller.buildInfo, !build.isEmpty {
                MonoRow("Build", build)
            }
            if let status = controller.status {
                LabeledContent("Status protocol revision") { Text(verbatim: "\(status.revision)") }
            }
            if let raw = controller.versionInfoRaw {
                MonoRow("Version info (raw)", raw.hexString)
            }
            if let cradle = controller.cradle {
                MonoRow("Case firmware", cradle.softwareVersion)
                MonoRow("Case serial", cradle.serialNumber)
            }
        }
        firmwareUpdates
    }

    @ViewBuilder
    private var firmwareUpdates: some View {
        if controller.model.supports(.firmwareUpdates) {
            SwiftUI.Section {
                if let transfer = controller.firmwareTransfer {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if transfer.isActive { ProgressView().controlSize(.small) }
                            Text(localizing: transfer.phase.label)
                            Spacer()
                            if transfer.isActive {
                                Button("Cancel") { controller.clearFirmwareTransfer() }
                            } else {
                                Button("Dismiss") { controller.clearFirmwareTransfer() }
                            }
                        }
                        if transfer.phase == .sending || transfer.phase == .flashing || transfer.phase == .done {
                            ProgressView(value: Double(transfer.percent), total: 100)
                            Text(verbatim: "\(transfer.percent)%").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    LabeledContent("Updates") {
                        HStack {
                            if controller.isCheckingFirmware { ProgressView().controlSize(.small) }
                            Button("Check for updates") { controller.checkForFirmware() }
                                .disabled(controller.isCheckingFirmware || !controller.isConnected)
                        }
                    }
                    if let status = controller.firmwareCheckStatus {
                        Text(verbatim: status).font(.callout).foregroundStyle(.secondary)
                    }
                    if let newer = controller.newerFirmware {
                        LabeledContent("Install \(newer.name)") {
                            Button("Install…") {
                                ui.pendingBuild = newer; ui.pendingImage = nil; ui.confirmInstall = true
                            }
                            .disabled(controller.firmwarePreflightProblem != nil)
                        }
                    }
                    LabeledContent("Install from a file") {
                        Button("Choose image…") { chooseImage() }
                            .disabled(controller.firmwarePreflightProblem != nil)
                    }
                    if let problem = controller.firmwarePreflightProblem, controller.isConnected {
                        Text(verbatim: problem).font(.caption).foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Firmware updates")
            } footer: {
                FormFooter(
                    "Images come from a community archive of Samsung's official builds and are checked against their own checksums and the model before anything is sent. Keep the earbuds and the Mac close together. The earbuds restart on their own when the transfer finishes."
                )
            }
            .confirmationDialog("Install this firmware?", isPresented: $ui.confirmInstall) {
                Button("Install") {
                    if let image = ui.pendingImage {
                        controller.installFirmware(image: image)
                    } else if let build = ui.pendingBuild {
                        controller.installFirmware(build)
                    }
                }
            } message: {
                Text(
                    "Both earbuds should have at least 30% battery and stay within a metre of the Mac. Do not close Mirinae or put the earbuds in the case until they have restarted. A failed update can leave the earbuds unusable."
                )
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a firmware image for \(controller.model.displayName)"
        guard panel.runModal() == .OK, let url = panel.url, let data = FileManager.default.contents(atPath: url.path)
        else { return }
        do {
            let image = try FirmwareImage([UInt8](data))
            guard image.model == controller.model else {
                controller.note("That image is for \(image.model?.displayName ?? "another model")")
                return
            }
            ui.pendingImage = image
            ui.pendingBuild = nil
            ui.confirmInstall = true
        } catch {
            controller.note("Could not read the firmware image: \(error)")
        }
    }

    @ViewBuilder
    private var battery: some View {
        if let d = controller.debugData {
            SwiftUI.Section {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow {
                        Text("").frame(width: 120)
                        Text("Left").bold()
                        Text("Right").bold()
                    }
                    GridRow {
                        Text("Charge"); Text(verbatim: "\(d.leftStateOfCharge)%");
                        Text(verbatim: "\(d.rightStateOfCharge)%")
                    }
                    GridRow {
                        Text("Cell voltage"); Text(volts(d.leftCellVoltage)); Text(volts(d.rightCellVoltage))
                    }
                    GridRow {
                        Text("Current"); Text(current(d.leftCurrent)); Text(current(d.rightCurrent))
                    }
                    GridRow {
                        Text("Temperature"); Text(temp(d.leftTemperature)); Text(temp(d.rightTemperature))
                    }
                    if let types = controller.batteryTypes {
                        GridRow {
                            Text("Cell type"); Text(types.left); Text(types.right)
                        }
                    }
                    if let cycles = controller.batteryCycles {
                        GridRow {
                            Text("Charge cycles"); Text(String(format: "%.1f", cycles.left));
                            Text(String(format: "%.1f", cycles.right))
                        }
                    } else if let usage = controller.usage {
                        let l = usage.entries.first { $0.key == "BSCL" }, r = usage.entries.first { $0.key == "BSCR" }
                        if let l, let r {
                            GridRow {
                                Text("Charge cycles"); Text(String(format: "%.2f", Double(l.value) / 100));
                                Text(String(format: "%.2f", Double(r.value) / 100))
                            }
                        }
                    }
                }
                .monospacedDigit()
            } header: {
                Text("Battery")
            } footer: {
                FormFooter(
                    "Negative current means the cell is discharging. Cycle counts come from the firmware's own counters."
                )
            }
        }
    }

    @ViewBuilder
    private var sensors: some View {
        if let d = controller.debugData {
            SwiftUI.Section("Raw sensor readings") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow {
                        Text("").frame(width: 120)
                        Text("Left").bold()
                        Text("Right").bold()
                    }
                    GridRow {
                        Text("Accelerometer"); Text(accel(d.leftAccelerometer)); Text(accel(d.rightAccelerometer))
                    }
                    GridRow {
                        Text("Proximity (offset)"); Text(verbatim: "\(d.leftProximity) (\(d.leftProximityOffset))");
                        Text(verbatim: "\(d.rightProximity) (\(d.rightProximityOffset))")
                    }
                    GridRow {
                        Text("Touch (absolute)"); Text(verbatim: "\(d.leftTouchAbsolute)");
                        Text(verbatim: "\(d.rightTouchAbsolute)")
                    }
                    GridRow {
                        Text("Hall sensor"); Text(String(format: "0x%02X", d.leftHall));
                        Text(String(format: "0x%02X", d.rightHall))
                    }
                    GridRow {
                        Text("In cradle"); Text(d.leftInCradle == 0 ? "No" : "Yes");
                        Text(d.rightInCradle == 0 ? "No" : "Yes")
                    }
                }
                .monospacedDigit()
            }
            if let usage = controller.usage, !usage.entries.isEmpty {
                SwiftUI.Section {
                    DisclosureGroup("Usage counters (\(usage.entries.count))", isExpanded: $ui.showUsage) {
                        ForEach(usage.entries) { entry in
                            LabeledContent(LocalizedStringKey(entry.label)) { Text(verbatim: "\(entry.value)") }
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    FormFooter("Raw counters the firmware reports when it connects. Durations are in seconds.")
                }
            }
        }
    }

    private var tests: some View {
        SwiftUI.Section("Tests") {
            if controller.model.supports(.gearFitTest) {
                LabeledContent("Earbud fit") {
                    HStack {
                        if let fit = controller.fitResult {
                            Text("Left: \(fit.left.description), right: \(fit.right.description)")
                        } else if controller.fitTestRunning {
                            ProgressView().controlSize(.small)
                            Text("Testing, keep both buds in and stay quiet…")
                        }
                        if controller.fitTestRunning {
                            Button("Cancel") { controller.cancelFitTest() }
                        } else {
                            Button("Run fit test") { controller.runFitTest() }
                        }
                    }
                }
            }
            LabeledContent("Hardware self test") {
                HStack {
                    if let result = controller.selfTest {
                        Text(
                            result.allPassed
                                ? "All checks passed" : "\(result.results.filter { !$0.passed }.count) checks failed"
                        )
                        .foregroundStyle(result.allPassed ? .green : .red)
                    }
                    Button("Run self test") { controller.runSelfTest() }
                }
            }
            if let result = controller.selfTest, !result.allPassed {
                ForEach(result.results.filter { !$0.passed }, id: \.name) { item in
                    Label(item.name, systemImage: "xmark.circle").foregroundStyle(.red).padding(.leading, 16)
                }
            }
        }
        .disabled(!controller.isConnected)
    }

    private var danger: some View {
        SwiftUI.Section {
            LabeledContent("Factory reset") {
                Button("Reset earbuds…", role: .destructive) { ui.confirmReset = true }
                    .disabled(!controller.isConnected)
            }
            .confirmationDialog("Reset the earbuds to factory settings?", isPresented: $ui.confirmReset) {
                Button("Reset", role: .destructive) { controller.factoryReset() }
            } message: {
                Text("All settings and pairings on the earbuds are erased. You will have to pair them again.")
            }
        } footer: {
            FormFooter("Same as the reset in Samsung's app. Nothing is sent until you confirm.")
        }
    }

    private func volts(_ v: Double) -> String { String(format: "%.2f V", v) }
    private func current(_ v: Double) -> String { String(format: "%.1f mA", v) }
    private func temp(_ v: Double) -> String { String(format: "%.1f °C", v) }
    private func accel(_ a: (x: Int16, y: Int16, z: Int16)) -> String { "\(a.x), \(a.y), \(a.z)" }
}
