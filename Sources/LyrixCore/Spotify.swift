import Foundation

public struct SpotifyTrack: Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public init(id: String, title: String, artist: String, album: String, durationMilliseconds: Double) {
        self.id = id; self.title = title; self.artist = artist; self.album = album; self.duration = durationMilliseconds / 1000
    }
}

public enum SpotifyPlaybackState: String, Sendable { case playing, paused, stopped, unknown }

public struct SpotifyObservation: Sendable {
    public let track: SpotifyTrack?
    public let position: TimeInterval
    public let state: SpotifyPlaybackState
    public let observedAt: Date
    public let error: String?
    public init(track: SpotifyTrack?, position: TimeInterval, state: SpotifyPlaybackState, observedAt: Date = Date(), error: String? = nil) {
        self.track = track; self.position = position; self.state = state; self.observedAt = observedAt; self.error = error
    }
}
