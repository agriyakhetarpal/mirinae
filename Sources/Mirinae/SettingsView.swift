// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var controller: BudsController
    @AppStorage(Preferences.autoConnect) private var autoConnect = true
    @AppStorage(Preferences.hideDockIcon) private var hideDockIcon = false
    @AppStorage(Preferences.presentAsSamsung) private var presentAsSamsung = true
    @AppStorage(Preferences.autoRefreshInterval) private var autoRefreshInterval = 60.0
    @AppStorage(Preferences.customActionLeft) private var customLeft = ""
    @AppStorage(Preferences.customActionRight) private var customRight = ""
    @StateObject private var ui = UIState()

    final class UIState: ObservableObject {
        @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
        @Published var launchOnConnect = WatcherAgent.isEnabled
        @Published var loginError: String?
    }

    var body: some View {
        Form {
            SwiftUI.Section {
                Toggle("Connect automatically when the earbuds appear", isOn: $autoConnect)
                Picker("Refresh the status automatically", selection: $autoRefreshInterval) {
                    Text("Off").tag(0.0)
                    Text("Every 20 seconds").tag(20.0)
                    Text("Every minute").tag(60.0)
                    Text("Every 5 minutes").tag(300.0)
                }
                .onChange(of: autoRefreshInterval) { controller.startAutoRefresh() }
                Toggle("Hide the Dock icon (menu bar only)", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { AppDelegate.applyActivationPolicy() }
                Toggle("Launch at login", isOn: $ui.launchAtLogin)
                    .onChange(of: ui.launchAtLogin) { _, enabled in toggleLoginItem(enabled) }
                Toggle("Launch when the earbuds connect", isOn: $ui.launchOnConnect)
                    .onChange(of: ui.launchOnConnect) { _, enabled in toggleWatcher(enabled) }
                if let error = ui.loginError { Text(error).font(.caption).foregroundStyle(.red) }
            } header: {
                Text("General")
            } footer: {
                FormFooter(
                    "\"Launch when the earbuds connect\" installs a small background helper that waits for the earbuds and starts Mirinae. It appears under Login Items → Allow in the Background. Keep Mirinae in /Applications so the entry stays valid."
                )
            }
            SwiftUI.Section {
                Picker("Earbuds", selection: $controller.selectedAddress) {
                    ForEach(controller.devices) {
                        Text("\($0.name)  \($0.address.uppercased())").tag(Optional($0.address))
                    }
                }
                Button("Rescan paired devices") { controller.refreshDevices() }
            } header: {
                Text("Device")
            }
            SwiftUI.Section {
                Toggle("Present as a Samsung phone", isOn: $presentAsSamsung)
            } header: {
                Text("Protocol")
            } footer: {
                FormFooter(
                    "Samsung's app identifies itself on connect. Pretending to be a Galaxy phone makes the firmware expose every option. Takes effect on the next connection."
                )
            }
            SwiftUI.Section {
                LabeledContent("Left bud") {
                    TextField("", text: $customLeft, prompt: Text("shell command")).font(.body.monospaced())
                        .labelsHidden()
                }
                LabeledContent("Right bud") {
                    TextField("", text: $customRight, prompt: Text("shell command")).font(.body.monospaced())
                        .labelsHidden()
                }
            } header: {
                Text("Custom touch and hold commands")
            } footer: {
                FormFooter("Used when a bud's touch and hold action is set to \"Custom\" in the Touch section.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func toggleLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            ui.loginError = nil
        } catch {
            ui.loginError = error.localizedDescription
            ui.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func toggleWatcher(_ enabled: Bool) {
        do {
            if enabled { try WatcherAgent.enable() } else { try WatcherAgent.disable() }
            ui.loginError = nil
        } catch {
            ui.loginError = error.localizedDescription
            ui.launchOnConnect = WatcherAgent.isEnabled
        }
    }
}
