// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import BudsProtocol

struct SensorsView: View {
    @EnvironmentObject private var controller: BudsController

    var body: some View {
        VStack(spacing: 24) {
            if controller.model.supports(.spatialSensor, revision: controller.status?.revision) {
                headTracking
            } else {
                ContentUnavailableView(
                    "No head tracking sensor", systemImage: "gyroscope",
                    description: Text("\(controller.model.displayName) does not stream orientation data."))
            }
        }
        .padding(24)
        .onDisappear { controller.stopHeadTracking() }
    }

    private var headTracking: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Head tracking").font(.title2.weight(.semibold))
                    Text(
                        "The earbuds stream their orientation as a quaternion about 20 times a second. Samsung uses it for 360 audio."
                    )
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.headTrackingActive {
                    Button("Stop") { controller.stopHeadTracking() }
                } else {
                    Button("Start streaming") { controller.startHeadTracking() }.buttonStyle(.borderedProminent)
                }
            }

            HStack(alignment: .top, spacing: 32) {
                HeadIndicator(orientation: controller.orientation)
                    .frame(width: 220, height: 220)
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text(verbatim: "w").foregroundStyle(.secondary); Text(fmt(controller.orientation?.w))
                    }
                    GridRow {
                        Text(verbatim: "x").foregroundStyle(.secondary); Text(fmt(controller.orientation?.x))
                    }
                    GridRow {
                        Text(verbatim: "y").foregroundStyle(.secondary); Text(fmt(controller.orientation?.y))
                    }
                    GridRow {
                        Text(verbatim: "z").foregroundStyle(.secondary); Text(fmt(controller.orientation?.z))
                    }
                    Divider()
                    if let euler = controller.orientation.map(eulerAngles) {
                        GridRow {
                            Text("Yaw").foregroundStyle(.secondary); Text(deg(euler.yaw))
                        }
                        GridRow {
                            Text("Pitch").foregroundStyle(.secondary); Text(deg(euler.pitch))
                        }
                        GridRow {
                            Text("Roll").foregroundStyle(.secondary); Text(deg(euler.roll))
                        }
                    }
                    GridRow {
                        Text("Samples").foregroundStyle(.secondary); Text(verbatim: "\(controller.orientationSamples)")
                    }
                }
                .font(.body.monospacedDigit())
                Spacer()
            }
            Spacer()
        }
    }

    private func fmt(_ v: Float?) -> String { v.map { String(format: "%+.4f", $0) } ?? "–" }
    private func deg(_ v: Double) -> String { String(format: "%+.1f°", v * 180 / .pi) }

    private func eulerAngles(
        _ q: (w: Float, x: Float, y: Float, z: Float)
    ) -> (yaw: Double, pitch: Double, roll: Double) {
        let w = Double(q.w), x = Double(q.x), y = Double(q.y), z = Double(q.z)
        let roll = atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y))
        let pitch = asin(max(-1, min(1, 2 * (w * y - z * x))))
        let yaw = atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
        return (yaw, pitch, roll)
    }
}

struct HeadIndicator: View {
    let orientation: (w: Float, x: Float, y: Float, z: Float)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 2)
            Circle().stroke(.quaternary, lineWidth: 1).scaleEffect(0.5)
            Path { p in
                p.move(to: CGPoint(x: 110, y: 0)); p.addLine(to: CGPoint(x: 110, y: 220))
                p.move(to: CGPoint(x: 0, y: 110)); p.addLine(to: CGPoint(x: 220, y: 110))
            }
            .stroke(.quaternary, lineWidth: 1)
            if let o = orientation {
                let forward = rotate(x: 0, y: 0, z: -1, by: o)
                let dot = CGPoint(x: 110 + CGFloat(forward.x) * 100, y: 110 + CGFloat(forward.y) * 100)
                Circle()
                    .fill(.tint)
                    .frame(width: 18, height: 18)
                    .position(dot)
                    .animation(reduceMotion ? nil : .linear(duration: 0.05), value: dot)
                Image(systemName: "face.smiling")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .rotation3DEffect(.radians(Double(asin(max(-1, min(1, forward.y))))), axis: (x: 1, y: 0, z: 0))
                    .rotation3DEffect(.radians(Double(-asin(max(-1, min(1, forward.x))))), axis: (x: 0, y: 1, z: 0))
            } else {
                Text("Not streaming").foregroundStyle(.tertiary)
            }
        }
    }

    private func rotate(
        x: Float, y: Float, z: Float, by q: (w: Float, x: Float, y: Float, z: Float)
    ) -> (x: Float, y: Float, z: Float) {
        // v' = q v q*
        let (qw, qx, qy, qz) = (q.w, q.x, q.y, q.z)
        let tx = qw * x + qy * z - qz * y
        let ty = qw * y + qz * x - qx * z
        let tz = qw * z + qx * y - qy * x
        let tw = -qx * x - qy * y - qz * z
        return (
            tx * qw + tw * -qx + ty * -qz - tz * -qy,
            ty * qw + tw * -qy + tz * -qx - tx * -qz,
            tz * qw + tw * -qz + tx * -qy - ty * -qx
        )
    }
}
