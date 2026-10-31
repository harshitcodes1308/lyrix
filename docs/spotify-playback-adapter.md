# Production Spotify forwarding boundary

## Current event path

AppModel.pollSpotify → SpotifyPlaybackForwarder.beginQuery → background SpotifyReader.read → typed SpotifyObservation → SpotifyPlaybackForwarder.receive → SpotifyPlaybackAdapter.receive → rendering gate → PlaybackSession.activate/observe.

The adapter now runs in production. The app's `spotifyRenderingPermitted` constant is false. Validated events update transport state but cannot change the active document, source, position, or clock while this gate is closed. Metadata and automatic lyrics lookup continue normally.

On an enabled forwarding path, track activation passes an already-parsed cached document directly to the existing session, or an empty document pending lookup. Later lookup results attach only when both the forwarder's current track and the session's Spotify track match. The async lookup also retains its existing task-cancellation and track-ID checks. No reparsing or second clock is introduced.

Generation tickets invalidate in-flight responses on cancellation. Sequence checks reject duplicate and out-of-order results. Cancellation occurs on Spotify unavailability/error and explicit demo/local source activation. Query tickets capture monotonic start time; the adapter applies bounded midpoint latency estimation for playing observations only. The existing PlaybackClock handles interpolation and discontinuities.

## Remaining limitation

Live lyric rendering is NOT enabled. The overlay still uses the explicitly active local/demo/simulation source. The remaining activation decision is the AppModel rendering/source-selection gate. Authorization covering the integration must be established before enabling it; the current false constant is not an authorization mechanism. A permitted deployment must also select Spotify explicitly rather than let background monitoring override a user-selected local source.

Spotify compliance guidance lists syncing Spotify recordings with lyrics as restricted: https://developer.spotify.com/compliance-tips. A private development use case is not established as an exemption by that page.

## Verification

16 tests pass, including the actual production forwarder's closed-gate isolation and enabled synthetic forwarding, pause/resume, seeks, track switching, delayed lyrics, and stale responses after cancellation. The optional 44-line cache test returns early unless LYRIX_CACHED_LYRICS is supplied; it was not supplied in this run.

Release packaged and ad-hoc signature verified. Packaged app launched; the existing constellation-style overlay visibly rendered demo text. No claim of live Spotify synchronized rendering or exhaustive visual-mode QA is made.

Reference architecture previously inspected: RithvikVatti/lyric server/index.js, playbackClock.ts, and App.tsx. No reference code copied.
