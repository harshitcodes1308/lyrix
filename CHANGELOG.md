# Changelog

## 0.1.0 — Native interface redesign

- Material-backed 390-point music control popover with source hierarchy, central playback control, timestamps, and horizontal mode selection.
- Reusable design tokens and pressed button styling.
- Ten-mode Settings gallery with lightweight symbolic cards and one shared live preview.
- Larger settings layout; existing playback, import, overlay, and preference actions preserved.
- SwiftPM tests: seven passing. Release packaging succeeds.
- This pass has not visually verified the new interface. First-run onboarding, appearance presets, overlay hover controls, and expanded appearance settings remain outstanding.

## Automatic metadata-driven lyrics lookup

- AppModel starts a cancellable lookup on Spotify track-ID changes, ignores stale responses, and exposes retrieved lyrics and retry/status controls.
- Added cache-first high-confidence lookup resolver and reusable playback observation clock.
- Added mocked lookup/cache/failure tests, clock correction tests, and word interval bounds tests: 10 passing tests total.
- Live metadata check returned Heartbeat / Childish Gambino / playing. Live online retrieval and app UI were not verified in this pass.
- Reference source inspected: RithvikVatti/lyric App.tsx, server/index.js, playbackClock.ts, and lrcParser.ts. Swift implementation independently implements the observation-clock architecture; no source code copied.
- Remaining limitations: plain-only result reporting, manual Spotify assignments, broader-search fallback, estimated timing provenance, and wiring the new clock into existing local playback remain incomplete. Spotify playback-driven rendering remains disabled.

## Shared synchronization pipeline

- Added PlaybackSession and wired local/demo playback and all visualizations through its monotonic clock and timeline.
- Added explicit retrieved-lyrics simulation and local-audio assignment actions in existing Lyrics settings.
- Local audio observations sampled at 4 Hz independently of rendering.
- Verified all 44 cached lines through the shared timeline, pause stability, source changes, stale observation rejection, seek, and drift correction. Twelve tests passed; release packaged.
- Synthetic observation replay is covered; live Spotify timing remains disconnected and unauthorized. Interactive audio/GUI verification was not performed in this pass.

## Independent Spotify playback adapter

- Added SpotifyPlaybackAdapter with typed events, generation cancellation, sequence freshness checks, track-bound lyric resolution, and bounded query-latency compensation.
- Added adapter tests for activation, pauses, seeks, track switching, drift, stale results, cancellation, and timeline continuity.
- Fifteen tests pass; release packaging succeeds. Production live forwarding stays absent pending authorization. See docs/spotify-playback-adapter.md for exact wiring boundary and verification limits.

## Production forwarding connection

- Added SpotifyPlaybackForwarder and connected the production monitor to adapter tickets, validated events, and a closed rendering gate.
- Added Spotify source identity to PlaybackSession and guarded asynchronous lyric attachment.
- Production forwarding integration tests cover gate isolation, track changes, pause/resume, seeks, late lyrics, and cancellation. Sixteen tests pass.
- Packaged app launched; demo constellation overlay visually checked. Live rendering remains disabled; see docs/spotify-playback-adapter.md.
