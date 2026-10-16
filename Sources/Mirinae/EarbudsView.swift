// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import BudsProtocol

struct EarbudsView: View {
    @EnvironmentObject private var controller: BudsController
    @StateObject private var ui = UIState()

    final class UIState: ObservableObject {
        @Published var confirmPairing = false
        @Published var showRename = false
        @Published var newName = ""
    }

    private static let bixbyLanguages = [
        "German", "English (UK)", "English (US)", "Spanish", "French", "Italian", "Korean",
        "Portuguese (Brazil)", "Chinese", "Hungarian",
    ]

    var body: some View {
        if let s = controller.status {
            Form {
                SwiftUI.Section("Connection") {
                    if model.supports(.rename) {
                        LabeledContent("Name") {
                            HStack {
                                Text(verbatim: controller.deviceName)
                                Button("Rename…") {
                                    ui.newName = controller.personalName ?? controller.deviceName
                                    ui.showRename = true
                                }
                                .disabled(controller.isRenaming)
                            }
                        }
                        .sheet(isPresented: $ui.showRename) { RenameSheet(name: $ui.newName) }
                        if let stored = controller.personalName, stored != controller.deviceName {
                            LabeledContent("Name stored on the earbuds") {
                                Text(verbatim: stored)
                            }
                        }
                    }
                    if model.supports(.seamlessConnection, revision: s.revision), let seamless = s.seamlessConnection {
                        Toggle(
                            "Seamless earbud connection",
                            isOn: Binding(get: { seamless }, set: controller.setSeamlessConnection))
                    }
                    LabeledContent("Primary earbud") {
                        HStack {
                            Text(s.basic.mainIsLeft ? "Left" : "Right")
                            Button("Switch") { controller.switchMainBud() }
                                .help("Hand the Bluetooth link to the other bud")
                        }
                    }
                    FormFooter(
                        "One bud holds the Bluetooth link and relays audio to the other. The earbuds swap that role on their own to balance battery. Switch by hand before a long call if one side is low, or if the side nearer your Mac keeps dropping out."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    if model.supports(.pairingMode) || model >= .buds2 {
                        LabeledContent("Pair another device") {
                            Button("Enter pairing mode") { ui.confirmPairing = true }
                        }
                        .confirmationDialog("Put the earbuds into pairing mode?", isPresented: $ui.confirmPairing) {
                            Button("Enter pairing mode") { controller.enterPairingMode() }
                        } message: {
                            Text(
                                "They will start advertising so a phone or another computer can pair. The connection to this Mac may drop until you reconnect."
                            )
                        }
                    }
                }

                if model.supports(.bixbyWakeup), let wake = s.voiceWakeUp {
                    SwiftUI.Section {
                        Toggle(
                            "Voice wake-up (\"Hi, Bixby\")",
                            isOn: Binding(get: { wake }, set: controller.setVoiceWakeUp))
                        if let language = s.voiceWakeUpLanguage {
                            Picker(
                                "Language",
                                selection: Binding(get: { language }, set: controller.setVoiceWakeUpLanguage)
                            ) {
                                ForEach(Array(Self.bixbyLanguages.enumerated()), id: \.offset) { index, name in
                                    Text(name).tag(index)
                                }
                                if language >= Self.bixbyLanguages.count { Text("Code \(language)").tag(language) }
                            }
                            .disabled(!wake)
                        }
                    } header: {
                        Text("Voice assistant")
                    } footer: {
                        FormFooter(
                            "Bixby itself lives on a Samsung phone. This only controls whether the earbuds listen for the wake word."
                        )
                    }
                }

                SwiftUI.Section("State") {
                    LabeledContent("Left bud") {
                        Text(localizing: describe(s.basic.placementLeft, charging: s.basic.isLeftCharging))
                    }
                    LabeledContent("Right bud") {
                        Text(localizing: describe(s.basic.placementRight, charging: s.basic.isRightCharging))
                    }
                    LabeledContent(
                        "Case",
                        value: s.basic.isCaseCharging
                            ? "Charging"
                            : (s.basic.batteryCase.map { $0 > 0 ? "\($0)%" : "Not reporting" } ?? "Unknown"))
                    LabeledContent("Buds coupled", value: s.basic.isCoupled ? "Yes" : "No")
                    if let fmm = s.fmmRevision {
                        LabeledContent("SmartThings Find revision") { Text(verbatim: "\(fmm)") }
                    }
                    if !s.unparsedTail.isEmpty {
                        MonoRow("Undocumented trailing bytes", s.unparsedTail.hexString)
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var model: BudsModel { controller.model }

    private func describe(_ placement: Placement, charging: Bool) -> String {
        charging ? "\(placement.description), charging" : placement.description
    }
}

struct RenameSheet: View {
    @EnvironmentObject private var controller: BudsController
    @Environment(\.dismiss) private var dismiss
    @Binding var name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename earbuds").font(.title3.weight(.semibold))
            if controller.renameSucceeded {
                Label(
                    "The earbuds now call themselves \(controller.personalName ?? name).",
                    systemImage: "checkmark.circle"
                )
                .fixedSize(horizontal: false, vertical: true)
                Text(
                    "Every paired device, this Mac included, keeps showing the name it learned when it paired. To see the new one here, remove the earbuds in System Settings → Bluetooth and pair them again. Mirinae shows the stored name on the Earbuds page in the meantime."
                )
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Done") {
                        controller.clearRenameStatus(); dismiss()
                    }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            } else {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                Text(
                    "The name is stored on the earbuds. Devices that are already paired, this Mac included, keep showing the old name until you pair them again."
                )
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let status = controller.renameStatus {
                    HStack(spacing: 6) {
                        if controller.isRenaming { ProgressView().controlSize(.small) }
                        Text(localizing: status).font(.callout).foregroundStyle(
                            controller.isRenaming ? Color.secondary : Color.red)
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") {
                        controller.cancelRename(); dismiss()
                    }.keyboardShortcut(.cancelAction)
                    Button("Rename") { controller.rename(to: name.trimmingCharacters(in: .whitespaces)) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.isRenaming || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

struct FindView: View {
    @EnvironmentObject private var controller: BudsController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var ui = UIState()

    final class UIState: ObservableObject {
        @Published var confirmWhileWorn = false
    }

    private var aBudIsWorn: Bool {
        guard let s = controller.status else { return false }
        return s.basic.placementLeft == .wearing || s.basic.placementRight == .wearing
    }

    var body: some View {
        Form {
            SwiftUI.Section {
                HStack {
                    Image(systemName: controller.isFinding ? "speaker.wave.3.fill" : "speaker.slash")
                        .font(.largeTitle)
                        .foregroundStyle(controller.isFinding ? .orange : .secondary)
                        .symbolEffect(.variableColor.iterative, isActive: controller.isFinding && !reduceMotion)
                        .frame(width: 56)
                    VStack(alignment: .leading) {
                        Text(controller.isFinding ? "Beeping…" : "Play a loud beep on both earbuds")
                            .font(.headline)
                        Text(
                            controller.isFinding
                                ? "Press Stop when you have them."
                                : "The beep is loud. Take the earbuds out of your ears before you start. Works while they are connected to this Mac, even inside the case."
                        )
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if controller.isFinding {
                        Button("Stop", role: .destructive) { controller.stopFinding() }
                    } else {
                        Button("Start beeping") {
                            if aBudIsWorn { ui.confirmWhileWorn = true } else { controller.startFinding() }
                        }
                        .buttonStyle(.borderedProminent)
                        .confirmationDialog("A bud is in your ear", isPresented: $ui.confirmWhileWorn) {
                            Button("Beep anyway") { controller.startFinding() }
                        } message: {
                            Text(
                                "The earbuds report that at least one bud is being worn. Take them out first, or beep anyway at your own risk."
                            )
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            if controller.isFinding {
                SwiftUI.Section("Mute while searching") {
                    Toggle(
                        "Mute left", isOn: Binding(get: { controller.mutedLeft }, set: { controller.setMute(left: $0) })
                    )
                    Toggle(
                        "Mute right",
                        isOn: Binding(get: { controller.mutedRight }, set: { controller.setMute(right: $0) }))
                }
            }
        }
        .formStyle(.grouped)
    }
}
