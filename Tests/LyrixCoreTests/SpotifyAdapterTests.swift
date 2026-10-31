import Foundation
import Testing
@testable import LyrixCore

private func observation(_ id: String = "a", _ position: Double = 10, _ state: SpotifyPlaybackState = .playing) -> SpotifyObservation {
    SpotifyObservation(track: SpotifyTrack(id: id, title: id, artist: "Fixture", album: "Test", durationMilliseconds: 180000), position: position, state: state)
}

@Test func adapterActivationLatencyAndCancellation() throws {
    var adapter = SpotifyPlaybackAdapter()
    #expect(adapter.beginQuery(at: 0) == nil)
    adapter.activate()
    let ticket = try unwrap(adapter.beginQuery(at: 100))
    let document = LRCParser.parse("[00:00]Original\n[00:20]Next")
    let event = try unwrap(adapter.receive(observation(), ticket: ticket, at: 100.2, lyrics: { _ in document }))
    #expect(event.activatesTrack)
    #expect(event.lyrics == document)
    #expect(abs(event.position - 10.1) < 0.00001)
    #expect(abs(event.queryLatency - 0.2) < 0.00001)
    #expect(event.duration == 180)
    #expect(adapter.receive(observation(), ticket: ticket, at: 101, lyrics: { _ in nil }) == nil)
    let pending = try unwrap(adapter.beginQuery(at: 102))
    adapter.cancel(); adapter.activate()
    #expect(adapter.receive(observation(), ticket: pending, at: 103, lyrics: { _ in nil }) == nil)
}

@Test func adapterRejectsOutOfOrderAndSwitchesTrack() throws {
    var adapter = SpotifyPlaybackAdapter(); adapter.activate()
    let old = try unwrap(adapter.beginQuery(at: 1))
    let new = try unwrap(adapter.beginQuery(at: 2))
    let changed = try unwrap(adapter.receive(observation("b"), ticket: new, at: 3, lyrics: { _ in nil }))
    #expect(changed.trackID == "b")
    #expect(adapter.receive(observation("a"), ticket: old, at: 4, lyrics: { _ in nil }) == nil)
    let paused = try unwrap(adapter.beginQuery(at: 5))
    let event = try unwrap(adapter.receive(observation("b", 15, .paused), ticket: paused, at: 6, lyrics: { _ in nil }))
    #expect(!event.activatesTrack)
    #expect(event.position == 15)
    #expect(!event.playing)
}

@Test func adapterSessionContinuitySeekAndDrift() throws {
    var adapter = SpotifyPlaybackAdapter(); adapter.activate()
    var session = PlaybackSession()
    let document = LRCParser.parse("[00:00]Intro\n[00:20]Verse\n[01:00]Chorus")
    // Forwarding exists only in this synthetic test, never in the app's live monitor.
    let records: [(String, Double, SpotifyPlaybackState, Double)] = [
        ("a", 20, .playing, 100), ("a", 20.95, .playing, 101),
        ("a", 22, .paused, 102), ("a", 22, .playing, 107),
        ("a", 65, .playing, 108), ("a", 5, .playing, 109), ("b", 0, .paused, 110)
    ]
    for (id, position, state, uptime) in records {
        let ticket = try unwrap(adapter.beginQuery(at: uptime))
        let event = try unwrap(adapter.receive(observation(id, position, state), ticket: ticket, at: uptime, lyrics: { _ in document }))
        if event.activatesTrack {
            session.activate(source: .simulatedSpotify, trackID: id, document: try #require(event.lyrics), position: event.position, playing: event.playing, at: uptime)
        } else {
            session.observe(trackID: id, position: event.position, playing: event.playing, at: uptime)
        }
        let rendered = session.position(at: uptime)
        #expect(abs(rendered - position) < 0.1)
        #expect(session.document == document)
        #expect(session.timeline(position: rendered).active != nil)
        if state == .paused { #expect(session.position(at: uptime + 2) == rendered) }
    }
}

private func unwrap<T>(_ value: T?) throws -> T { try #require(value) }

@Test func productionForwardingGateAndLifecycle() throws {
    var bridge = SpotifyPlaybackForwarder()
    var session = PlaybackSession()
    let local = LRCParser.parse("[00:00]Local")
    let remote = LRCParser.parse("[00:00]Remote\n[00:30]Next")
    session.activate(source: .localAudio, trackID: "local", document: local, position: 3, at: 0)
    let blockedTicket = try unwrap(bridge.beginQuery(at: 1))
    let blocked = bridge.receive(observation(), ticket: blockedTicket, at: 1,
        renderingPermitted: false, session: &session, lyrics: { _ in remote })
    #expect(!blocked)
    #expect(session.source == .localAudio)
    #expect(session.document == local)
    #expect(session.position(at: 1) == 3)
    // Exercise the actual production forwarder with synthetic authorization in tests only.
    for (time, pos, state) in [(2.0, 10.0, SpotifyPlaybackState.playing), (3, 11, .paused), (6, 11, .playing), (7, 60, .playing), (8, 2, .playing)] {
        let ticket = try unwrap(bridge.beginQuery(at: time))
        let forwarded = bridge.receive(observation("a", pos, state), ticket: ticket, at: time,
            renderingPermitted: true, session: &session, lyrics: { _ in remote })
        #expect(forwarded)
        #expect(session.source == .spotify)
        #expect(session.document == remote)
        #expect(abs(session.position(at: time) - pos) < 0.01)
    }
    let switchTicket = try unwrap(bridge.beginQuery(at: 9))
    _ = bridge.receive(observation("b", 0, .paused), ticket: switchTicket, at: 9,
        renderingPermitted: true, session: &session, lyrics: { _ in nil })
    #expect(session.document.lines.isEmpty)
    bridge.attachLyrics(remote, trackID: "a", renderingPermitted: true, session: &session)
    #expect(session.document.lines.isEmpty)
    bridge.attachLyrics(remote, trackID: "b", renderingPermitted: true, session: &session)
    #expect(session.document == remote)
    let pending = try unwrap(bridge.beginQuery(at: 10))
    bridge.cancel()
    session.activate(source: .localAudio, trackID: "local", document: local, at: 10)
    let stale = bridge.receive(observation(), ticket: pending, at: 11, renderingPermitted: true, session: &session, lyrics: { _ in remote })
    #expect(!stale)
    #expect(session.document == local)
}
