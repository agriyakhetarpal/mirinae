// SPDX-License-Identifier: Apache-2.0
import AppKit
import Combine
import SwiftUI
import BudsProtocol

@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    init(controller: BudsController, media: NowPlayingMonitor) {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(
            rootView: MenuPanelView().environmentObject(controller).environmentObject(media)
        )
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "Mirinae")
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(toggle)
        }
        controller.$status.combineLatest(controller.$state)
            .receive(on: RunLoop.main)
            .sink { [weak self] status, state in
                guard let self, let button = self.item.button else { return }
                if state == .connected, let s = status {
                    button.title = " \(min(s.basic.batteryLeft, s.basic.batteryRight))%"
                } else {
                    button.title = ""
                }
            }
            .store(in: &cancellables)
    }

    func showIfRequested() {
        guard ProcessInfo.processInfo.environment["MIRINAE_SHOW_PANEL"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.toggle() }
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

struct MenuPanelView: View {
    @EnvironmentObject private var controller: BudsController
    @EnvironmentObject private var media: NowPlayingMonitor
    var body: some View {
        VStack(spacing: 14) {
            header
            if controller.isConnected, let s = controller.status {
                PanelCard("Earbuds") {
                    HStack(spacing: 10) {
                        BatteryTile(
                            label: "Left", level: s.basic.batteryLeft, charging: s.basic.isLeftCharging,
                            worn: s.basic.placementLeft == .wearing)
                        BatteryTile(
                            label: "Right", level: s.basic.batteryRight, charging: s.basic.isRightCharging,
                            worn: s.basic.placementRight == .wearing)
                        if controller.model.supports(.caseBattery) {
                            BatteryTile(
                                label: "Case",
                                level: (s.basic.batteryCase ?? 0) > 0
                                    ? s.basic.batteryCase : controller.lastKnownCase?.level,
                                charging: s.basic.isCaseCharging, worn: false, isCase: true)
                        }
                    }
                }
                if controller.model.supports(.noiseControl), let mode = s.noiseControlMode {
                    PanelCard("Noise controls") {
                        PillPicker(selection: Binding(get: { mode }, set: controller.setNoiseControl), options: modes) {
                            $0.displayName
                        }
                    }
                }
                PanelCard("Sound") {
                    VStack(spacing: 0) {
                        PanelRow("Equaliser") {
                            Picker(
                                "",
                                selection: Binding(get: { s.equalizerPreset ?? .normal }, set: controller.setEqualizer)
                            ) {
                                ForEach(EqualizerPreset.allCases) { Text(localizing: $0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        Divider().padding(.vertical, 6)
                        PanelRow("Touch controls") {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { !s.touchpadLocked }, set: { controller.setTouchLock(lockAll: !$0) })
                            )
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                        }
                        Divider().padding(.vertical, 6)
                        PanelRow("Find my earbuds") {
                            Button(controller.isFinding ? "Stop" : "Beep") {
                                controller.isFinding ? controller.stopFinding() : controller.startFinding()
                            }
                            .controlSize(.small)
                            .tint(controller.isFinding ? .orange : nil)
                        }
                    }
                }
            } else if controller.state == .connecting {
                PanelCard("Earbuds") {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Connecting…").foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { controller.cancelConnect() }.controlSize(.small)
                    }
                }
            } else if case .failed(let reason) = controller.state {
                PanelCard("Earbuds") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localizing: reason).font(.callout).foregroundStyle(.secondary).fixedSize(
                            horizontal: false, vertical: true)
                        Button("Try again") { controller.connect() }.controlSize(.small)
                    }
                }
            } else {
                PanelCard("Earbuds") {
                    HStack {
                        Text(controller.selectedDevice == nil ? "No paired Galaxy Buds" : "Not connected")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Connect") { controller.connect() }.controlSize(.small).disabled(
                            controller.selectedDevice == nil)
                    }
                }
            }
            if media.track != nil || media.permissionDenied {
                PanelCard("Now playing") { NowPlayingCard(compact: true) }
            }
            footer
        }
        .padding(16)
        .frame(width: 340)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .onAppear { media.start() }
    }

    private var modes: [NoiseControlMode] {
        var m: [NoiseControlMode] = [.off, .noiseCancelling, .ambientSound]
        if controller.model.supports(.noiseControlAdaptive) { m.append(.adaptive) }
        return m
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.22))
                Image(systemName: "earbuds").foregroundStyle(Color.accentColor)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.deviceName.isEmpty ? "Mirinae" : controller.deviceName).font(.headline).lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(localizing: controller.isConnected ? controller.model.displayName : controller.state.label)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if controller.isConnected {
                Button {
                    controller.disconnectBluetooth()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Disconnect from this Mac")
                .accessibilityLabel("Disconnect from this Mac")
            }
        }
    }

    private var statusColor: Color {
        switch controller.state {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .failed: return .red
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            PillButton("Open Mirinae", systemImage: "macwindow") { AppActions.showMainWindow() }
            PillButton(nil, systemImage: "gearshape") { AppActions.showSettings() }
                .frame(width: 46)
                .help("Settings")
                .accessibilityLabel("Settings")
            PillButton("Quit", systemImage: "power") { NSApp.terminate(nil) }
        }
    }
}

struct PanelCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .font(.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct PanelRow<Accessory: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let accessory: Accessory

    init(_ title: LocalizedStringKey, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            accessory
        }
    }
}

struct PillButton: View {
    let title: LocalizedStringKey?
    let systemImage: String
    let action: () -> Void

    init(_ title: LocalizedStringKey?, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let title {
                    Label(title, systemImage: systemImage)
                } else {
                    Image(systemName: systemImage)
                }
            }
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PillPicker<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String
    /// Labels come from the protocol library and are looked up in Localizable.strings.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    if reduceMotion {
                        selection = option
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) { selection = option }
                    }
                } label: {
                    Text(localizing: label(option))
                        .font(.callout.weight(selection == option ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            selection == option ? Color.accentColor.opacity(0.35) : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

struct BatteryTile: View {
    let label: LocalizedStringKey
    let level: Int?
    let charging: Bool
    let worn: Bool
    var isCase = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: charging ? "bolt.fill" : (isCase ? "earbuds.case" : (worn ? "ear" : "earbuds")))
                    .font(.caption)
                    .foregroundStyle(charging ? .yellow : .secondary)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Text(verbatim: level.map { "\($0)%" } ?? "–")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            Gauge(value: Double(level ?? 0), in: 0...100) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .tint(tint)
                .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label) + Text(" ") + Text("battery"))
        .accessibilityValue(level.map { "\($0) percent" } ?? "not reporting")
    }

    private var tint: Color {
        guard let level else { return .gray }
        return level <= 15 ? .red : (level <= 30 ? .orange : .green)
    }
}
