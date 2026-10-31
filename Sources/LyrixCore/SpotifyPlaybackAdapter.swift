import Foundation

/// Pure event conversion. Creating/activating this adapter does not authorize live rendering.
/// Production observations reach this adapter through SpotifyPlaybackForwarder; rendering is gated.
public struct SpotifyPlaybackAdapter: Sendable {
    public struct Ticket: Sendable {
        fileprivate let generation: UUID
        public let sequence: UInt64
        public let queryStartedAt: Double
    }
    public struct Event: Sendable {
        public let track: SpotifyTrack
        public var trackID: String { track.id }
        public var duration: Double { track.duration }
        public let position: Double
        public let state: SpotifyPlaybackState
        public let observedAt: Date
        public let receivedAt: Double
        public let queryLatency: Double
        public let activatesTrack: Bool
        public var playing: Bool { state == .playing }
        /// Already-parsed cached document, attached only for an activation.
        public let lyrics: LyricsDocument?
    }
    private var generation: UUID?
    private var issued: UInt64 = 0
    private var accepted: UInt64 = 0
    private var lastReceipt = -Double.infinity
    public private(set) var trackID: String?
    public init() {}
    public mutating func activate() {
        generation = UUID(); issued = 0; accepted = 0
        lastReceipt = -.infinity; trackID = nil
    }
    public mutating func cancel() { generation = nil; trackID = nil }
    public mutating func beginQuery(at uptime: Double) -> Ticket? {
        guard let generation, uptime.isFinite else { return nil }
        issued += 1
        return Ticket(generation: generation, sequence: issued, queryStartedAt: uptime)
    }
    public mutating func receive(_ observation: SpotifyObservation, ticket: Ticket, at uptime: Double,
                                 lyrics: (String) -> LyricsDocument?) -> Event? {
        guard generation == ticket.generation, ticket.sequence > accepted,
              uptime.isFinite, uptime >= ticket.queryStartedAt, uptime >= lastReceipt,
              observation.error == nil, let track = observation.track,
              !track.id.isEmpty, track.duration.isFinite, track.duration > 0,
              observation.position.isFinite, observation.state != .unknown else { return nil }
        let changed = trackID != track.id
        // Midpoint sampling estimate: exact AppleScript property-read time is unknown.
        // Cap uncertain compensation to 250ms; paused/stopped positions never advance.
        let latency = uptime - ticket.queryStartedAt
        let correction = observation.state == .playing ? min(0.25, latency / 2) : 0
        let position = min(track.duration, max(0, observation.position + correction))
        accepted = ticket.sequence; lastReceipt = uptime; trackID = track.id
        return Event(track: track, position: position, state: observation.state,
                     observedAt: observation.observedAt, receivedAt: uptime,
                     queryLatency: latency, activatesTrack: changed,
                     lyrics: changed ? lyrics(track.id) : nil)
    }
}
