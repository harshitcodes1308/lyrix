# Implementation status

Verified on macOS 26.6.2 arm64 with Swift 6.3.3 and Xcode Command Line Tools (31 October 2026).

## Working

- SwiftPM native menu-bar executable and AppKit floating overlay.
- Compact icon-only menu item and Dock access to Settings for Macs with a notch or crowded menu bar.
- Open Audio / LRC picker starts at Desktop, remembers the last audio folder, and supports browsing into other folders. Selecting an LRC opens a lyrics-only preview.
- Demo timeline, local AVFoundation audio playback, pause, seek, LRC import, adjacent LRC discovery.
- Nine selectable visualization layouts. Minimal, Fisheye, and Visual have dedicated presentations; the remaining six have separate layouts and styles.
- Standard and enhanced LRC parsing, metadata, offsets, multiple timestamps, Unicode, sorted lines, binary-search timeline state.
- Spotify AppleScript metadata observation on a background queue, with installed/running and permission status. Spotify timing is not connected to lyric rendering.
- LRCLIB search, result selection, matching, local cache, persisted preferences.
- `swift build`, `swift test` (7 passing tests), release `.app`, icon, ad-hoc signature, zip. Packaged app was launched and its demo overlay inspected visually.

## Partial / not yet verified

- The advanced modes are functional distinct layouts, but cinematic animation, per-word progression, graph tuning, and frame pacing have not been profiled or polished to the full master prompt.
- Spotify metadata was not manually validated in the app UI against a playing track during this build. The monitor compiles and is wired to the menu.
- Multi-monitor disconnect handling, persistence after moving the overlay, settings controls, local audio playback, and online lookup need interactive QA.
- Candidate matching is basic and should be strengthened for covers, transliterations, and ambiguous releases.
- Cache stores lyrics documents, but does not yet record failed requests, manual offsets per track, or edit preservation.
- The optional Python `syncedlyrics` provider was not integrated; no Python runtime is bundled.
- Launch-at-login, per-mode settings, selectable monitor, reduced-motion coverage, and detailed performance controls remain open.

## Known limitations

- Demo is a simulated timeline, not audio playback.
- The packaging script uses local ad-hoc signing and does not notarize the app.
- Swift Testing in the Command Line Tools requires explicit framework and runtime search paths; `Scripts/test.sh` supplies them.

## Next tasks

1. Run the manual QA checklist, especially Spotify permission, local audio, and multi-monitor behavior.
2. Improve the advanced animation modes and word-level rendering.
3. Expand automated coverage of the app/UI and Spotify descriptor parsing.
4. Add robust cache records and more precise candidate matching.
