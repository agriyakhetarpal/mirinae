// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Installs the connect watcher as a user launch agent. The modern SMAppService route needs a
/// Developer ID signature, which an ad hoc build does not have, so this writes the plist to
/// ~/Library/LaunchAgents and loads it with launchctl instead.
enum WatcherAgent {
    static let label = "al.agriyakhetarp.mirinae.watcher"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var helperPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/MirinaeWatcher").path
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func enable() throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [helperPath],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = launchctl(["bootout", domain, plistURL.path])
        try data.write(to: plistURL)
        let result = launchctl(["bootstrap", domain, plistURL.path])
        if result.status != 0 {
            throw NSError(
                domain: "Mirinae", code: Int(result.status),
                userInfo: [NSLocalizedDescriptionKey: "launchctl failed: \(result.output)"])
        }
    }

    static func disable() throws {
        _ = launchctl(["bootout", domain, plistURL.path])
        if isEnabled { try FileManager.default.removeItem(at: plistURL) }
    }

    /// Reloads the agent if the app has moved since it was installed.
    static func repairIfNeeded() {
        guard isEnabled,
            let plist = NSDictionary(contentsOf: plistURL),
            let arguments = plist["ProgramArguments"] as? [String]
        else { return }
        if arguments.first != helperPath { try? enable() }
    }

    private static var domain: String { "gui/\(getuid())" }

    private static func launchctl(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
