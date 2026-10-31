import AppKit
import SwiftUI
import LyrixCore

struct MenuView: View {
    @ObservedObject var model: AppModel
    let showOverlay: () -> Void
    let showSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "waveform").foregroundStyle(LyrixDesign.accent)
                Text("lyrix").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Text(model.isPlaying ? "PLAYING" : "PAUSED").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                Button(action: showSettings) { Image(systemName: "slider.horizontal.3") }.buttonStyle(.plain).help("Settings")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(model.isDemo ? "LYRICS TIMELINE" : "LOCAL AUDIO").font(.system(size: 9, weight: .bold)).tracking(1.6).foregroundStyle(LyrixDesign.accent)
                Text(model.document.metadata["ti"] ?? model.sourceLabel).font(.system(size: 22, weight: .semibold)).lineLimit(2)
                Text(model.document.metadata["ar"] ?? "Your words, your space.").font(.callout).foregroundStyle(.secondary)
                Slider(value: Binding(get: { model.position }, set: { model.seek($0) }), in: 0...max(1, model.duration)).tint(LyrixDesign.accent)
                HStack {
                    Text(time(model.position))
                    Spacer()
                    Button { model.playPause() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 26, height: 26) }.buttonStyle(LyrixButtonStyle(prominent: true)).accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                    Spacer()
                    Text(time(model.duration))
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(18).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: LyrixDesign.radius))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppModel.modes, id: \.self) { mode in
                        Button { model.preferences.mode = mode } label: { Label(mode, systemImage: LyrixDesign.icon(mode)).font(.caption.weight(.medium)) }.buttonStyle(LyrixButtonStyle(prominent: model.preferences.mode == mode))
                    }
                }
            }
            HStack {
                Button(model.preferences.showOverlay ? "Hide Overlay" : "Show Overlay", action: showOverlay).buttonStyle(LyrixButtonStyle(prominent: true))
                Spacer()
                Button { model.importAudio() } label: { Image(systemName: "folder") }.help("Open audio or LRC").buttonStyle(LyrixButtonStyle())
                Button { model.importLyrics() } label: { Image(systemName: "text.badge.plus") }.help("Import lyrics").buttonStyle(LyrixButtonStyle())
            }
            Toggle("Click through overlay", isOn: $model.preferences.clickThrough).font(.caption).toggleStyle(.switch).controlSize(.mini)
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Spotify · metadata only").font(.caption.weight(.semibold))
                    Text(model.spotifyLyricsStatus).font(.caption2).foregroundStyle(.secondary)
                    Text(model.spotifyTrack.map { "\($0.title) · \($0.artist)" } ?? model.spotifyStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Demo") { model.useDemo() }.buttonStyle(.plain).font(.caption)
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.plain).help("Quit Lyrix")
            }
        }.padding(22).frame(width: 390).background(.regularMaterial)
    }
    private func time(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(max(0, seconds)) / 60, Int(max(0, seconds)) % 60)

    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        TabView {
            VisualizationGallery(model: model).tabItem { Label("Gallery", systemImage: "square.grid.2x2") }
            Form {
                Text("Local audio and demo playback drive synchronized visualizations. Spotify is shown as metadata only.").font(.callout)
                Button("Open Audio / LRC…") { model.importAudio() }
                Button("Use Demo Timeline") { model.useDemo() }
                Text("Source: \(model.sourceLabel)")
                Text("Spotify: \(model.spotifyStatus)")
            }.tabItem { Label("General", systemImage: "gear") }
            Form {
                Button("Import LRC…") { model.importLyrics() }
                Button("Search LRCLIB") { model.searchLyrics() }
                Text("Spotify: \(model.spotifyLyricsStatus)")
                Text("Spotify playback synchronization awaits authorization.").font(.caption).foregroundStyle(.secondary)
                Button("Retry Spotify lyrics lookup") { model.retrySpotifyLyrics() }
                if let lyrics = model.spotifyLyrics {
                    Button("Simulate retrieved lyrics (no audio)") { model.simulateRetrievedLyrics() }
                    Button("Use retrieved lyrics with local audio") { model.useRetrievedLyricsForLocalAudio() }.disabled(model.isDemo)
                    DisclosureGroup("Retrieved Spotify lyrics") {
                        ScrollView { Text(lyrics.lines.map(\.text).joined(separator: "\n")).textSelection(.enabled) }.frame(height: 140)
                    }
                }
                HStack { Text("Timing offset"); Slider(value: $model.preferences.offset, in: -10...10); Text(String(format: "%+.1fs", model.preferences.offset)).monospacedDigit() }
                Text("Lyrics source: \(model.document.source)")
                Text("\(model.document.lines.count) synchronized lines")
                if !model.candidates.isEmpty {
                    Text("Search results").font(.headline)
                    ForEach(model.candidates) { candidate in
                        Button("\(candidate.track.title) — \(candidate.track.artist)") { model.selectCandidate(candidate) }
                    }
                }
                if let message = model.message { Text(message).foregroundStyle(.orange) }
            }.tabItem { Label("Lyrics", systemImage: "text.quote") }
            Form {
                Picker("Visualization", selection: $model.preferences.mode) { ForEach(AppModel.modes, id: \.self) { Text($0) } }
                HStack { Text("Font size"); Slider(value: $model.preferences.fontSize, in: 18...72); Text("\(Int(model.preferences.fontSize))") }
                Picker("Highlight", selection: $model.preferences.highlight) { Text("Blue").tag("blue"); Text("Amber").tag("amber"); Text("Rose").tag("rose"); Text("Violet").tag("violet"); Text("White").tag("white") }
                Toggle("Reduce motion", isOn: $model.preferences.reducedMotion)
                OverlayView(model: model).frame(height: 190).background(.black.opacity(0.9)).clipShape(RoundedRectangle(cornerRadius: 14))
            }.tabItem { Label("Visual", systemImage: "sparkles") }
            Form {
                Toggle("Show overlay", isOn: $model.preferences.showOverlay)
                Toggle("Always on top", isOn: $model.preferences.alwaysOnTop)
                Toggle("Click through", isOn: $model.preferences.clickThrough)
                HStack { Text("Opacity"); Slider(value: $model.preferences.opacity, in: 0.2...1) }
                Text("Use the menu-bar control to regain overlay interaction when click through is on.").font(.caption)
            }.tabItem { Label("Overlay", systemImage: "rectangle.on.rectangle") }
        }
        .padding(18).frame(width: 760, height: 580)
    }
}

struct OverlayView: View {
    @ObservedObject var model: AppModel
    private var state: TimelineState { model.timeline }
    private var color: Color {
        switch model.preferences.highlight { case "amber": return .orange; case "rose": return .pink; case "violet": return .purple; case "white": return .white; default: return .cyan }
    }
    private var active: String { state.active?.text.isEmpty == false ? state.active!.text : "LYRIX — Waiting for lyrics" }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                content(size: geometry.size)
                    .padding(24)
                    .shadow(color: .black.opacity(0.85), radius: 4, y: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(model.preferences.reducedMotion ? nil : .easeInOut(duration: 0.35), value: state.index)
            .animation(model.preferences.reducedMotion ? nil : .easeInOut(duration: 0.3), value: model.preferences.mode)
        }
        .accessibilityLabel(active)
    }
    @ViewBuilder private func content(size: CGSize) -> some View {
        switch model.preferences.mode {
        case "Kinetic Word":
            let words = state.active?.words ?? []
            let index = state.wordIndex ?? 0
            Text(words.indices.contains(index) ? words[index].text : active)
                .font(.system(size: model.preferences.fontSize * 1.7, weight: .bold, design: .rounded))
                .foregroundStyle(color).minimumScaleFactor(0.3).lineLimit(1)
                .id("\(state.index ?? -1)-\(index)")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        case "Fisheye":
            VStack(spacing: 13) { line(state.previous?.text, scale: 0.58, alpha: 0.4); line(active, scale: 1.3, alpha: 1); line(state.next?.text, scale: 0.58, alpha: 0.4) }
        case "Visual":
            ZStack { Circle().fill(color.opacity(0.17)).blur(radius: 55).frame(width: 210); Text(active).font(.system(size: model.preferences.fontSize * 1.35, weight: .bold, design: .serif)).foregroundStyle(.white).shadow(color: color.opacity(0.8), radius: 24).multilineTextAlignment(.center) }
        case "Fisheye Visual":
            ZStack { Circle().fill(color.opacity(0.14)).blur(radius: 45).frame(width: 200); VStack(spacing: 14) { line(state.previous?.text, scale: 0.48, alpha: 0.25); line(active, scale: 1.25, alpha: 1).shadow(color: color, radius: 18); line(state.next?.text, scale: 0.48, alpha: 0.25) } }
        case "Codestyle":
            VStack(alignment: .leading, spacing: 12) { codeLine(state.previous?.text, number: (state.index ?? 0), active: false); codeLine(active, number: (state.index ?? 0) + 1, active: true); codeLine(state.next?.text, number: (state.index ?? 0) + 2, active: false) }.frame(maxWidth: .infinity, alignment: .leading)
        case "Codestyle Visual":
            VStack(alignment: .leading, spacing: 10) { Text("LYRIX / NOW PLAYING").font(.system(size: 11, design: .monospaced)).foregroundStyle(color.opacity(0.7)); Rectangle().fill(color.opacity(0.3)).frame(height: 1); Text("› " + active + " ▌").font(.system(size: model.preferences.fontSize * 0.85, weight: .medium, design: .monospaced)).foregroundStyle(color).shadow(color: color, radius: 12); Text("// " + (state.next?.text ?? "")).font(.system(size: 14, design: .monospaced)).foregroundStyle(.white.opacity(0.35)) }.frame(maxWidth: .infinity, alignment: .leading)
        case "Branches":
            ZStack { Path { p in p.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.5)); p.addLine(to: CGPoint(x: size.width * 0.19, y: size.height * 0.2)); p.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.5)); p.addLine(to: CGPoint(x: size.width * 0.81, y: size.height * 0.8)) }.stroke(color.opacity(0.45), lineWidth: 2); Text(state.previous?.text ?? "").font(.caption).foregroundStyle(.white.opacity(0.45)).position(x: size.width * 0.19, y: size.height * 0.18); Text(active).font(.system(size: model.preferences.fontSize * 0.8, weight: .bold)).foregroundStyle(color).position(x: size.width * 0.5, y: size.height * 0.5); Text(state.next?.text ?? "").font(.caption).foregroundStyle(.white.opacity(0.45)).position(x: size.width * 0.81, y: size.height * 0.78) }
        case "Web":
            graph(size: size, star: false)
        case "Constellation":
            graph(size: size, star: true)
        default:
            VStack(spacing: 13) { line(state.previous?.text, scale: 0.65, alpha: 0.4); line(active, scale: 1, alpha: 1); line(state.next?.text, scale: 0.65, alpha: 0.4) }
        }
    }
    private func line(_ text: String?, scale: Double, alpha: Double) -> some View {
        Text(text ?? " ").font(.system(size: model.preferences.fontSize * scale, weight: alpha == 1 ? .bold : .medium, design: .rounded)).foregroundStyle(alpha == 1 ? color : .white.opacity(alpha)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.5).frame(maxWidth: .infinity)
    }
    private func codeLine(_ text: String?, number: Int, active: Bool) -> some View {
        HStack { Text(String(format: "%02d", number)).foregroundStyle(.white.opacity(0.35)); Text(text ?? " ").foregroundStyle(active ? color : .white.opacity(0.45)) }.font(.system(size: active ? model.preferences.fontSize * 0.8 : 16, weight: active ? .bold : .regular, design: .monospaced)).lineLimit(2).minimumScaleFactor(0.5)
    }
    private func graphPoint(_ i: Int, size: CGSize) -> CGPoint {
        let x = 25 + (size.width - 50) * CGFloat((i * 37) % 101) / 101
        let y = 20 + (size.height - 40) * CGFloat((i * 53 + 19) % 97) / 97
        return CGPoint(x: x, y: y)
    }
    private func graph(size: CGSize, star: Bool) -> some View {
        let previousWords = Array((state.previous?.text ?? "").split(separator: " ").suffix(3)).map { String($0) }
        let activeWords = active.split(separator: " ").map { String($0) }
        let nextWords = Array((state.next?.text ?? "").split(separator: " ").prefix(3)).map { String($0) }
        let tokens = previousWords + activeWords + nextWords
        return ZStack {
            Canvas { context, canvasSize in
                let count = max(1, tokens.count)
                let pts = (0..<count).map { graphPoint($0, size: canvasSize) }
                for i in 0..<max(0, count - 1) { var path = Path(); path.move(to: pts[i]); path.addLine(to: pts[i + 1]); context.stroke(path, with: .color(color.opacity(star ? 0.27 : 0.5)), lineWidth: 1) }
                if star { for p in pts { context.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.75))) } }
            }
            ForEach(Array(tokens.enumerated()), id: \.offset) { i, word in
                let isActive = i >= previousWords.count && i < previousWords.count + activeWords.count
                Text(word).font(.system(size: isActive ? (star ? 16 : 19) : 12, weight: isActive ? .bold : .regular, design: star ? .serif : .rounded)).foregroundStyle(isActive ? color : .white.opacity(0.45)).shadow(color: isActive ? color : .clear, radius: star ? 12 : 0)
                    .position(graphPoint(i, size: size))
            }
        }
    }
}
