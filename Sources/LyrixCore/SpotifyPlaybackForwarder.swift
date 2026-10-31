import Foundation

/// Owns transport freshness only. PlaybackSession remains the sole clock and timeline owner.
public struct SpotifyPlaybackForwarder: Sendable {
    private var adapter = SpotifyPlaybackAdapter()
    private var monitoring = false
    public private(set) var latestEvent: SpotifyPlaybackAdapter.Event?
    public init() {}
    public mutating func beginQuery(at now: Double) -> SpotifyPlaybackAdapter.Ticket? {
        if !monitoring { adapter.activate(); monitoring = true }
        return adapter.beginQuery(at: now)
    }
    public mutating func cancel() {
        adapter.cancel(); monitoring = false; latestEvent = nil
    }
    @discardableResult
    public mutating func receive(_ observation: SpotifyObservation, ticket: SpotifyPlaybackAdapter.Ticket,
                                 at now: Double, renderingPermitted: Bool, session: inout PlaybackSession,
                                 lyrics: (String) -> LyricsDocument?) -> Bool {
        guard let event = adapter.receive(observation, ticket: ticket, at: now, lyrics: lyrics) else { return false }
        latestEvent = event
        guard renderingPermitted else { return false }
        if event.activatesTrack || session.source != .spotify || session.trackID != event.trackID {
            session.activate(source: .spotify, trackID: event.trackID,
                             document: event.lyrics ?? lyrics(event.trackID) ?? LyricsDocument(lines: []),
                             position: event.position, playing: event.playing, at: event.receivedAt)
        } else {
            session.observe(trackID: event.trackID, position: event.position, playing: event.playing, at: event.receivedAt)
        }
        return true
    }
    public func attachLyrics(_ lyrics: LyricsDocument, trackID: String, renderingPermitted: Bool,
                             session: inout PlaybackSession) {
        guard renderingPermitted, monitoring, latestEvent?.trackID == trackID,
              session.source == .spotify, session.trackID == trackID else { return }
        session.replaceLyrics(lyrics)
    }
}
