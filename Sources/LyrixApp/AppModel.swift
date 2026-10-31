import AppKit
import AVFoundation
import Combine
import LyrixCore

struct Preferences: Codable {
    var mode = "Minimal"
    var fontSize = 34.0
    var opacity = 0.92
    var highlight = "blue"
    var alwaysOnTop = true
    var clickThrough = false
    var showOverlay = true
    var offset = 0.0
    var reducedMotion = false
    var overlayFrame: String? = nil
}

@MainActor final class AppModel: ObservableObject {
    static let modes = ["Minimal", "Fisheye", "Visual", "Fisheye Visual", "Codestyle", "Codestyle Visual", "Branches", "Web", "Constellation", "Kinetic Word"]
    @Published var preferences: Preferences { didSet { persist() } }
    @Published var document: LyricsDocument { didSet { session.replaceLyrics(document) } }
    @Published var position: Double = 0
    @Published var duration: Double = 49
    @Published var isPlaying = false
    @Published var isDemo = true
    @Published var sourceLabel = "Demo timeline (no audio)"
    @Published var message: String? = nil
    @Published var candidates: [LyricsCandidate] = []
    @Published var spotifyStatus = "Checking Spotify…"
    @Published var spotifyTrack: SpotifyTrack? = nil
    @Published var spotifyPosition: Double = 0
    @Published var spotifyLyrics: LyricsDocument?
    @Published var spotifyLyricsStatus = "Waiting for Spotify track"
    private var spotifyLookup: Task<Void, Never>?
    private var lookupTrackID: String?
    private var player: AVAudioPlayer?
    private var session = PlaybackSession()
    private var lastAudioObservation = 0.0
    private var uptime: Double { ProcessInfo.processInfo.systemUptime }
    private var timer: Timer?
    private var spotifyTimer: Timer?
    private var spotifyBusy = false
    private var spotifyForwarder = SpotifyPlaybackForwarder()
    // No authorization established for live lyric rendering. No user-default bypass.
    private let spotifyRenderingPermitted = false
    private let cache = LyricsCache()

    init() {
        if let data = UserDefaults.standard.data(forKey: "preferences"), let saved = try? JSONDecoder().decode(Preferences.self, from: data) { preferences = saved }
        else { preferences = Preferences() }
        let demo = Bundle.main.url(forResource: "demo", withExtension: "lrc")
        document = LRCParser.parse((demo.flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "[00:00.00]Welcome to Lyrix", source: "Demo")
        session.activate(source: .demo, trackID: "demo", document: document, at: uptime)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        spotifyTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.pollSpotify() } }
        pollSpotify()
    }
    private func persist() { if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "preferences") } }
    var timeline: TimelineState { session.timeline(position: position, offset: preferences.offset) }
    func playPause() { isPlaying ? pause() : play() }
    func play() {
        if position >= duration { seek(0) }
        if !isDemo {
            guard let player else { return }
            player.currentTime = position
            guard player.play() else { message = "Audio playback could not start."; return }
        }
        session.observe(trackID: session.trackID, position: position, playing: true, at: uptime)
        isPlaying = true
    }
    func pause() {
        guard isPlaying else { return }
        position = min(duration, session.position(at: uptime))
        player?.pause()
        session.observe(trackID: session.trackID, position: position, playing: false, at: uptime)
        isPlaying = false
    }
    func seek(_ time: Double) {
        position = min(duration, max(0, time))
        player?.currentTime = position
        session.observe(trackID: session.trackID, position: position, playing: isPlaying, at: uptime, seek: true)
    }
    private func tick() {
        guard isPlaying else { return }
        let now = uptime
        if session.source == .localAudio, let player, now - lastAudioObservation >= 0.25 {
            lastAudioObservation = now
            session.observe(trackID: session.trackID, position: player.currentTime, playing: player.isPlaying, at: now)
            if !player.isPlaying { isPlaying = false }
        }
        position = min(duration, session.position(at: now))
        if position >= duration { pause() }
    }
    func simulateRetrievedLyrics() {
        guard let lyrics = spotifyLyrics else { return }
        spotifyForwarder.cancel()
        pause(); player = nil; isDemo = true; position = 0
        duration = max(1, spotifyTrack?.duration ?? lyrics.lines.last?.endTime ?? 1)
        document = lyrics
        sourceLabel = "Simulated Spotify observations (no audio)"
        session.activate(source: .simulatedSpotify, trackID: spotifyTrack?.id ?? "simulation", document: lyrics, at: uptime)
    }
    func useRetrievedLyricsForLocalAudio() {
        guard !isDemo, let lyrics = spotifyLyrics else { return }
        document = lyrics
    }
    func useDemo() {
        spotifyForwarder.cancel()
        pause(); player = nil; isDemo = true; duration = 49; position = 0
        sourceLabel = "Demo timeline (no audio)"
        if let url = Bundle.main.url(forResource: "demo", withExtension: "lrc"), let raw = try? String(contentsOf: url, encoding: .utf8) { document = LRCParser.parse(raw, source: "Demo") }
        session.activate(source: .demo, trackID: "demo", document: document, at: uptime)
        message = nil
    }
    func importAudio() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose local audio or an LRC file from Desktop or any folder."
        panel.prompt = "Open"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        let savedDirectory = UserDefaults.standard.url(forKey: "lastAudioDirectory")
        panel.directoryURL = savedDirectory ?? desktop
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.pathExtension.lowercased() == "lrc" {
            loadLyrics(from: url)
            return
        }
        do {
            spotifyForwarder.cancel()
            pause(); player = try AVAudioPlayer(contentsOf: url); player?.prepareToPlay()
            UserDefaults.standard.set(url.deletingLastPathComponent(), forKey: "lastAudioDirectory")
            isDemo = false; duration = player?.duration ?? 0; position = 0
            sourceLabel = url.lastPathComponent
            let adjacent = url.deletingPathExtension().appendingPathExtension("lrc")
            if let raw = try? String(contentsOf: adjacent, encoding: .utf8) { document = LRCParser.parse(raw, source: "Adjacent LRC") }
            else if let cached = cache.load(TrackIdentity(title: url.deletingPathExtension().lastPathComponent, artist: "")) { document = cached }
            else { document = LyricsDocument(lines: [], source: "None") }
            session.activate(source: .localAudio, trackID: url.absoluteString, document: document, at: uptime)
            message = document.lines.isEmpty ? "No synchronized lyrics found. Import an LRC file." : nil
        } catch { message = "Could not open audio: \(error.localizedDescription)" }
    }
    func importLyrics() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.init(filenameExtension: "lrc")!]; panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadLyrics(from: url)
    }
    private func loadLyrics(from url: URL) {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { message = "Could not read LRC file."; return }
        let parsed = LRCParser.parse(raw, source: url.lastPathComponent)
        guard !parsed.lines.isEmpty else { message = "No valid timestamps in this LRC file."; return }
        if isDemo {
            pause()
            position = 0
            duration = max(1, parsed.lines.last?.endTime ?? 1)
            sourceLabel = "Lyrics preview (no audio) · \(url.lastPathComponent)"
        }
        document = parsed; message = nil
        if isDemo { session.activate(source: .demo, trackID: url.absoluteString, document: parsed, at: uptime) }
        if !isDemo {
            let key = TrackIdentity(title: URL(fileURLWithPath: sourceLabel).deletingPathExtension().lastPathComponent, artist: "")
            try? cache.save(parsed, for: key)
        }
    }
    func searchLyrics() {
        guard !isDemo else { message = "Import local audio before searching for its lyrics."; return }
        let name = URL(fileURLWithPath: sourceLabel).deletingPathExtension().lastPathComponent
        let track = TrackIdentity(title: name, artist: "")
        if let cached = cache.load(track) { document = cached; message = nil; return }
        Task {
            do {
                let found = try await LRCLIBProvider().search(track: track)
                candidates = found
                guard let best = found.first else { message = "No synchronized lyrics found. Import an LRC file."; return }
                if LyricsMatcher.score(best, for: track) >= 0.72 { selectCandidate(best) }
                else { message = "Choose a lyrics result below or import an LRC file." }
            } catch { message = error.localizedDescription }
        }
    }
    func selectCandidate(_ candidate: LyricsCandidate) {
        document = candidate.document
        let name = URL(fileURLWithPath: sourceLabel).deletingPathExtension().lastPathComponent
        try? cache.save(candidate.document, for: TrackIdentity(title: name, artist: ""))
        message = nil
    }
    func retrySpotifyLyrics() {
        lookupTrackID = nil
        updateSpotifyLyrics(spotifyTrack)
    }
    private func updateSpotifyLyrics(_ track: SpotifyTrack?) {
        guard let track else { return }
        guard lookupTrackID != track.id else { return }
        lookupTrackID = track.id
        spotifyLookup?.cancel()
        spotifyLyrics = nil
        spotifyLyricsStatus = "Searching lyrics…"
        let identity = TrackIdentity(title: track.title, artist: track.artist, album: track.album, duration: track.duration)
        spotifyLookup = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await LyricsLookup.resolve(track: identity, provider: LRCLIBProvider(), cache: cache)
                guard !Task.isCancelled, lookupTrackID == track.id else { return }
                spotifyLyrics = result
                if let result {
                    spotifyForwarder.attachLyrics(result, trackID: track.id, renderingPermitted: spotifyRenderingPermitted, session: &session)
                    if spotifyRenderingPermitted, session.source == .spotify { document = session.document }
                }
                spotifyLyricsStatus = result == nil ? "Lyrics unavailable — no confident synchronized match" : "Synced lyrics found · \(result!.lines.count) lines"
            } catch {
                guard !Task.isCancelled, lookupTrackID == track.id else { return }
                spotifyLyricsStatus = "Lyrics lookup failed: \(error.localizedDescription)"
            }
        }
    }
    private func pollSpotify() {
        guard !spotifyBusy else { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first != nil else {
            spotifyStatus = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") == nil ? "Spotify not installed" : "Spotify not running"
            spotifyForwarder.cancel()
            spotifyLookup?.cancel(); lookupTrackID = nil; spotifyLyrics = nil
            spotifyLyricsStatus = "Waiting for Spotify track"
            spotifyTrack = nil; return
        }
        spotifyBusy = true
        guard let ticket = spotifyForwarder.beginQuery(at: uptime) else { spotifyBusy = false; return }
        DispatchQueue.global(qos: .utility).async {
            let result = SpotifyReader.read()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.spotifyBusy = false
                switch result {
                case .success(let observation):
                    let cached = observation.track.flatMap { track in
                        self.cache.load(TrackIdentity(title: track.title, artist: track.artist, album: track.album, duration: track.duration))
                    }
                    let forwarded = self.spotifyForwarder.receive(observation, ticket: ticket, at: self.uptime,
                        renderingPermitted: self.spotifyRenderingPermitted, session: &self.session, lyrics: { _ in cached })
                    if forwarded, let event = self.spotifyForwarder.latestEvent {
                        self.player?.pause()
                        self.document = self.session.document
                        self.duration = event.duration
                        self.position = self.session.position(at: self.uptime)
                        self.isPlaying = event.playing
                        self.sourceLabel = "Spotify · " + event.track.title
                    }
                    self.updateSpotifyLyrics(observation.track)
                    self.spotifyTrack = observation.track; self.spotifyPosition = observation.position; self.spotifyStatus = "Spotify connected · metadata only"
                case .failure(let error):
                    self.spotifyForwarder.cancel()
                    self.spotifyTrack = nil; self.spotifyStatus = error.localizedDescription
                }
            }
        }
    }
}

private enum SpotifyReader {
    static func read() -> Result<SpotifyObservation, Error> {
        let script = "tell application id \"com.spotify.client\" to return {id of current track, name of current track, artist of current track, album of current track, duration of current track, player position, player state as text}"
        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&error) else {
            let number = error?[NSAppleScript.errorNumber] as? Int
            let detail = number == -1743 ? "Spotify Automation permission required. Allow Lyrix in System Settings → Privacy & Security → Automation." : "Spotify running but metadata unavailable."
            return .failure(NSError(domain: "Lyrix", code: number ?? 1, userInfo: [NSLocalizedDescriptionKey: detail]))
        }
        guard descriptor.numberOfItems >= 7,
              let id = descriptor.atIndex(1)?.stringValue,
              let title = descriptor.atIndex(2)?.stringValue,
              let artist = descriptor.atIndex(3)?.stringValue,
              let album = descriptor.atIndex(4)?.stringValue else {
            return .failure(NSError(domain: "Lyrix", code: 2, userInfo: [NSLocalizedDescriptionKey: "Spotify metadata is incomplete."]))
        }
        let duration = Double(descriptor.atIndex(5)?.int32Value ?? 0)
        let position = descriptor.atIndex(6)?.doubleValue ?? 0
        let state = SpotifyPlaybackState(rawValue: descriptor.atIndex(7)?.stringValue ?? "") ?? .unknown
        return .success(SpotifyObservation(track: SpotifyTrack(id: id, title: title, artist: artist, album: album, durationMilliseconds: duration), position: position, state: state))
    }
}
