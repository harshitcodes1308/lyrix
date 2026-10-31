import SwiftUI

enum LyrixDesign {
    static let accent = Color(red: 0.38, green: 0.85, blue: 0.94)
    static let surface = Color(red: 0.09, green: 0.10, blue: 0.13)
    static let radius: CGFloat = 16
    static func icon(_ mode: String) -> String {
        switch mode {
        case "Minimal": return "text.aligncenter"
        case "Fisheye", "Fisheye Visual": return "circle.lefthalf.filled"
        case "Visual": return "sun.max"
        case "Codestyle", "Codestyle Visual": return "chevron.left.forwardslash.chevron.right"
        case "Branches": return "point.3.connected.trianglepath.dotted"
        case "Web": return "network"
        case "Constellation": return "sparkles"
        default: return "textformat.size.larger"
        }
    }
}

struct LyrixButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(prominent ? Color.black : Color.primary)
            .background(prominent ? LyrixDesign.accent : Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 10))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct VisualizationGallery: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Find your rhythm").font(.title2.bold())
                Text("Ten ways to see the same words.").foregroundStyle(.secondary)
                OverlayView(model: model).frame(height: 180)
                    .background(LyrixDesign.surface, in: RoundedRectangle(cornerRadius: 18))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                    ForEach(AppModel.modes, id: \.self) { mode in
                        Button { model.preferences.mode = mode } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: LyrixDesign.icon(mode)).font(.title2).foregroundStyle(LyrixDesign.accent)
                                    Spacer()
                                    if model.preferences.mode == mode { Image(systemName: "checkmark.circle.fill").foregroundStyle(LyrixDesign.accent) }
                                }
                                Text(mode).font(.headline)
                                Text(mode.contains("Code") ? "Precision in every line" : mode == "Kinetic Word" ? "One word. Full focus." : "Typography in motion").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(Color.primary.opacity(model.preferences.mode == mode ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).accessibilityLabel("Select \(mode)")
                    }
                }
            }.padding(18)
        }
    }
}
