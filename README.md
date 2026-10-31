# Lyrix

Native macOS menu-bar lyrics visualizer, built with Swift Package Manager and the Xcode Command Line Tools. Full Xcode is not required.

## Build and run

Requires macOS 14 or later, Apple Silicon, Swift 6, and Xcode Command Line Tools.

```sh
./Scripts/test.sh
./Scripts/package.sh
open build/Lyrix.app
```

`Scripts/build.sh` runs `swift build -c release`. `Scripts/test.sh` runs `swift test` with explicit framework search paths because the Command Line Tools keep Swift Testing outside SwiftPM's default path. `Scripts/package.sh` creates the app bundle, a generated `.icns` icon, an ad-hoc signature, and `build/Lyrix-0.1.0.zip`. No asset catalog, project file, or full Xcode installation is used.

## Using Lyrix

The compact menu-bar icon opens playback controls. If macOS hides menu extras near the notch, click Lyrix in the Dock to open Settings; **Open Audio / LRC…** is available there too. **Demo** starts a simulated timeline with original sample LRC text and no audio. **Open Audio / LRC** starts at Desktop on first use, remembers the last folder, and lets you browse into any folder. Audio files play through AVFoundation. Selecting an LRC file opens a lyrics-only simulated preview. If an LRC file with the same basename sits next to selected audio, Lyrix loads it automatically. **Import LRC** also starts at Desktop. The settings window provides lyrics lookup, timing offset, visualization mode, color, font size, opacity, and overlay controls.

Spotify is observed through AppleScript for **metadata display only**. The app never uses Spotify playback position to drive lyric synchronization. macOS may ask for Automation permission when Spotify is running; the bundle provides `NSAppleEventsUsageDescription`. If permission is denied, the menu reports it. No Spotify OAuth or protected lyrics interfaces are used.

Lyrics lookup uses LRCLIB's public exact lookup when full metadata is available, then its search endpoint. Results are variable; a missing result does not imply a bug. User-selected lyrics are stored in Application Support. Network lookup is never required for local or demo playback.

## Architecture

- `LyrixCore`: LRC parsing, timeline lookup, provider protocol, LRCLIB client, matching, cache, Spotify metadata types.
- `LyrixApp`: menu-bar UI, settings, AVFoundation playback, AppleScript monitor, AppKit overlay, nine visualization layouts.
- `Scripts`: SwiftPM build/test and `.app` packaging.

## Manual QA

1. Launch the app and confirm `✦ Lyrix` appears in the menu bar and the transparent overlay appears.
2. Start demo playback, pause, seek, and switch all nine modes.
3. Import a local audio file and adjacent or separately selected LRC; seek and pause.
4. Toggle overlay visibility and click-through from the menu bar. Confirm click-through can be disabled there.
5. Move and resize the overlay, quit, relaunch, and verify the frame restores.
6. Disconnect a secondary display while the overlay is on it and check accessibility.
7. With Spotify running, check track metadata and Automation permission behavior. Verify local/demo lyrics are independent of Spotify.
8. Restart and verify visual settings persist.

## Interface

The menu popover now uses native material, a prominent playback card, a horizontal visualization selector, and grouped overlay/import actions. Settings includes a ten-mode gallery with lightweight selection cards and one live renderer preview. See CHANGELOG.md for verification limits and outstanding redesign work.

## Automatic Spotify lyrics retrieval

Spotify track-ID changes start a cancellable cache-first LRCLIB lookup. High-confidence synchronized results are cached and displayed in Settings → Lyrics. Status and retry controls are available; failed lookups are not retriggered on every poll. Retrieved documents are separate from the active local/demo document, so Spotify observations cannot reset local playback or the overlay.

Spotify playback synchronization remains disabled pending explicit permission covering this integration and applicable lyrics rights. See https://developer.spotify.com/policy and https://developer.spotify.com/compliance-tips.

The standalone PlaybackClock supports monotonic interpolation, drift correction, pause/resume, and explicit seeks. It is tested but has not replaced the existing local/demo clock yet.

## Shared playback session

All renderers now consume AppModel.timeline backed by PlaybackSession. The session owns the active lyrics and monotonic clock. Local AVAudioPlayer observations arrive at 4 Hz; the existing 30 Hz UI timer samples interpolated position. Pause, resume, seek, source activation, and document replacement use the same session.

In Settings → Lyrics, use **Simulate retrieved lyrics (no audio)** to explicitly activate the cached Spotify lyrics on an independent simulated clock. Alternatively, open local audio and choose **Use retrieved lyrics with local audio**. These actions do not read Spotify playback position.

The authorization boundary is PlaybackSession.activate/observe. Source currently permits only demo, localAudio, and simulatedSpotify. Live SpotifyReader observations feed metadata and retrieval only. An authorized Spotify adapter would need an explicit new source, track-bound activation, monotonic receipt timestamps, and observation forwarding here; it is not enabled.

Validation: 12 tests pass, including the actual local 44-line cache file supplied through LYRIX_CACHED_LYRICS. Replay observations in the test are synthetic Spotify-style records, not captured Spotify playback. Real audio device playback and the updated GUI still require interactive verification.

The independent SpotifyPlaybackAdapter is implemented and tested without enabling live synchronization. See [adapter boundary](docs/spotify-playback-adapter.md) for event semantics, required authorization, integration steps, and test limits.

Production monitoring now passes through SpotifyPlaybackForwarder and the existing adapter. A closed rendering gate preserves the active local/demo source. See docs/spotify-playback-adapter.md for the precise production path and remaining activation limitation.
