import Foundation
import Observation
import Security

/// Central app state: settings, rules, sources, news and projects. The UI and the MCP server both operate on this object.
@MainActor @Observable
public final class Library {
    public private(set) var settings = AppSettings()
    public private(set) var playbook: Playbook
    public private(set) var sources: [Source] = []
    public private(set) var news: [NewsItem] = []
    public private(set) var newsLoading = false
    public private(set) var projects: [Project] = []
    public private(set) var progress: [String: Double] = [:]
    private var playbookSaved = false

    public init() {
        Paths.ensure(Paths.root); Paths.ensure(Paths.projects)
        playbook = Playbook.defaults(language: Library.systemLanguage)
        load()
    }

    // MARK: Language
    public nonisolated static var systemLanguage: String { (Locale.preferredLanguages.first ?? "en").hasPrefix("es") ? "es" : "en" }
    public var uiLanguage: String { settings.uiLanguage ?? Library.systemLanguage }

    // MARK: Persistence
    private static let enc: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }()
    private static let dec: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    private func url(_ name: String) -> URL { Paths.root.appendingPathComponent(name) }
    private func write<T: Encodable>(_ v: T, to u: URL) { try? Library.enc.encode(v).write(to: u, options: .atomic) }
    private func read<T: Decodable>(_ t: T.Type, from u: URL) -> T? { (try? Data(contentsOf: u)).flatMap { try? Library.dec.decode(t, from: $0) } }

    private func load() {
        if let s = read(AppSettings.self, from: url("settings.json")) { settings = s }
        if let p = read(Playbook.self, from: url("playbook.json")) { playbook = p; playbookSaved = true }
        else { playbook = Playbook.defaults(language: uiLanguage) }
        sources = read([Source].self, from: url("sources.json")) ?? [
            Source(id: "s1", kind: .rss, url: "https://www.nintendolife.com/feeds/latest", label: "Nintendo Life"),
            Source(id: "s2", kind: .rss, url: "https://feeds.bbci.co.uk/news/technology/rss.xml", label: "BBC Technology")]
        let dirs = (try? FileManager.default.contentsOfDirectory(at: Paths.projects, includingPropertiesForKeys: nil)) ?? []
        projects = dirs.compactMap { read(Project.self, from: $0.appendingPathComponent("project.json")) }.sorted { $0.created > $1.created }
        if settings.mcp.token.isEmpty { updateSettings { $0.mcp.token = Library.makeToken() } }
        // a job interrupted by quitting the app cannot stay "in progress"
        for i in projects.indices where [.generating, .rendering, .fetching].contains(projects[i].status) { projects[i].status = .draft; save(projects[i]) }
    }

    nonisolated static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public func regenerateMCPToken() { updateSettings { $0.mcp.token = Library.makeToken() } }

    public func updateSettings(_ change: (inout AppSettings) -> Void) { change(&settings); write(settings, to: url("settings.json")) }

    public func setLanguage(_ code: String?) {
        updateSettings { $0.uiLanguage = code }
        if !playbookSaved { playbook = Playbook.defaults(language: uiLanguage) }   // unedited rules follow the interface language
    }

    public func savePlaybook(_ pb: Playbook) { playbook = pb; playbookSaved = true; write(pb, to: url("playbook.json")) }
    public func resetPlaybook() { try? FileManager.default.removeItem(at: url("playbook.json")); playbookSaved = false; playbook = Playbook.defaults(language: uiLanguage) }

    public func saveSources(_ s: [Source]) { sources = s; write(s, to: url("sources.json")) }
    public func addSource(kind: Source.Kind, url u: String, label: String) throws {
        let trimmed = u.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("http"), URL(string: trimmed) != nil else { throw LibraryError.invalidURL }
        saveSources(sources + [Source(kind: kind, url: trimmed, label: label)])
        news = []
    }
    public func removeSource(_ id: String) { saveSources(sources.filter { $0.id != id }); news = [] }

    // MARK: News
    public func refreshNews() async {
        newsLoading = true
        news = await Feeds.fetchAll(sources)
        newsLoading = false
    }

    // MARK: Projects
    public func project(_ id: String) -> Project? { projects.first { $0.id == id } }
    public func playbook(for p: Project) -> Playbook { playbook.effective(for: p.platform) }

    private func save(_ p: Project) { Paths.ensure(Paths.project(p.id)); write(p, to: Paths.project(p.id).appendingPathComponent("project.json")) }

    @discardableResult
    private func mutate(_ id: String, _ change: (inout Project) -> Void) -> Project? {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return nil }
        change(&projects[i]); save(projects[i]); return projects[i]
    }

    /// Creates the project and asks the configured agent for the script.
    @discardableResult
    public func createProject(news item: NewsItem, platform: Platform? = nil, generate: Bool = true) -> Project {
        var p = Project(news: item, platform: platform ?? playbook.platform, lang: uiLanguage)
        p.status = generate ? .generating : .draft
        projects.insert(p, at: 0); save(p)
        if generate { runGenerate(p.id, feedback: nil) }
        return p
    }

    public func regenerate(_ id: String, feedback: String?) { runGenerate(id, feedback: feedback) }

    private func runGenerate(_ id: String, feedback: String?) {
        guard let p = project(id) else { return }
        mutate(id) { $0.status = .generating; $0.error = nil }
        let pb = playbook(for: p), s = settings.agent, key = Secrets.get(.agentKey), news = p.news
        Task {
            do {
                let (d, problems) = try await AgentService.generate(settings: s, apiKey: key, playbook: pb, news: news, feedback: feedback)
                mutate(id) { $0.title = d.title.isEmpty ? $0.title : d.title; $0.hook = d.hook; $0.script = d.script; $0.clipQuery = d.clipQuery
                    $0.problems = problems; $0.hasVideo = false; $0.status = .draft }
            } catch { mutate(id) { $0.status = .error; $0.error = error.localizedDescription } }
        }
    }

    /// Manual or MCP edit. Returns the validation problems of the resulting text.
    @discardableResult
    public func edit(_ id: String, title: String? = nil, hook: String? = nil, script: String? = nil, clipQuery: String? = nil, platform: Platform? = nil) -> [Problem] {
        let p = mutate(id) { p in
            if let v = title, v != p.title { p.title = v; p.hasVideo = false }
            if let v = hook, v != p.hook { p.hook = v; p.hasVideo = false }
            if let v = script, v != p.script { p.script = v; p.hasVideo = false }
            if let v = clipQuery { p.clipQuery = v }
            if let v = platform, v != p.platform { p.platform = v; p.hasVideo = false }
        }
        guard let p else { return [] }
        let problems = Rules.validate(hook: p.hook, script: p.script, playbook: playbook(for: p))
        mutate(id) { $0.problems = problems }
        return problems
    }

    public func deleteProject(_ id: String) {
        projects.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Paths.project(id))
    }

    // MARK: Background
    public func setBackground(_ id: String, file: URL) throws {
        let ext = file.pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "m4v"].contains(ext)
        let dir = Paths.project(id)
        for old in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where old.lastPathComponent.hasPrefix("custom_bg") { try? FileManager.default.removeItem(at: old) }
        let dest = dir.appendingPathComponent("custom_bg" + (ext.isEmpty ? "" : "." + ext))
        let scoped = file.startAccessingSecurityScopedResource(); defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: file, to: dest)
        mutate(id) { $0.bgImage = isVideo ? nil : dest.path; $0.bgVideo = isVideo ? dest.path : nil; $0.stockCredit = nil; $0.hasVideo = false }
    }

    /// Downloads an image or video from a URL (https) as the background; used by MCP agents.
    public func setBackground(_ id: String, remote: URL) async throws {
        guard remote.scheme == "https" || remote.scheme == "http" else { throw LibraryError.invalidURL }
        var req = URLRequest(url: remote, timeoutInterval: 120); req.setValue(Feeds.userAgent, forHTTPHeaderField: "User-Agent")
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let mime = (resp.mimeType ?? "").lowercased()
        let ext = mime.hasPrefix("video/") ? "mp4" : (mime.hasPrefix("image/") ? "jpg" : remote.pathExtension)
        let named = tmp.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + "." + ext)
        try FileManager.default.moveItem(at: tmp, to: named)
        defer { try? FileManager.default.removeItem(at: named) }
        try setBackground(id, file: named)
    }

    public func clearBackground(_ id: String) {
        mutate(id) { $0.bgImage = nil; $0.bgVideo = nil; $0.stockCredit = nil; $0.imageURL = nil; $0.hasVideo = false }
    }

    public func findStock(_ id: String, query: String? = nil) {
        guard let p = project(id) else { return }
        mutate(id) { $0.status = .fetching; $0.error = nil }
        let key = Secrets.get(.pexelsKey), q = (query?.isEmpty == false ? query! : (p.clipQuery.isEmpty ? p.title : p.clipQuery)), platform = p.platform
        Task {
            do {
                let hit = try await Stock.find(apiKey: key, query: q, platform: platform)
                let dest = Paths.project(id).appendingPathComponent("stock.mp4")
                try await Stock.download(hit.url, to: dest)
                mutate(id) { $0.bgImage = nil; $0.bgVideo = dest.path; $0.stockCredit = StockCredit(author: hit.author, page: hit.page); $0.hasVideo = false; $0.status = .draft }
            } catch { mutate(id) { $0.status = .error; $0.error = error.localizedDescription } }
        }
    }

    // MARK: Render
    public func videoURL(_ id: String) -> URL? {
        let u = Paths.project(id).appendingPathComponent("video.mp4")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    func resolveBackground(_ p: Project) async -> RenderBackground {
        if let v = p.bgVideo, FileManager.default.fileExists(atPath: v) { return .video(URL(fileURLWithPath: v)) }
        if let i = p.bgImage, let img = Renderer.loadImage(at: URL(fileURLWithPath: i)) { return .image(img) }
        if let s = p.imageURL, let u = URL(string: s) {
            var req = URLRequest(url: u, timeoutInterval: 20); req.setValue(Feeds.userAgent, forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 {
                let f = Paths.project(p.id).appendingPathComponent("article_image")
                try? data.write(to: f)
                if let img = Renderer.loadImage(at: f) { return .image(img) }
            }
        }
        return .color
    }

    public func render(_ id: String) {
        guard let p = project(id) else { return }
        mutate(id) { $0.status = .rendering; $0.error = nil }
        progress[id] = 0
        let pb = playbook(for: p), vs = settings.voice, key = Secrets.get(.voiceKey)
        Task {
            do {
                let spoken = [p.hook, p.script, pb.outro].filter { !$0.isEmpty }.joined(separator: " ")
                let voice = try await VoiceService.synthesize(text: spoken, language: pb.language, voiceName: pb.voice, settings: vs, apiKey: key, into: Paths.project(id))
                let bg = await resolveBackground(p)
                let out = Paths.project(id).appendingPathComponent("video.mp4")
                try await Renderer.render(RenderRequest(title: p.title, words: voice.words, audio: voice.url, duration: voice.duration, platform: p.platform, background: bg, output: out)) { v in
                    Task { @MainActor in self.progress[id] = v }
                }
                mutate(id) { $0.hasVideo = true; $0.duration = voice.duration + 0.5; $0.renderedAt = Date(); $0.status = .ready; $0.problems = Rules.validate(hook: $0.hook, script: $0.script, playbook: pb) }
            } catch { mutate(id) { $0.status = .error; $0.error = error.localizedDescription } }
            progress[id] = nil
        }
    }

    /// Waits for a project's current job to finish (for synchronous MCP tools).
    public func waitUntilIdle(_ id: String, timeout: TimeInterval = 180) async -> Project? {
        let end = Date().addingTimeInterval(timeout)
        while let p = project(id), [.generating, .rendering, .fetching].contains(p.status), Date() < end { try? await Task.sleep(nanoseconds: 300_000_000) }
        return project(id)
    }
}

public enum LibraryError: LocalizedError {
    case invalidURL, notFound
    public var errorDescription: String? { self == .invalidURL ? "invalid_url" : "not_found" }
}
