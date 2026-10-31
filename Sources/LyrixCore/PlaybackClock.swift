import Foundation

/// Observation clock for authorized sources. Times supplied by callers use system uptime.
public struct PlaybackClock: Sendable {
    private var base = 0.0
    private var anchor = 0.0
    private var playing = false
    private var last = 0.0
    public init() {}
    public mutating func reset(position: Double, playing: Bool, at now: Double) {
        base = max(0, position); anchor = now; self.playing = playing; last = base
    }
    public mutating func position(at now: Double) -> Double {
        let value = max(0, base + (playing ? max(0, now - anchor) : 0))
        last = playing ? max(last, value) : value
        return last
    }
    public mutating func observe(position: Double, playing: Bool, at now: Double, discontinuity: Bool = false) {
        let predicted = self.position(at: now)
        let drift = position - predicted
        if discontinuity || abs(drift) > 1.5 || self.playing != playing {
            reset(position: position, playing: playing, at: now)
        } else {
            base = max(0, predicted + drift * 0.15); anchor = now
        }
    }
}

public enum LyricsLookup {
    public static func resolve(track: TrackIdentity, provider: any LyricsProvider, cache: LyricsCache) async throws -> LyricsDocument? {
        if let cached = cache.load(track) { return cached }
        let results = try await provider.search(track: track)
        try Task.checkCancellation()
        let ranked = results.sorted { LyricsMatcher.score($0, for: track) > LyricsMatcher.score($1, for: track) }
        guard let best = ranked.first, !best.document.lines.isEmpty,
              LyricsMatcher.score(best, for: track) >= 0.88 else { return nil }
        try cache.save(best.document, for: track)
        return best.document
    }
}
