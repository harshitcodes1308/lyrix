import Foundation
import Testing
@testable import LyrixCore

@Test func lrcAndTimeline() {
    let d = LRCParser.parse("[ti:Test]\n[00:01.00][00:02.00]Hello\n[00:04.00]World")
    #expect(d.metadata["ti"] == "Test")
    #expect(d.lines.count == 3)
    #expect(LyricsTimeline.state(document: d, time: 2.5).active?.text == "Hello")
    #expect(LyricsTimeline.state(document: d, time: 0).active == nil)
    #expect(LyricsTimeline.state(document: d, time: 4.5).active?.text == "World")
}
@Test func malformedAndUnicode() {
    let d = LRCParser.parse("[xx:abc]\r\n[01:99.00]bad\r\n[00:03.50]नमस्ते")
    #expect(d.lines.count == 1)
    #expect(d.lines[0].text == "नमस्ते")
}
@Test func spotifyDuration() {
    let t = SpotifyTrack(id: "x", title: "a", artist: "b", album: "c", durationMilliseconds: 230165)
    #expect(abs(t.duration - 230.165) < 0.001)
}
@Test func cacheRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = LyricsCache(directory: dir)
    let track = TrackIdentity(title: "A/B", artist: "Singer")
    let doc = LRCParser.parse("[00:01.00]line")
    try cache.save(doc, for: track)
    #expect(cache.load(track)?.lines.first?.text == "line")
    try cache.clear()
    #expect(cache.load(track) == nil)
}

@Test func offsetsAndWords() {
    let d = LRCParser.parse("[00:01.00]<00:01.00>Hello <00:01.50>world\n[offset:1000]")
    #expect(d.lines[0].startTime == 2)
    #expect(d.lines[0].words.count == 2)
    #expect(d.lines[0].words[1].startTime == 2.5)
}
@Test func seekAndPauseState() {
    let d = LRCParser.parse("[00:01.00]A\n[00:03.00]B")
    #expect(LyricsTimeline.state(document: d, time: 1.5).active?.text == "A")
    #expect(LyricsTimeline.state(document: d, time: 3.5).active?.text == "B")
    #expect(LyricsTimeline.state(document: d, time: 1.5).active?.text == "A")
    #expect(LyricsTimeline.state(document: d, time: 0.5, offset: 1).active?.text == "A")
}
@Test func matchingRejectsCover() {
    let doc = LRCParser.parse("[00:01.00]Test")
    let original = TrackIdentity(title: "Song", artist: "Original", duration: 200)
    let good = LyricsCandidate(id: "a", track: original, document: doc, provider: "test")
    let cover = LyricsCandidate(id: "b", track: TrackIdentity(title: "Song", artist: "Cover", duration: 201), document: doc, provider: "test")
    #expect(LyricsMatcher.score(good, for: original) > LyricsMatcher.score(cover, for: original))
}

@Test func clockCorrections() {
    var clock = PlaybackClock()
    clock.reset(position: 10, playing: true, at: 100)
    #expect(clock.position(at: 102) == 12)
    clock.observe(position: 11.9, playing: true, at: 102)
    #expect(clock.position(at: 102) >= 12)
    clock.observe(position: 12, playing: false, at: 103)
    #expect(clock.position(at: 110) == 12)
    clock.observe(position: 12, playing: true, at: 110)
    #expect(clock.position(at: 111) == 13)
    clock.observe(position: 2, playing: true, at: 111, discontinuity: true)
    #expect(clock.position(at: 111) == 2)
}
private struct MockLyricsProvider: LyricsProvider {
    var results: [LyricsCandidate] = []
    var fails = false
    func search(track: TrackIdentity) async throws -> [LyricsCandidate] {
        if fails { throw LyricsNetworkError.unavailable(503) }
        return results
    }
}
@Test @MainActor func automaticLookupAndCache() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let cache = LyricsCache(directory: folder)
    let track = TrackIdentity(title: "Original", artist: "Artist", album: "Album", duration: 200)
    let doc = LRCParser.parse("[00:01]One two\n[00:05]Three")
    let provider = MockLyricsProvider(results: [LyricsCandidate(id: "1", track: track, document: doc, provider: "Mock")])
    let first = try await LyricsLookup.resolve(track: track, provider: provider, cache: cache)
    #expect(first == doc)
    let cached = try await LyricsLookup.resolve(track: track, provider: MockLyricsProvider(fails: true), cache: cache)
    #expect(cached == doc)
    do {
        _ = try await LyricsLookup.resolve(track: TrackIdentity(title: "Missing", artist: "Other"), provider: MockLyricsProvider(fails: true), cache: cache)
        Issue.record("Expected provider failure")
    } catch { }
}
@Test func wordIntervalsStayWithinLine() {
    let words = WordTiming.estimate("Hello, 世界 again!", start: 2, end: 8)
    #expect(words.first?.startTime == 2)
    #expect(words.last?.endTime == 8)
    for pair in zip(words, words.dropFirst()) { #expect(pair.0.endTime <= pair.1.startTime) }
}

@Test func playbackSessionRecordedObservations() throws {
    // Deterministic Spotify-style replay: monotonic receipt time, media position, playback state.
    // Synthetic observations, not a claim of captured live Spotify timing.
    let records: [(Double, Double, Bool, Bool)] = [
        (100, 20, true, true), (101, 20.95, true, false),
        (102, 22, false, false), (107, 22, true, false),
        (108, 60, true, true), (109, 10, true, true)
    ]
    let doc = LRCParser.parse("[00:00]Intro\n[00:20]Verse\n[01:00]Chorus")
    var session = PlaybackSession()
    session.activate(source: .simulatedSpotify, trackID: "spotify:track:fixture", document: doc, at: 100)
    for (receipt, position, playing, seek) in records {
        session.observe(trackID: "spotify:track:fixture", position: position, playing: playing, at: receipt, seek: seek)
        let sampled = session.position(at: receipt)
        #expect(abs(sampled - position) < 0.1)
        #expect(session.timeline(position: sampled).active?.text == LyricsTimeline.state(document: doc, time: sampled).active?.text)
        if !playing { #expect(session.position(at: receipt + 4) == sampled) }
    }
    session.activate(source: .localAudio, trackID: "new", document: doc, at: 110)
    session.observe(trackID: "spotify:track:fixture", position: 100, playing: true, at: 111)
    #expect(session.position(at: 111) == 0)
    #expect(session.source == .localAudio)
}

@Test func existing44LineCachePipeline() throws {
    // Opt-in local integration fixture: never redistribute cached song lyrics in the repository.
    guard let path = ProcessInfo.processInfo.environment["LYRIX_CACHED_LYRICS"] else { return }
    let doc = try JSONDecoder().decode(LyricsDocument.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    #expect(doc.lines.count == 44)
    var session = PlaybackSession()
    session.activate(source: .simulatedSpotify, trackID: "recorded-metadata", document: doc, at: 100)
    for line in doc.lines where line.endTime > line.startTime {
        session.observe(trackID: "recorded-metadata", position: line.startTime + 0.001, playing: true, at: 100, seek: true)
        #expect(session.timeline(position: session.position(at: 100)).active?.id == line.id)
    }
    session.activate(source: .localAudio, trackID: "local-fixture", document: doc, at: 200)
    session.observe(trackID: "local-fixture", position: 30, playing: false, at: 201, seek: true)
    #expect(session.position(at: 210) == 30)
    #expect(session.document == doc)
}
