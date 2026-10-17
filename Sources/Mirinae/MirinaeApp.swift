// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import AppKit
import ServiceManagement

struct MirinaeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = BudsController.shared
    @StateObject private var media = NowPlayingMonitor.shared

    var body: some Scene {
        Window("Mirinae", id: "main") {
            MainView()
                .environmentObject(controller)
                .environmentObject(media)
                .frame(minWidth: 760, minHeight: 540)
        }
        .defaultSize(width: 920, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button("Mirinae Help") { Help.open("README.md") }
                Button("Custom touch-and-hold actions") { Help.open("docs/custom-actions.md") }
                Button("Protocol notes") { Help.open("docs/protocol.md") }
                Divider()
                Button("Report a problem…") { Help.reportProblem() }
            }
            CommandMenu("Earbuds") {
                Button("Connect") { controller.connect() }.keyboardShortcut("k")
                    .disabled(controller.isConnected)
                Button("Disconnect from Mac") { controller.disconnectBluetooth() }
                    .disabled(!controller.isConnected)
                Divider()
                Button("Refresh status") { controller.refreshStatus() }.keyboardShortcut("r")
                    .disabled(!controller.isConnected)
                Button("Refresh diagnostics") { controller.refreshDiagnostics() }.keyboardShortcut(
                    "r", modifiers: [.command, .shift]
                )
                .disabled(!controller.isConnected)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(controller)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        Self.applyActivationPolicy()
        if let style = ProcessInfo.processInfo.environment["MIRINAE_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: style == "dark" ? .darkAqua : .aqua)
        }
        statusItem = StatusItemController(controller: BudsController.shared, media: NowPlayingMonitor.shared)
        statusItem?.showIfRequested()
        runDebugAction()
        refreshWatcherRegistration()
    }

    func applicationWillTerminate(_ notification: Notification) {
        BudsController.shared.shutDown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppActions.showMainWindow() }
        return true
    }

    private func refreshWatcherRegistration() {
        WatcherAgent.repairIfNeeded()
    }

    private func runDebugAction() {
        guard let action = ProcessInfo.processInfo.environment["MIRINAE_DEBUG_ACTION"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            switch action {
            case "settings": AppActions.showSettings()
            case "window": AppActions.showMainWindow()
            case "bt-off": BudsController.shared.disconnectBluetooth()
            case "about": NSApp.activate(ignoringOtherApps: true); NSApp.orderFrontStandardAboutPanel(nil)
            case "help": Help.open("README.md")
            case "rename-same": BudsController.shared.rename(to: BudsController.shared.deviceName)
            case "fw-check": BudsController.shared.checkForFirmware()
            case "fw-dry": BudsController.shared.firmwareDryRun()
            case "connect": BudsController.shared.connect()
            case "watcher-on", "watcher-off":
                do {
                    if action == "watcher-on" { try WatcherAgent.enable() } else { try WatcherAgent.disable() }
                    NSLog("Mirinae: watcher agent enabled=%d", WatcherAgent.isEnabled ? 1 : 0)
                } catch {
                    NSLog("Mirinae: watcher agent error %@", error.localizedDescription)
                }
            default: break
            }
        }
    }

    static func applyActivationPolicy() {
        let hide = UserDefaults.standard.bool(forKey: Preferences.hideDockIcon)
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
    }

    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "Mirinae" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

enum Help {
    static let repository = URL(string: "https://github.com/agriyakhetarpal/mirinae")!

    /// Opens a bundled document with whatever the Mac uses for Markdown.
    static func open(_ relativePath: String) {
        if let local = Bundle.main.resourceURL?.appendingPathComponent("Help/\(relativePath)"),
            FileManager.default.fileExists(atPath: local.path)
        {
            NSWorkspace.shared.open(local)
        } else {
            NSWorkspace.shared.open(repository.appendingPathComponent("blob/main/\(relativePath)"))
        }
    }

    static func reportProblem() {
        NSWorkspace.shared.open(repository.appendingPathComponent("issues"))
    }
}
