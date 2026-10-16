// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import BudsProtocol

extension Text {
    /// Looks a runtime string up in Localizable.strings, for enum labels that come from the protocol library.
    init(localizing string: String) {
        self.init(LocalizedStringKey(string))
    }
}

struct BatteryCard: View {
    let title: LocalizedStringKey
    let level: Int?
    let charging: Bool
    let placement: Placement?
    let systemImage: String
    var note: LocalizedStringKey? = nil
    var stale = false

    var body: some View {
        VStack(spacing: 10) {
            Gauge(value: Double(level ?? 0), in: 0...100) {
                Image(systemName: systemImage)
            } currentValueLabel: {
                Text(verbatim: level.map { "\($0)" } ?? "–")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(tint)
            .scaleEffect(1.25)
            .frame(height: 70)
            .opacity(stale ? 0.45 : 1)

            Text(title).font(.headline)
            HStack(spacing: 4) {
                if charging { Image(systemName: "bolt.fill").foregroundStyle(.yellow) }
                if let note, !charging {
                    Text(note).foregroundStyle(.secondary)
                } else {
                    Text(localizing: subtitle).foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title) + Text(" ") + Text("battery"))
        .accessibilityValue(level.map { "\($0) percent, \(subtitle)" } ?? subtitle)
    }

    private var subtitle: String {
        if charging { return "Charging" }
        if let placement { return placement.description }
        return level == nil ? "Unknown" : ""
    }

    private var tint: Color {
        guard let level else { return .gray }
        if level <= 15 { return .red }
        if level <= 30 { return .orange }
        return .green
    }
}

struct StatusDot: View {
    let state: BudsController.ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(localizing: state.label).foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var color: Color {
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .failed: return .red
        }
    }
}

struct NotConnectedView: View {
    @EnvironmentObject private var controller: BudsController

    var body: some View {
        switch controller.state {
        case .connecting:
            ContentUnavailableView {
                Label {
                    Text("Connecting to \(controller.deviceName)…")
                } icon: {
                    ProgressView().controlSize(.large)
                }
            } description: {
                Text("Bringing up the Bluetooth link and the control channel.")
            } actions: {
                Button("Cancel") { controller.cancelConnect() }
            }
        case .failed(let reason):
            ContentUnavailableView {
                Label("Could not connect", systemImage: "exclamationmark.triangle")
            } description: {
                Text(reason)
            } actions: {
                Button("Try again") { controller.connect() }
                    .buttonStyle(.borderedProminent)
                Button("Rescan") { controller.refreshDevices() }
            }
        default:
            ContentUnavailableView {
                Label("Earbuds not connected", systemImage: "earbuds")
            } description: {
                Text(
                    controller.selectedDevice == nil
                        ? "Pair your Galaxy Buds with this Mac in System Settings first, then come back here."
                        : "Take the earbuds out of the case and press Connect. Mirinae brings up the Bluetooth link and the control channel."
                )
            } actions: {
                Button("Connect") { controller.connect() }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.selectedDevice == nil)
                Button("Rescan") { controller.refreshDevices() }
            }
        }
    }
}

extension View {
    /// Greys out a section when the connected model does not support the feature.
    @ViewBuilder
    func available(_ supported: Bool) -> some View {
        if supported { self } else { EmptyView() }
    }
}

struct SideLabel: View {
    let side: Side
    var body: some View {
        Text(localizing: side.label).frame(width: 44, alignment: .leading).foregroundStyle(.secondary)
    }
}

struct MonoRow: View {
    let label: LocalizedStringKey
    let value: String

    init(_ label: LocalizedStringKey, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        LabeledContent(label) {
            Text(verbatim: value).font(.body.monospaced()).textSelection(.enabled)
        }
    }
}

/// Removes the title bar separator so the sidebar and detail columns share one continuous top edge.
struct WindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(nsView.window) }
    }

    private func apply(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
    }
}

/// Scene actions captured from the main window so the status item panel can use them.
@MainActor
enum AppActions {
    static var openWindow: OpenWindowAction?
    static var openSettings: OpenSettingsAction?

    static func showMainWindow() {
        openWindow?(id: "main")
        AppDelegate.showMainWindow()
    }

    static func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let openSettings {
            openSettings()
            return
        }
        let appMenu = NSApp.mainMenu?.items.first?.submenu
        if let item = appMenu?.items.first(where: { $0.keyEquivalent == "," }), let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
        }
    }
}

/// Grouped-form footers default to trailing alignment on macOS. Hints read better under the group.
struct FormFooter: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
    }
}

/// A slider that snaps to whole steps and names every stop underneath. The first and last
/// labels hug the edges so nothing is clipped, the others sit under their stop.
struct SteppedSlider: View {
    @Binding var value: Int
    let labels: [LocalizedStringKey]

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: 0...Double(max(labels.count - 1, 1)), step: 1)
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        let last = labels.count - 1
                        Text(label)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(index == value ? .primary : .secondary)
                            .frame(
                                width: Self.slotWidth(count: labels.count, width: geo.size.width),
                                alignment: index == 0 ? .leading : (index == last ? .trailing : .center)
                            )
                            .offset(x: Self.slotX(for: index, count: labels.count, width: geo.size.width))
                    }
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(labels[min(max(value, 0), labels.count - 1)]))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, labels.count - 1)
            case .decrement: value = max(value - 1, 0)
            @unknown default: break
            }
        }
    }

    /// Each label gets a slot as wide as the gap between stops, centred on its stop. The end
    /// slots are pulled inside the edges and aligned outward instead.
    private static func slotWidth(count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return width }
        return width / CGFloat(count - 1)
    }

    private static func slotX(for index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        let slot = slotWidth(count: count, width: width)
        let inset: CGFloat = 10
        let stop = inset + (width - 2 * inset) * CGFloat(index) / CGFloat(count - 1)
        if index == 0 { return 0 }
        if index == count - 1 { return width - slot }
        return stop - slot / 2
    }

    static func ambientLabels(stops: Int, extraHigh: Bool) -> [LocalizedStringKey] {
        switch (stops, extraHigh) {
        case (3, _): return ["Low", "Medium", "High"]
        case (4, true): return ["Low", "Medium", "High", "Extra high"]
        case (4, false): return ["Low", "Medium", "High", "Highest"]
        case (5, _): return ["Low", "Medium low", "Medium", "High", "Highest"]
        default: return (0..<stops).map { LocalizedStringKey(String($0 + 1)) }
        }
    }
}
