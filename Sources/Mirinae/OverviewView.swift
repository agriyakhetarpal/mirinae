// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import BudsProtocol

struct OverviewView: View {
    @EnvironmentObject private var controller: BudsController
    @StateObject private var ui = UIState()

    final class UIState: ObservableObject {
        @Published var showRename = false
        @Published var newName = ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let s = controller.status {
                    HStack(spacing: 14) {
                        BatteryCard(
                            title: "Left", level: s.basic.batteryLeft, charging: s.basic.isLeftCharging,
                            placement: s.basic.placementLeft, systemImage: "l.circle")
                        BatteryCard(
                            title: "Right", level: s.basic.batteryRight, charging: s.basic.isRightCharging,
                            placement: s.basic.placementRight, systemImage: "r.circle")
                        if controller.model.supports(.caseBattery) {
                            BatteryCard(
                                title: "Case", level: caseLevel(s), charging: s.basic.isCaseCharging,
                                placement: nil, systemImage: "earbuds.case", note: caseNote(s),
                                stale: caseLevel(s) == nil && controller.lastKnownCase != nil)
                        }
                    }
                    quickControls(s)
                    GroupBox {
                        NowPlayingCard().padding(6)
                    } label: {
                        Text("Now playing")
                    }
                } else {
                    ProgressView("Waiting for the first status report…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                }
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: controller.deviceName).font(.largeTitle.weight(.semibold))
                    if controller.model.supports(.rename) {
                        Button {
                            ui.newName = controller.personalName ?? controller.deviceName
                            ui.showRename = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Rename the earbuds")
                        .accessibilityLabel("Rename the earbuds")
                        .disabled(!controller.isConnected || controller.isRenaming)
                        .sheet(isPresented: $ui.showRename) { RenameSheet(name: $ui.newName) }
                    }
                }
                HStack(spacing: 14) {
                    Text(verbatim: controller.model.displayName)
                    if let color = controller.status?.colorLeft?.name {
                        Text(localizing: color)
                    }
                    if let fw = controller.debugData?.softwareVersion {
                        Text(verbatim: fw).monospaced()
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let s = controller.status {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(s.basic.mainIsLeft ? "Primary bud: left" : "Primary bud: right")
                    if let date = controller.lastUpdate {
                        Text("Updated \(date, style: .relative) ago")
                    }
                    Button {
                        controller.refreshStatus()
                    } label: {
                        if controller.isRefreshing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .controlSize(.small)
                    .disabled(controller.isRefreshing)
                    .help("Reopens the control channel so the earbuds resend their full status. ⌘R")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func caseLevel(_ s: ExtendedStatus) -> Int? {
        if let level = s.basic.batteryCase, level > 0 { return level }
        return controller.lastKnownCase?.level
    }

    private func caseNote(_ s: ExtendedStatus) -> LocalizedStringKey? {
        if let level = s.basic.batteryCase, level > 0 { return nil }
        if let last = controller.lastKnownCase {
            let ago = RelativeDateTimeFormatter().localizedString(for: last.date, relativeTo: Date())
            return "Last seen \(ago)"
        }
        return "Not reporting"
    }

    @ViewBuilder
    private func quickControls(_ s: ExtendedStatus) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if controller.model.supports(.noiseControl), let mode = s.noiseControlMode {
                    LabeledContent("Noise controls") {
                        Picker("Noise controls", selection: Binding(get: { mode }, set: controller.setNoiseControl)) {
                            ForEach(availableModes) { m in Text(localizing: m.displayName).tag(m) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 360)
                    }
                }
                LabeledContent("Equaliser") {
                    Picker(
                        "Equaliser",
                        selection: Binding(get: { s.equalizerPreset ?? .normal }, set: controller.setEqualizer)
                    ) {
                        ForEach(EqualizerPreset.allCases) { p in Text(localizing: p.displayName).tag(p) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                LabeledContent("Touch controls") {
                    Toggle(
                        "Touch controls",
                        isOn: Binding(get: { !s.touchpadLocked }, set: { controller.setTouchLock(lockAll: !$0) })
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                if controller.model.supports(.ambientSoundVolume), s.noiseControlMode == .ambientSound,
                    let volume = s.ambientSoundVolume
                {
                    LabeledContent("Ambient volume") {
                        let maximum = controller.model.maximumAmbientVolume + (s.extraHighAmbient == true ? 1 : 0)
                        SteppedSlider(
                            value: Binding(get: { min(volume, maximum) }, set: { controller.setAmbientVolume($0) }),
                            labels: SteppedSlider.ambientLabels(
                                stops: maximum + 1, extraHigh: s.extraHighAmbient == true)
                        )
                        .frame(maxWidth: 280)
                    }
                }
            }
            .padding(6)
        } label: {
            Text("Quick controls")
        }
    }

    private var availableModes: [NoiseControlMode] {
        var modes: [NoiseControlMode] = [.off, .noiseCancelling, .ambientSound]
        if controller.model.supports(.noiseControlAdaptive) { modes.append(.adaptive) }
        return modes
    }
}
