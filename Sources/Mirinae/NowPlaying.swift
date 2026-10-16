// SPDX-License-Identifier: Apache-2.0
import AppKit
import Foundation

struct NowPlayingTrack: Equatable {
    enum Source: String { case music = "Music", spotify = "Spotify" }
    enum State: String { case playing, paused, stopped }

    var source: Source
    var state: State
    var title: String
    var artist: String
    var album: String
    var position: Double
    var duration: Double
    var trackID: String
    var positionDate = Date()

    var isPlaying: Bool { state == .playing }

    /// Position extrapolated from the last reading, so the bar moves between polls.
    func position(at date: Date) -> Double {
        guard isPlaying else { return position }
        return min(position + date.timeIntervalSince(positionDate), duration > 0 ? duration : .infinity)
    }
}

/// Polls Apple Music and Spotify through their AppleScript dictionaries. Both are public
/// interfaces and both hand back artwork. Nothing is launched: an app that is not running is
/// skipped.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    static let shared = NowPlayingMonitor()

    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var permissionDenied = false

    private var timer: Timer?
    private var artworkTrackID: String?
    private let queue = DispatchQueue(label: "mirinae.nowplaying")

    func start(interval: TimeInterval = 3) {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func playPause() { control("playpause") }
    func next() { control("next track") }
    func previous() { control("previous track") }

    private func control(_ verb: String) {
        guard let track else { return }
        let app = track.source.rawValue
        queue.async { _ = Self.run("tell application \"\(app)\" to \(verb)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.poll() }
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func poll() {
        let candidates: [(NowPlayingTrack.Source, String)] = [
            (.music, "com.apple.Music"), (.spotify, "com.spotify.client"),
        ]
        let running = candidates.filter { Self.isRunning($0.1) }.map { $0.0 }
        guard !running.isEmpty else {
            track = nil
            artwork = nil
            return
        }
        queue.async { [weak self] in
            var found: NowPlayingTrack?
            var denied = false
            for source in running {
                switch Self.query(source) {
                case .success(let t):
                    if found == nil || (t?.isPlaying == true && found?.isPlaying != true) { found = t ?? found }
                case .denied: denied = true
                case .none: break
                }
            }
            let result = found
            Task { @MainActor in
                guard let self else { return }
                self.permissionDenied = denied && result == nil
                self.track = self.reconciled(result)
                self.refreshArtworkIfNeeded()
            }
        }
    }

    private enum QueryResult { case success(NowPlayingTrack?), denied, none }

    /// A fresh reading that agrees with the extrapolated position within a couple of seconds
    /// keeps the old timestamp, which stops the bar from twitching on each poll.
    private func reconciled(_ fresh: NowPlayingTrack?) -> NowPlayingTrack? {
        guard var fresh, let old = track, old.trackID == fresh.trackID, old.isPlaying, fresh.isPlaying else {
            return fresh
        }
        let predicted = old.position(at: fresh.positionDate)
        if abs(predicted - fresh.position) < 2 {
            fresh.position = old.position
            fresh.positionDate = old.positionDate
        }
        return fresh
    }

    private static func query(_ source: NowPlayingTrack.Source) -> QueryResult {
        let script: String
        switch source {
        case .music:
            script = """
                tell application "Music"
                    set s to player state as string
                    if s is "stopped" then return "stopped"
                    set t to current track
                    return s & linefeed & name of t & linefeed & artist of t & linefeed & album of t & linefeed & player position & linefeed & duration of t & linefeed & database ID of t
                end tell
                """
        case .spotify:
            script = """
                tell application "Spotify"
                    set s to player state as string
                    if s is "stopped" then return "stopped"
                    set t to current track
                    return s & linefeed & name of t & linefeed & artist of t & linefeed & album of t & linefeed & player position & linefeed & (duration of t) / 1000 & linefeed & id of t
                end tell
                """
        }
        guard let output = run(script) else { return .denied }
        guard let text = output.stringValue, text != "stopped" else { return .success(nil) }
        let parts = text.components(separatedBy: "\n")
        guard parts.count >= 7 else { return .success(nil) }
        let state = NowPlayingTrack.State(rawValue: parts[0]) ?? .paused
        let position = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        let duration = Double(parts[5].replacingOccurrences(of: ",", with: ".")) ?? 0
        return .success(
            NowPlayingTrack(
                source: source, state: state, title: parts[1], artist: parts[2], album: parts[3],
                position: position, duration: duration, trackID: "\(source.rawValue):\(parts[6])"))
    }

    private func refreshArtworkIfNeeded() {
        guard let track else { artworkTrackID = nil; artwork = nil; return }
        guard track.trackID != artworkTrackID else { return }
        artworkTrackID = track.trackID
        let source = track.source
        queue.async { [weak self] in
            var image: NSImage?
            switch source {
            case .music:
                if let descriptor = Self.run("tell application \"Music\" to get data of artwork 1 of current track") {
                    image = NSImage(data: descriptor.data)
                }
                if image == nil {
                    image = Self.lookupArtwork(title: track.title, artist: track.artist, album: track.album)
                }
            case .spotify:
                if let url = Self.run("tell application \"Spotify\" to get artwork url of current track")?.stringValue,
                    let u = URL(string: url), let data = Self.fetch(u)
                {
                    image = NSImage(data: data)
                }
            }
            Task { @MainActor in
                guard let self, self.artworkTrackID == track.trackID else { return }
                self.artwork = image
            }
        }
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result
    }
}

extension NowPlayingMonitor {
    /// Streaming tracks in Apple Music expose no artwork through scripting, so look the album
    /// up on the public iTunes Search API instead. Local library tracks never get here.
    static func lookupArtwork(title: String, artist: String, album: String) -> NSImage? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(album.isEmpty ? title : album)"),
            URLQueryItem(name: "entity", value: album.isEmpty ? "song" : "album"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = components.url, let data = fetch(url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = json["results"] as? [[String: Any]]
        else { return nil }
        let wanted = album.lowercased()
        let best = results.first { ($0["collectionName"] as? String)?.lowercased() == wanted } ?? results.first
        guard let small = best?["artworkUrl100"] as? String else { return nil }
        let large = small.replacingOccurrences(of: "100x100", with: "300x300")
        guard let artURL = URL(string: large), let artData = fetch(artURL) else { return nil }
        return NSImage(data: artData)
    }

    /// HTTPS only, short timeout, capped size. Runs on the monitor's background queue.
    static func fetch(_ url: URL, limit: Int = 4_000_000) -> Data? {
        guard url.scheme == "https" else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        let task = session.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                let data, data.count <= limit
            {
                result = data
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        return result
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.httpAdditionalHeaders = ["User-Agent": "Mirinae"]
        return URLSession(configuration: configuration)
    }()
}
