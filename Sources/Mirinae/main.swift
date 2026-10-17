// SPDX-License-Identifier: Apache-2.0
import Foundation

// Answered before AppKit starts, so it also works where there is no window server, such as
// Homebrew's test sandbox.
if CommandLine.arguments.contains("--version") {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    print("Mirinae \(version)")
    exit(0)
}

MirinaeApp.main()
