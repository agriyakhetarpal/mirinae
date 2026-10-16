// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import BudsProtocol

/// Nine draggable bands. On models with a custom equaliser the gains go to the firmware as
/// they are. On everything else the curve snaps to the closest preset, because those
/// firmwares only accept a preset number.
struct EqualiserView: View {
    @EnvironmentObject private var controller: BudsController
    @StateObject private var ui = UIState()

    final class UIState: ObservableObject {
        @Published var gains: [Int] = Array(repeating: 0, count: 9)
        @Published var dragging = false
        @Published var synced = false
    }

    static let bandLabels = ["60", "150", "400", "1k", "2.4k", "6k", "10k", "14k", "18k"]

    private var supportsCustom: Bool {
        controller.model.supports(.customEqualizer, revision: controller.status?.revision)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker(
                    "Preset",
                    selection: Binding(get: { controller.status?.equalizerPreset ?? .normal }, set: applyPreset)
                ) {
                    ForEach(EqualizerPreset.allCases) { Text(localizing: $0.displayName).tag($0) }
                    if supportsCustom { Text("Custom").tag(EqualizerPreset.normal).hidden() }
                }
                .frame(maxWidth: 220)
                Spacer()
                if supportsCustom, controller.customEqualiserActive {
                    Label("Custom", systemImage: "slider.vertical.3").foregroundStyle(.tint)
                }
                Button("Flat") { setAll(0) }
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<9, id: \.self) { band in
                    BandSlider(value: binding(for: band), label: Self.bandLabels[band])
                }
            }
            .frame(height: 190)
            .padding(.horizontal, 4)

            Text(footer).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear(perform: syncFromDevice)
        .onChange(of: controller.status?.equalizerPreset) { syncFromDevice() }
    }

    private var footer: String {
        if supportsCustom {
            return "Each band is sent to the earbuds as you drag. -10 to +10 dB."
        }
        return
            "\(controller.model.displayName) only stores presets. Drag the bands and Mirinae picks the closest one. The curves are approximations, not Samsung's exact filters."
    }

    private func binding(for band: Int) -> Binding<Double> {
        Binding(
            get: { Double(ui.gains[band]) },
            set: { newValue in
                let v = Int(newValue.rounded())
                guard ui.gains[band] != v else { return }
                ui.gains[band] = v
                push()
            })
    }

    private func setAll(_ value: Int) {
        ui.gains = Array(repeating: value, count: 9)
        push()
    }

    private func applyPreset(_ preset: EqualizerPreset) {
        ui.gains = Self.presetCurves[preset] ?? Array(repeating: 0, count: 9)
        controller.setEqualizer(preset)
    }

    private func syncFromDevice() {
        guard !controller.customEqualiserActive, let preset = controller.status?.equalizerPreset else { return }
        ui.gains = Self.presetCurves[preset] ?? Array(repeating: 0, count: 9)
    }

    private func push() {
        if supportsCustom {
            controller.setCustomEqualiser(ui.gains)
        } else {
            let nearest = Self.presetCurves.min { lhs, rhs in distance(lhs.value) < distance(rhs.value) }!.key
            if controller.status?.equalizerPreset != nearest { controller.setEqualizer(nearest) }
        }
    }

    private func distance(_ curve: [Int]) -> Int {
        zip(curve, ui.gains).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
    }

    /// Rough shapes of Samsung's presets, used for display and for snapping.
    static let presetCurves: [EqualizerPreset: [Int]] = [
        .normal: [0, 0, 0, 0, 0, 0, 0, 0, 0],
        .bassBoost: [6, 5, 3, 1, 0, 0, 0, 0, 0],
        .soft: [2, 1, 0, -1, -2, -3, -3, -2, -2],
        .dynamic: [4, 3, 1, -1, 0, 1, 3, 4, 3],
        .clear: [-1, -1, 0, 0, 1, 2, 3, 3, 2],
        .trebleBoost: [0, 0, 0, 0, 1, 2, 4, 5, 6],
    ]
}

struct BandSlider: View {
    @Binding var value: Double
    let label: String

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height - 24
            let y = height / 2 - CGFloat(value) / 10 * (height / 2)
            VStack(spacing: 6) {
                ZStack {
                    Capsule().fill(.quaternary).frame(width: 6)
                    Rectangle().fill(.tertiary).frame(height: 1)
                    Capsule()
                        .fill(.tint)
                        .frame(width: 6, height: abs(y - height / 2))
                        .position(x: geo.size.width / 2, y: (y + height / 2) / 2)
                    Circle()
                        .fill(.tint)
                        .frame(width: 16, height: 16)
                        .shadow(radius: 1, y: 1)
                        .position(x: geo.size.width / 2, y: y)
                }
                .frame(height: height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        let clamped = min(max(drag.location.y, 0), height)
                        value = Double((height / 2 - clamped) / (height / 2) * 10).rounded()
                    })
                Text(verbatim: label).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: geo.size.width)
        }
        .frame(minWidth: 28)
        .help(Text(verbatim: "\(Int(value)) dB"))
    }
}
