// SPDX-License-Identifier: Apache-2.0
import SwiftUI

struct NowPlayingCard: View {
    @EnvironmentObject private var media: NowPlayingMonitor
    var compact = false

    var body: some View {
        HStack(spacing: 14) {
            artworkView
            VStack(alignment: .leading, spacing: 3) {
                if let track = media.track {
                    Text(track.title).font(compact ? .callout.weight(.semibold) : .headline).lineLimit(1)
                    Text(track.artist).font(compact ? .caption : .subheadline).foregroundStyle(.secondary).lineLimit(1)
                    if !compact {
                        Text(track.album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    if track.duration > 0 {
                        TimelineView(.periodic(from: .now, by: 0.5)) { context in
                            let position = track.position(at: context.date)
                            VStack(spacing: 2) {
                                ProgressView(value: position, total: track.duration)
                                    .progressViewStyle(.linear)
                                    .controlSize(.small)
                                if !compact {
                                    HStack {
                                        Text(Self.clock(position))
                                        Spacer()
                                        Text("-" + Self.clock(track.duration - position))
                                    }
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                } else if media.permissionDenied {
                    Text("Mirinae needs permission to read from Music").font(.callout)
                    Text("Allow it in System Settings → Privacy & Security → Automation.").font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nothing playing").font(compact ? .callout : .headline)
                    Text("Apple Music and Spotify show up here.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if media.track != nil {
                HStack(spacing: compact ? 6 : 10) {
                    Button {
                        media.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    Button {
                        media.playPause()
                    } label: {
                        Image(systemName: media.track?.isPlaying == true ? "pause.fill" : "play.fill")
                    }
                    .font(compact ? .body : .title3)
                    Button {
                        media.next()
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
        .onAppear { media.start() }
    }

    static func clock(_ seconds: Double) -> String {
        let s = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var artworkView: some View {
        Group {
            if let art = media.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: compact ? 44 : 64, height: compact ? 44 : 64)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
    }
}
