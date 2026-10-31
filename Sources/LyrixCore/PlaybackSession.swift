import Foundation

/// Single clock/timeline owner. Live Spotify activation is guarded by the production forwarder.
public struct PlaybackSession: Sendable {
    public enum Source: String, Sendable { case demo, localAudio, simulatedSpotify, spotify }
    public private(set) var source: Source = .demo
    public private(set) var trackID = "demo"
    public private(set) var document = LyricsDocument(lines: [])
    private var clock = PlaybackClock()
    public init() {}
    public mutating func activate(source: Source, trackID: String, document: LyricsDocument, position: Double = 0, playing: Bool = false, at now: Double) {
        self.source = source; self.trackID = trackID; self.document = document
        clock.reset(position: position, playing: playing, at: now)
    }
    public mutating func replaceLyrics(_ document: LyricsDocument) { self.document = document }
    public mutating func observe(trackID: String, position: Double, playing: Bool, at now: Double, seek: Bool = false) {
        guard self.trackID == trackID else { return } // stale observation from previous source
        clock.observe(position: position, playing: playing, at: now, discontinuity: seek)
    }
    public mutating func position(at now: Double) -> Double { clock.position(at: now) }
    public func timeline(position: Double, offset: Double = 0) -> TimelineState {
        LyricsTimeline.state(document: document, time: position, offset: offset)
    }
}
