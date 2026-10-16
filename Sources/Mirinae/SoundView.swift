// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import BudsProtocol

struct SoundView: View {
    @EnvironmentObject private var controller: BudsController

    var body: some View {
        if let s = controller.status {
            Form {
                noiseControls(s)
                ambient(s)
                equaliser(s)
                calls(s)
            }
            .formStyle(.grouped)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var model: BudsModel { controller.model }

    @ViewBuilder
    private func noiseControls(_ s: ExtendedStatus) -> some View {
        if model.supports(.noiseControl), let mode = s.noiseControlMode {
            SwiftUI.Section("Noise controls") {
                Picker("Mode", selection: Binding(get: { mode }, set: controller.setNoiseControl)) {
                    Text("Off").tag(NoiseControlMode.off)
                    Text("Noise cancelling").tag(NoiseControlMode.noiseCancelling)
                    Text("Ambient sound").tag(NoiseControlMode.ambientSound)
                    if model.supports(.noiseControlAdaptive) { Text("Adaptive").tag(NoiseControlMode.adaptive) }
                }
                .pickerStyle(.segmented)

                if model.supports(.noiseControlsWithOneEarbud, revision: s.revision),
                    let one = s.noiseControlsWithOneEarbud
                {
                    Toggle(
                        "Allow noise controls with one earbud",
                        isOn: Binding(get: { one }, set: controller.setNoiseControlsWithOneEarbud))
                }
                if model.supports(.ancNoiseReductionLevels), let level = s.noiseReductionLevel {
                    Toggle(
                        "High noise cancelling level",
                        isOn: Binding(
                            get: { level == 1 }, set: { controller.send(Commands.noiseReductionLevel(high: $0)) }))
                }
                if model.supports(.detectConversations), let detect = s.detectConversations {
                    Toggle(
                        "Voice detect (switch to ambient when you talk)",
                        isOn: Binding(get: { detect }, set: controller.setDetectConversations))
                }
            }
        }
    }

    @ViewBuilder
    private func ambient(_ s: ExtendedStatus) -> some View {
        if model.supports(.ambientSound) {
            SwiftUI.Section {
                if model.supports(.ambientSoundVolume), let volume = s.ambientSoundVolume {
                    let extra = s.extraHighAmbient == true
                    let maximum = model.maximumAmbientVolume + (extra ? 1 : 0)
                    LabeledContent("Volume") {
                        SteppedSlider(
                            value: Binding(get: { min(volume, maximum) }, set: { controller.setAmbientVolume($0) }),
                            labels: SteppedSlider.ambientLabels(stops: maximum + 1, extraHigh: extra)
                        )
                        .frame(maxWidth: 340)
                    }
                }
                if let extra = s.extraHighAmbient {
                    Toggle(
                        "Extra high ambient volume", isOn: Binding(get: { extra }, set: controller.setExtraHighAmbient))
                }
                if model.supports(.ambientCustomize, revision: s.revision), let custom = s.ambientCustomEnabled {
                    Toggle(
                        "Customise ambient sound",
                        isOn: Binding(get: { custom }, set: { controller.setCustomAmbient(enabled: $0) }))
                    if custom {
                        LabeledContent("Left volume") {
                            Slider(
                                value: Binding(
                                    get: { Double(s.ambientCustomVolumeLeft ?? 0) },
                                    set: { controller.setCustomAmbient(left: Int($0.rounded())) }),
                                in: 0...4, step: 1
                            ).frame(maxWidth: 320)
                        }
                        LabeledContent("Right volume") {
                            Slider(
                                value: Binding(
                                    get: { Double(s.ambientCustomVolumeRight ?? 0) },
                                    set: { controller.setCustomAmbient(right: Int($0.rounded())) }),
                                in: 0...4, step: 1
                            ).frame(maxWidth: 320)
                        }
                        LabeledContent("Tone") {
                            Slider(
                                value: Binding(
                                    get: { Double(s.ambientCustomTone ?? 2) },
                                    set: { controller.setCustomAmbient(tone: Int($0.rounded())) }),
                                in: 0...4, step: 1
                            ) {
                                EmptyView()
                            } minimumValueLabel: {
                                Text("Soft")
                            } maximumValueLabel: {
                                Text("Clear")
                            }
                            .frame(maxWidth: 320)
                        }
                    }
                }
            } header: {
                Text("Ambient sound")
            } footer: {
                if s.noiseControlMode != .ambientSound {
                    FormFooter("Ambient sound is not active right now. These settings apply the next time it is.")
                }
            }
        }
    }

    @ViewBuilder
    private func equaliser(_ s: ExtendedStatus) -> some View {
        SwiftUI.Section("Equaliser") {
            EqualiserView()
            if model.supports(.stereoPan, revision: s.revision), let balance = s.stereoBalance {
                LabeledContent("Left/right balance") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(balance) }, set: { controller.setStereoBalance(Int($0.rounded())) }),
                            in: 0...32, step: 1
                        ) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("L")
                        } maximumValueLabel: {
                            Text("R")
                        }
                        .frame(maxWidth: 320)
                        Button("Centre") { controller.setStereoBalance(16) }.disabled(balance == 16)
                    }
                }
            }
            if let sync = s.adjustSoundSync, model == .budsPlus || model == .budsLive {
                Toggle("Adjust sound sync", isOn: Binding(get: { sync }, set: controller.setAdjustSoundSync))
            }
        }
    }

    @ViewBuilder
    private func calls(_ s: ExtendedStatus) -> some View {
        SwiftUI.Section("Calls") {
            if model.supports(.ambientSidetone, revision: s.revision), let sidetone = s.sidetone {
                Toggle(
                    "Sidetone (hear your own voice during calls)",
                    isOn: Binding(get: { sidetone }, set: controller.setSidetone))
            }
            if model.supports(.callPathControl, revision: s.revision), let path = s.callPathControl {
                Toggle(
                    "Answer calls on the earbuds automatically",
                    isOn: Binding(get: { path }, set: controller.setCallPathControl))
            }
            if model.supports(.extraClearCallSound, revision: s.revision), let clear = s.extraClearCallSound {
                Toggle("Extra clear call sound", isOn: Binding(get: { clear }, set: controller.setExtraClearCallSound))
            }
            if let speak = s.speakSeamlessly, model.supports(.detectConversations) {
                Toggle("Speak seamlessly", isOn: Binding(get: { speak }, set: controller.setSpeakSeamlessly))
            }
        }
    }
}
