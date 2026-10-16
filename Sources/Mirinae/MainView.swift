// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import BudsProtocol

enum Section: String, CaseIterable, Identifiable {
    case overview, sound, touch, earbuds, find, device, sensors, console

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .sound: return "Sound"
        case .touch: return "Touch"
        case .earbuds: return "Earbuds"
        case .find: return "Find"
        case .device: return "Device"
        case .sensors: return "Sensors"
        case .console: return "Console"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "earbuds"
        case .sound: return "waveform"
        case .touch: return "hand.tap"
        case .earbuds: return "slider.horizontal.3"
        case .find: return "location.magnifyingglass"
        case .device: return "info.circle"
        case .sensors: return "gyroscope"
        case .console: return "terminal"
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var controller: BudsController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @StateObject private var ui = UIState()

    final class UIState: ObservableObject {
        @Published var section: Section? =
            ProcessInfo.processInfo.environment["MIRINAE_SECTION"].flatMap(Section.init(rawValue:)) ?? .overview
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $ui.section) { item in
                Label(LocalizedStringKey(item.title), systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    Group {
                        if controller.deviceName.isEmpty {
                            Text("No earbuds")
                        } else {
                            Text(verbatim: controller.deviceName)
                        }
                    }
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    StatusDot(state: controller.state)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        } detail: {
            Group {
                if controller.isConnected || ui.section == .console || ui.section == .device {
                    detail
                } else {
                    NotConnectedView()
                }
            }
            .navigationTitle(LocalizedStringKey(ui.section?.title ?? "Mirinae"))
            .toolbar { toolbar }
        }
        .background(WindowStyler())
        .onAppear {
            AppActions.openWindow = openWindow
            AppActions.openSettings = openSettings
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch ui.section ?? .overview {
        case .overview: OverviewView()
        case .sound: SoundView()
        case .touch: TouchView()
        case .earbuds: EarbudsView()
        case .find: FindView()
        case .device: DeviceView()
        case .sensors: SensorsView()
        case .console: ConsoleView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if controller.isConnected {
                Button {
                    controller.disconnectBluetooth()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .help("Disconnect the earbuds from this Mac")
            } else {
                Button {
                    controller.connect()
                } label: {
                    Label("Connect", systemImage: "link")
                }
                .disabled(controller.state == .connecting)
            }
        }
        if controller.devices.count > 1 {
            ToolbarItem {
                Picker("Earbuds", selection: $controller.selectedAddress) {
                    ForEach(controller.devices) { device in
                        Text(verbatim: device.name).tag(Optional(device.address))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}
