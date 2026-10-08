import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers
import YaikusCore

@MainActor struct VideosView: View {
    @Environment(Library.self) private var lib
    @Binding var selected: String?

    var body: some View {
        let _ = Strings.shared.code
        HStack(spacing: 0) {
            List(lib.projects, selection: $selected) { p in
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.title).font(.headline).lineLimit(2)
                    HStack { StatusBadge(status: p.status); Text(t("plat." + p.platform.rawValue)).font(.caption).foregroundStyle(.tertiary) }
                }.padding(.vertical, 3).tag(p.id)
            }
            .frame(width: 260)
            .overlay { if lib.projects.isEmpty { Text(t("videos.none")).foregroundStyle(.secondary) } }
            Divider()
            Group {
                if let id = selected, lib.project(id) != nil { ProjectEditor(id: id).id(id) }
                else { ContentUnavailableView(t("videos.empty"), systemImage: "film") }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(t("nav.videos"))
    }
}

@MainActor struct ProjectEditor: View {
    @Environment(Library.self) private var lib
    let id: String
    @State private var title = ""
    @State private var hook = ""
    @State private var script = ""
    @State private var synced = (title: "", hook: "", script: "")
    @State private var feedback = ""
    @State private var importing = false
    @State private var confirmDelete = false
    @State private var flash: String?

    var p: Project { lib.project(id) ?? Project(news: NewsItem(title: "", summary: "", url: "", source: ""), platform: .tiktok, lang: "en") }
    var busy: Bool { [.generating, .rendering, .fetching].contains(p.status) }
    var effective: Playbook { lib.playbook(for: p) }
    var problems: [Problem] { Rules.validate(hook: hook, script: script, playbook: effective) }

    var body: some View {
        let _ = Strings.shared.code
        let wide = p.platform.orientation == .horizontal
        ScrollView {
            if wide { VStack(alignment: .leading, spacing: 18) { preview; form }.padding(22) }
            else { HStack(alignment: .top, spacing: 22) { form; preview.frame(width: 300) }.padding(22) }
        }
        .task(id: id) { load() }
        .onChange(of: p.title) { _, n in if title == synced.title { title = n }; synced.title = n }
        .onChange(of: p.hook) { _, n in if hook == synced.hook { hook = n }; synced.hook = n }
        .onChange(of: p.script) { _, n in if script == synced.script { script = n }; synced.script = n }
        .onDisappear { commit() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie]) { r in
            if case .success(let u) = r { try? lib.setBackground(id, file: u) }
        }
        .confirmationDialog(t("editor.delete") + "?", isPresented: $confirmDelete) {
            Button(t("editor.delete"), role: .destructive) { lib.deleteProject(id) }
        }
    }

    func load() { title = p.title; hook = p.hook; script = p.script; synced = (p.title, p.hook, p.script) }
    func commit() { lib.edit(id, title: title, hook: hook, script: script); synced = (title, hook, script) }

    var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.news.title).font(.headline)
                    HStack(spacing: 6) {
                        Text(p.news.source).foregroundStyle(.secondary)
                        if let u = URL(string: p.news.url), p.news.url.hasPrefix("http") { Link(t("editor.openNote"), destination: u) }
                    }.font(.caption)
                }
                Spacer(); StatusBadge(status: p.status)
            }
            if let e = p.error { Text(errorText(e)).foregroundStyle(.red).font(.callout) }

            Field(label: t("editor.format")) {
                Picker("", selection: Binding(get: { p.platform }, set: { commit(); lib.edit(id, platform: $0) })) {
                    ForEach(Platform.allCases, id: \.self) { Text(platformName($0)).tag($0) }
                }.labelsHidden().fixedSize()
            }
            Field(label: t("editor.title")) { TextField("", text: $title).textFieldStyle(.roundedBorder) }
            Field(label: t("editor.hook")) { TextField("", text: $hook).textFieldStyle(.roundedBorder) }
            Field(label: t("editor.script")) {
                TextEditor(text: $script).font(.body).frame(minHeight: 150).scrollContentBackground(.hidden)
                    .padding(6).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                let n = Rules.wordCount(script)
                Text(t("editor.words", ["n": n])).font(.caption).foregroundStyle(n < effective.minWords || n > effective.maxWords ? .red : .secondary).frame(maxWidth: .infinity, alignment: .trailing)
            }
            ForEach(Array(problems.enumerated()), id: \.offset) { _, pr in Label(problemText(pr), systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }

            Field(label: t("editor.background")) {
                HStack(spacing: 8) {
                    Text(bgLabel).font(.callout)
                    if let c = p.stockCredit, let u = URL(string: c.page) { Link(t("bg.credit", ["author": c.author.isEmpty ? "Pexels" : c.author]), destination: u).font(.caption) }
                }
                HStack {
                    Button(t("editor.upload")) { importing = true }
                    Button(t("editor.stock")) { commit(); lib.findStock(id) }
                    if p.background != .none { Button(t("editor.noBg"), role: .destructive) { lib.clearBackground(id) } }
                }.disabled(busy)
            }

            Field(label: t("editor.askChanges")) {
                HStack {
                    TextField(t("editor.askPlaceholder"), text: $feedback).textFieldStyle(.roundedBorder)
                    Button(t("editor.regenerate")) { commit(); lib.regenerate(id, feedback: feedback.isEmpty ? nil : feedback) }.disabled(busy)
                }
            }

            HStack {
                Button(p.hasVideo ? t("editor.rerender") : t("editor.render")) { commit(); lib.render(id) }
                    .buttonStyle(.borderedProminent).disabled(busy || script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: { Label(t("editor.delete"), systemImage: "trash") }.disabled(busy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var bgLabel: String {
        switch p.background { case .none: return t("bg.none"); case .article: return t("bg.article"); case .image: return t("bg.image"); case .video: return t("bg.video"); case .stock: return t("bg.stock") }
    }

    @ViewBuilder var preview: some View {
        VStack(spacing: 10) {
            if p.status == .rendering {
                VStack(spacing: 8) { ProgressView(value: lib.progress[id] ?? 0); Text(t("status.rendering")).font(.caption).foregroundStyle(.secondary) }.padding(30)
            } else if p.hasVideo, let url = lib.videoURL(id) {
                PlayerView(url: url).id(p.renderedAt)
                    .aspectRatio(CGFloat(p.platform.width) / CGFloat(p.platform.height), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10)).frame(maxHeight: p.platform.orientation == .vertical ? 540 : 360)
                HStack {
                    Button(t("editor.export")) { export(url) }
                    Button(t("editor.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }.controlSize(.small)
            } else {
                Text(t("editor.noVideo")).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(30)
                    .frame(maxWidth: .infinity).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    func export(_ url: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = p.title.replacingOccurrences(of: "/", with: "-") + ".mp4"
        if panel.runModal() == .OK, let dest = panel.url { try? FileManager.default.removeItem(at: dest); try? FileManager.default.copyItem(at: url, to: dest) }
    }
}

/// Native player (AppKit's AVPlayerView). SwiftUI's `VideoPlayer` is avoided: it crashes when instantiated in this app.
@MainActor struct PlayerView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .inline
        v.player = AVPlayer(url: url)
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {
        if ((v.player?.currentItem?.asset) as? AVURLAsset)?.url != url { v.player = AVPlayer(url: url) }
    }
    static func dismantleNSView(_ v: AVPlayerView, coordinator: ()) { v.player?.pause(); v.player = nil }
}
