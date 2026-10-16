// swift-tools-version: 5.9
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "Mirinae",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BudsProtocol", targets: ["BudsProtocol"]),
        .executable(name: "Mirinae", targets: ["Mirinae"]),
    ],
    targets: [
        // Pure Swift. No Bluetooth, no UI. Frames, checksums, decoders, and command builders.
        .target(name: "BudsProtocol"),
        // The macOS app: IOBluetooth transport, state, SwiftUI windows, and the menu bar item.
        .executableTarget(
            name: "Mirinae",
            dependencies: ["BudsProtocol"],
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        // Launch agent that starts the app when the earbuds connect.
        .executableTarget(name: "MirinaeWatcher", linkerSettings: [.linkedFramework("IOBluetooth")]),
        .testTarget(name: "BudsProtocolTests", dependencies: ["BudsProtocol"]),
    ]
)
