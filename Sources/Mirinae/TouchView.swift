// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import BudsProtocol

struct TouchView: View {
    @EnvironmentObject private var controller: BudsController
    @AppStorage(Preferences.customActionLeft) private var customLeft = ""
    @AppStorage(Preferences.customActionRight) private var customRight = ""
    @StateObject private var ui = UIState()

    final class UIState: ObservableObject {
        @Published var showCustomHelp = false
    }

    static let examples: [(LocalizedStringKey, String)] = [
        ("Play or pause Apple Music", "osascript -e 'tell application \"Music\" to playpause'"),
        ("Next track in Spotify", "osascript -e 'tell application \"Spotify\" to next track'"),
        ("Run a Shortcut", "shortcuts run \"Deep Focus\""),
        ("Take a screenshot", "screencapture -i ~/Desktop/shot.png"),
    ]

    var body: some View {
        if let s = controller.status {
            Form {
                lock(s)
                holdActions(s)
                cycles(s)
                extras(s)
            }
            .formStyle(.grouped)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var model: BudsModel { controller.model }

    @ViewBuilder
    private func lock(_ s: ExtendedStatus) -> some View {
        SwiftUI.Section {
            Toggle(
                "Touch controls",
                isOn: Binding(get: { !s.touchpadLocked }, set: { controller.setTouchLock(lockAll: !$0) }))
            if model.supports(.advancedTouchLock, revision: s.revision), s.touchpadLocked {
                Text("Gestures that stay enabled while locked").font(.subheadline).foregroundStyle(.secondary)
                gestureToggle("Single tap", s.singleTapEnabled) { controller.setTouchLock(singleTap: $0) }
                gestureToggle("Double tap", s.doubleTapEnabled) { controller.setTouchLock(doubleTap: $0) }
                gestureToggle("Triple tap", s.tripleTapEnabled) { controller.setTouchLock(tripleTap: $0) }
                gestureToggle("Touch and hold", s.touchHoldEnabled) { controller.setTouchLock(touchHold: $0) }
                if model.supports(.advancedTouchLockForCalls, revision: s.revision) {
                    gestureToggle("Double tap during calls", s.doubleTapForCallEnabled) {
                        controller.setTouchLock(doubleTapForCalls: $0)
                    }
                    gestureToggle("Touch and hold during calls", s.touchHoldForCallEnabled) {
                        controller.setTouchLock(touchHoldForCalls: $0)
                    }
                }
            }
        } header: {
            Text("Touchpad")
        } footer: {
            FormFooter("Single tap plays or pauses, double tap skips forward, triple tap skips back.")
        }
    }

    @ViewBuilder
    private func gestureToggle(_ title: String, _ value: Bool?, set: @escaping (Bool) -> Void) -> some View {
        if let value {
            Toggle(title, isOn: Binding(get: { value }, set: set)).padding(.leading, 16)
        }
    }

    @ViewBuilder
    private func holdActions(_ s: ExtendedStatus) -> some View {
        SwiftUI.Section {
            Picker(
                "Left",
                selection: Binding(
                    get: { s.touchActionLeft ?? .noiseControls }, set: { controller.setTouchActions(left: $0) })
            ) {
                ForEach(model.touchMap.choices(forLeft: true)) { Text(localizing: $0.displayName).tag($0) }
            }
            Picker(
                "Right",
                selection: Binding(
                    get: { s.touchActionRight ?? .noiseControls }, set: { controller.setTouchActions(right: $0) })
            ) {
                ForEach(model.touchMap.choices(forLeft: false)) { Text(localizing: $0.displayName).tag($0) }
            }
            if s.touchActionLeft == .otherLeft {
                LabeledContent("Left command") {
                    TextField(
                        "", text: $customLeft, prompt: Text("osascript -e 'tell application \"Music\" to playpause'")
                    ).font(.body.monospaced()).labelsHidden()
                }
            }
            if s.touchActionRight == .otherRight {
                LabeledContent("Right command") {
                    TextField("", text: $customRight, prompt: Text("shortcuts run \"Focus\"")).font(.body.monospaced())
                        .labelsHidden()
                }
            }
        } header: {
            HStack {
                Text("Touch and hold")
                Spacer()
                Button {
                    ui.showCustomHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("What is Custom for?")
                .accessibilityLabel("What is Custom for?")
                .popover(isPresented: $ui.showCustomHelp, arrowEdge: .bottom) { customHelp }
            }
        } footer: {
            FormFooter(
                "\"Custom\" hands the gesture to this Mac. Mirinae runs the command you enter here with zsh whenever you touch and hold that bud."
            )
        }
    }

    private var customHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom turns a bud into a button for your Mac").font(.headline)
            Text(
                "Samsung reserves this touch-and-hold option for their phone app. Set a side to Custom and the earbuds hand the gesture to Mirinae, which runs the command you enter. Anything you can type in Terminal works: a Shortcut, an AppleScript, a curl call to something you built."
            )
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            ForEach(Array(Self.examples.enumerated()), id: \.offset) { _, example in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(example.0).font(.callout)
                        Text(verbatim: example.1).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(
                            .enabled)
                    }
                    Spacer()
                    Button("Left") {
                        customLeft = example.1; controller.setTouchActions(left: .otherLeft)
                    }.controlSize(.small)
                    Button("Right") {
                        customRight = example.1; controller.setTouchActions(right: .otherRight)
                    }.controlSize(.small)
                }
            }
            Text("More ideas in docs/custom-actions.md.").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 440)
    }

    @ViewBuilder
    private func cycles(_ s: ExtendedStatus) -> some View {
        if model.supports(.noiseControl), let left = s.noiseControlCycleLeft {
            let dual = model.supports(.noiseControlModeDualSide, revision: s.revision)
            SwiftUI.Section {
                cyclePicker(dual ? "Left" : "Both", left) { controller.setNoiseControlCycle(left: $0) }
                    .disabled(s.touchActionLeft != .noiseControls && (!dual || s.touchActionRight != .noiseControls))
                if dual, let right = s.noiseControlCycleRight {
                    cyclePicker("Right", right) { controller.setNoiseControlCycle(right: $0) }
                        .disabled(s.touchActionRight != .noiseControls)
                }
            } header: {
                Text("Noise control cycle")
            } footer: {
                FormFooter(
                    "When touch and hold is set to \"Noise controls\", each hold moves to the next of these modes.")
            }
        }
    }

    private func cyclePicker(
        _ title: String, _ cycle: NoiseControlCycle, set: @escaping (NoiseControlCycle) -> Void
    ) -> some View {
        Picker(title, selection: Binding(get: { cycle }, set: set)) {
            Text("Noise cancelling ↔ Ambient").tag(NoiseControlCycle.ancAndAmbient)
            Text("Noise cancelling ↔ Off").tag(NoiseControlCycle.ancAndOff)
            Text("Ambient ↔ Off").tag(NoiseControlCycle.ambientAndOff)
            Text("All three").tag(NoiseControlCycle.all)
            if ![.ancAndAmbient, .ancAndOff, .ambientAndOff, .all].contains(cycle) {
                Text(localizing: cycle.displayName).tag(cycle)
            }
        }
    }

    @ViewBuilder
    private func extras(_ s: ExtendedStatus) -> some View {
        if model.supports(.doubleTapVolume, revision: s.revision), let edge = s.outsideDoubleTap {
            SwiftUI.Section {
                Toggle(
                    "Double tap the earbud edge to change volume",
                    isOn: Binding(get: { edge }, set: controller.setOutsideDoubleTap))
            } header: {
                Text("Labs")
            } footer: {
                FormFooter("Front edge turns the volume down, back edge turns it up.")
            }
        }
    }
}
