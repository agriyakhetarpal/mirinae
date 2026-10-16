// SPDX-License-Identifier: Apache-2.0
import AppKit
import IOBluetooth
import os

// Background helper. Waits for the chosen earbuds to connect and starts Mirinae if it is not running.
// Connect notifications are the fast path. A slow poll covers the case where they never arrive.

let appBundleID = "al.agriyakhetarp.mirinae"
let log = Logger(subsystem: "al.agriyakhetarp.mirinae", category: "watcher")

final class Watcher: NSObject {
    private var notification: IOBluetoothUserNotification?
    private var wasConnected = false
    private var lastLaunch = Date.distantPast

    func start() {
        notification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(connected(_:device:)))
        wasConnected = targetDevice()?.isConnected() ?? false
        log.notice(
            "watching for \(self.targetAddress() ?? "no device", privacy: .public), connected now: \(self.wasConnected)"
        )
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func targetAddress() -> String? {
        let defaults =
            Bundle.main.bundleIdentifier == appBundleID ? UserDefaults.standard : UserDefaults(suiteName: appBundleID)
        return defaults?.string(forKey: "selectedDevice")
    }

    private func targetDevice() -> IOBluetoothDevice? {
        targetAddress().flatMap { IOBluetoothDevice(addressString: $0) }
    }

    @objc private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        log.notice("connect event from \(device.addressString ?? "?", privacy: .public)")
        guard let wanted = targetAddress(), device.addressString?.lowercased() == wanted.lowercased() else { return }
        wasConnected = true
        launchIfNeeded(reason: "notification")
    }

    private func poll() {
        let connected = targetDevice()?.isConnected() ?? false
        if connected && !wasConnected {
            launchIfNeeded(reason: "poll")
        }
        wasConnected = connected
    }

    private func launchIfNeeded(reason: String) {
        guard Date().timeIntervalSince(lastLaunch) > 10 else { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID).isEmpty else {
            log.notice("earbuds connected (\(reason, privacy: .public)), Mirinae already running")
            return
        }
        lastLaunch = Date()
        let app = Bundle.main.executableURL!.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        log.notice("earbuds connected (\(reason, privacy: .public)), launching \(app.path, privacy: .public)")
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            if let error { log.error("launch failed: \(error.localizedDescription, privacy: .public)") }
        }
    }
}

let watcher = Watcher()
watcher.start()
RunLoop.main.run()
