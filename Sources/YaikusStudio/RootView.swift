import SwiftUI
import YaikusCore

enum Section: String, CaseIterable, Identifiable {
    case news, videos, sources, rules, agent, voice, connect
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .news: return "newspaper"; case .videos: return "film.stack"; case .sources: return "link"; case .rules: return "list.bullet.rectangle"
        case .agent: return "sparkles"; case .voice: return "waveform"; case .connect: return "point.3.connected.trianglepath.dotted"
        }
    }
}

@MainActor struct RootView: View {
    @Environment(Library.self) private var lib
    @State private var section: Section? = .news
    @State private var selectedProject: String?
    @State private var update: Updates.Info?
    @State private var visibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        // reading the language here makes the whole interface redraw when it changes
        let _ = Strings.shared.code
        NavigationSplitView(columnVisibility: $visibility) {
            List(Section.allCases, selection: $section) { s in
                Label {
                    HStack { Text(t("nav." + s.rawValue)); if s == .videos, !lib.projects.isEmpty { Spacer(); Text("\(lib.projects.count)").font(.caption).foregroundStyle(.secondary) } }
                } icon: { Image(systemName: s.icon) }
                .tag(s)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) { LanguageMenu().padding(10) }
        } detail: {
            VStack(spacing: 0) {
                if let u = update, u.isNewer {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(t("update.available", ["v": u.latest ?? "", "cur": u.current]))
                        Link(t("update.get"), destination: u.url)
                        Spacer()
                    }
                    .padding(10).background(Color.accentColor.opacity(0.15))
                }
                Group {
                    switch section ?? .news {
                    case .news: NewsView(openProject: { id in selectedProject = id; section = .videos })
                    case .videos: VideosView(selected: $selectedProject)
                    case .sources: SourcesView()
                    case .rules: RulesView()
                    case .agent: AgentView()
                    case .voice: VoiceView()
                    case .connect: ConnectView()
                    }
                }
            }
        }
        .task {
            Strings.shared.code = lib.uiLanguage
            if lib.settings.checkUpdates { update = await Updates.check() }
        }
        .onChange(of: lib.uiLanguage) { _, new in Strings.shared.code = new }
    }
}

@MainActor struct LanguageMenu: View {
    @Environment(Library.self) private var lib
    var body: some View {
        Picker(selection: Binding(get: { lib.settings.uiLanguage ?? "system" }, set: { lib.setLanguage($0 == "system" ? nil : $0) })) {
            Text("English").tag("en"); Text("Español").tag("es"); Text(t("lang.system")).tag("system")
        } label: { Image(systemName: "globe") }
        .pickerStyle(.menu).labelsHidden()
    }
}
