import Foundation

/// MCP (Model Context Protocol) server: lets any agent (Claude, OpenClaw, Hermes, Grok bots…) drive the app.
/// This layer is only the JSON-RPC protocol and the tools; the HTTP transport lives in MCPServer.
public final class MCPHandler: @unchecked Sendable {
    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    let library: Library
    public init(library: Library) { self.library = library }

    // MARK: JSON-RPC
    /// Handles a JSON-RPC body (single message or batch). nil = notifications only (reply 202).
    public func handle(_ body: Data) async -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: body) else { return Self.encode(Self.error(nil, -32700, "Parse error")) }
        if let batch = obj as? [[String: Any]] {
            var out: [[String: Any]] = []
            for m in batch { if let r = await handleOne(m) { out.append(r) } }
            return out.isEmpty ? nil : try? JSONSerialization.data(withJSONObject: out)
        }
        guard let msg = obj as? [String: Any] else { return Self.encode(Self.error(nil, -32600, "Invalid Request")) }
        return await handleOne(msg).flatMap(Self.encode)
    }

    static func encode(_ o: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: o) }
    static func error(_ id: Any?, _ code: Int, _ msg: String) -> [String: Any] { ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": msg]] }
    static func ok(_ id: Any, _ result: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }

    func handleOne(_ m: [String: Any]) async -> [String: Any]? {
        guard let method = m["method"] as? String else { return nil }          // client responses are ignored
        guard let id = m["id"] else { return nil }                              // notification: no reply
        let params = m["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            let version = Self.supportedVersions.contains(asked) ? asked : Self.supportedVersions[0]
            return Self.ok(id, ["protocolVersion": version, "capabilities": ["tools": ["listChanged": false]],
                                "serverInfo": ["name": "yaikus-studio", "title": "Yaikus Studio", "version": Updates.currentVersion],
                                "instructions": Self.instructions])
        case "ping": return Self.ok(id, [:])
        case "tools/list": return Self.ok(id, ["tools": Self.tools])
        case "tools/call":
            guard let name = params["name"] as? String else { return Self.error(id, -32602, "Missing tool name") }
            let args = params["arguments"] as? [String: Any] ?? [:]
            guard Self.tools.contains(where: { ($0["name"] as? String) == name }) else { return Self.error(id, -32602, "Unknown tool: \(name)") }
            let (text, isError) = await call(name, args)
            return Self.ok(id, ["content": [["type": "text", "text": text]], "isError": isError])
        default: return Self.error(id, -32601, "Method not found: \(method)")
        }
    }

    // MARK: Tools
    static let instructions = """
    Yaikus Studio turns news into short videos. Typical flow: list_news → get_rules → create_project (news_url) → write the script following the rules → \
    submit_script (fix and resubmit until ok=true) → optionally find_stock_footage / set_background_url → render_video. \
    The user decides where to publish the video; you only produce it.
    """

    static func tool(_ name: String, _ desc: String, _ props: [String: [String: Any]] = [:], required: [String] = []) -> [String: Any] {
        ["name": name, "description": desc, "inputSchema": ["type": "object", "properties": props, "required": required]]
    }
    static let str: [String: Any] = ["type": "string"]
    static let platformEnum: [String: Any] = ["type": "string", "enum": Platform.allCases.map(\.rawValue), "description": "Target format. vertical: tiktok, reels, shorts. horizontal: youtube."]

    static let tools: [[String: Any]] = [
        tool("list_news", "List the news stories collected from the user's sources (RSS feeds and links).",
             ["refresh": ["type": "boolean", "description": "Re-read the sources first (default false)."]]),
        tool("get_rules", "Get the user's rules (playbook): style instructions, word limits, banned phrases, language and target platform. Your script MUST follow them; they are validated automatically."),
        tool("create_project", "Start a video for a news story. Use news_url from list_news, or pass title+summary+url for a story you found yourself. The app's own AI is NOT used: you write the script and send it with submit_script.",
             ["news_url": str, "title": str, "summary": str, "platform": platformEnum]),
        tool("submit_script", "Set the title, hook and script of a project. The text is validated against the rules; if ok is false, fix the listed problems and submit again.",
             ["project_id": str, "title": ["type": "string", "description": "Short title shown on top of the video (max ~6 words)."],
              "hook": ["type": "string", "description": "First spoken sentence."], "script": ["type": "string", "description": "Narration."],
              "clip_query": ["type": "string", "description": "Search query for background footage (optional)."]],
             required: ["project_id", "script"]),
        tool("get_project", "Get a project's current state: texts, validation problems, status and video path when rendered.", ["project_id": str], required: ["project_id"]),
        tool("list_projects", "List all projects with their status."),
        tool("find_stock_footage", "Search royalty-free stock video (Pexels) and use it as the background. Requires the user's Pexels key.",
             ["project_id": str, "query": str], required: ["project_id"]),
        tool("set_background_url", "Use an image or video from an https URL as the background. Only use media you are allowed to use.",
             ["project_id": str, "url": str], required: ["project_id", "url"]),
        tool("set_platform", "Change the target format of a project (the video must be rendered again).", ["project_id": str, "platform": platformEnum], required: ["project_id", "platform"]),
        tool("render_video", "Render the project to an MP4 (voice, captions, background). Waits until done and returns the file path.",
             ["project_id": str, "wait": ["type": "boolean", "description": "Wait for completion (default true)."]], required: ["project_id"]),
    ]

    func call(_ name: String, _ a: [String: Any]) async -> (String, Bool) {
        do { return (Self.json(try await run(name, a)), false) }
        catch { return (Self.json(["error": Self.describe(error)]), true) }
    }

    static func describe(_ e: Error) -> String {
        let d = e.localizedDescription
        switch d {
        case "not_found": return "Project or news item not found."
        case "invalid_url": return "Invalid URL."
        case "stock_key_missing": return "The user has not set a Pexels API key (Agent tab)."
        case "stock_key_invalid": return "Pexels rejected the API key."
        case "stock_no_results": return "No stock footage found; try a different query."
        case "voice_key_missing", "voice_key_invalid", "voice_id_missing": return "Voice service problem (\(d)); ask the user to check Settings → Voice."
        default: return d
        }
    }

    static func json(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) else { return "\(o)" }
        return String(decoding: d, as: UTF8.self)
    }

    @MainActor func summary(_ p: Project) -> [String: Any] {
        var o: [String: Any] = ["project_id": p.id, "status": p.status.rawValue, "title": p.title, "hook": p.hook, "script": p.script,
                                "platform": p.platform.rawValue, "word_count": Rules.wordCount(p.script), "has_video": p.hasVideo,
                                "problems": Rules.describe(p.problems).split(separator: "\n").map { String($0.dropFirst(2)) },
                                "news": ["title": p.news.title, "url": p.news.url]]
        if let u = library.videoURL(p.id), p.hasVideo { o["video_path"] = u.path; o["duration_seconds"] = p.duration as Any }
        if let e = p.error { o["error"] = e }
        if let c = p.stockCredit { o["stock_credit"] = "Video by \(c.author) on Pexels (\(c.page))" }
        return o
    }

    func run(_ name: String, _ a: [String: Any]) async throws -> [String: Any] {
        func pid() throws -> String { guard let s = a["project_id"] as? String else { throw LibraryError.notFound }; return s }
        return try await dispatch(name, a, pid)
    }

    func dispatch(_ name: String, _ a: [String: Any], _ pid: () throws -> String) async throws -> [String: Any] {
        switch name {
        case "list_news":
            if a["refresh"] as? Bool == true { await library.refreshNews() } else if await library.news.isEmpty { await library.refreshNews() }
            return await MainActor.run { ["count": library.news.count, "news": library.news.filter { !$0.isError }.map {
                ["news_url": $0.url, "title": $0.title, "summary": $0.summary, "source": $0.source, "image": $0.image as Any] } as [[String: Any]]] }
        case "get_rules":
            return await MainActor.run {
                let pb = library.playbook
                return ["language": pb.language, "platform": pb.platform.rawValue, "instructions": pb.instructions, "script_words": ["min": pb.minWords, "max": pb.maxWords],
                        "hook_max_words": pb.hookMaxWords, "banned_phrases": pb.banned, "spoken_outro_added_automatically": pb.outro,
                        "full_system_prompt": AgentService.systemPrompt(pb)]
            }
        case "create_project":
            let platform = (a["platform"] as? String).flatMap(Platform.init(rawValue:))
            return try await MainActor.run {
                var item: NewsItem?
                if let u = a["news_url"] as? String { item = library.news.first { $0.url == u } }
                if item == nil, let t = a["title"] as? String {
                    item = NewsItem(title: t, summary: a["summary"] as? String ?? "", url: a["news_url"] as? String ?? "", source: "agent")
                }
                guard let item else { throw LibraryError.notFound }
                let p = library.createProject(news: item, platform: platform, generate: false)
                let pb = library.playbook(for: p)
                return summary(p).merging(["rules_summary": "Script \(pb.minWords)-\(pb.maxWords) words, hook ≤ \(pb.hookMaxWords) words, language \(pb.language). Call get_rules for the full instructions.",
                                           "next": "Write the script and call submit_script."]) { $1 }
            }
        case "submit_script":
            let id = try pid()
            return try await MainActor.run {
                guard library.project(id) != nil else { throw LibraryError.notFound }
                let problems = library.edit(id, title: a["title"] as? String, hook: a["hook"] as? String, script: a["script"] as? String, clipQuery: a["clip_query"] as? String)
                var o = summary(library.project(id)!)
                o["ok"] = problems.isEmpty
                if !problems.isEmpty { o["fix"] = "Fix these problems and call submit_script again." }
                return o
            }
        case "get_project":
            let id = try pid()
            return try await MainActor.run { guard let p = library.project(id) else { throw LibraryError.notFound }; return summary(p) }
        case "list_projects":
            return await MainActor.run { ["projects": library.projects.map { ["project_id": $0.id, "title": $0.title, "status": $0.status.rawValue, "has_video": $0.hasVideo] } as [[String: Any]]] }
        case "find_stock_footage":
            let id = try pid()
            try await MainActor.run { guard library.project(id) != nil else { throw LibraryError.notFound }; library.findStock(id, query: a["query"] as? String) }
            guard let p = await library.waitUntilIdle(id, timeout: 120) else { throw LibraryError.notFound }
            if p.status == .error { throw NSError(domain: "mcp", code: 1, userInfo: [NSLocalizedDescriptionKey: p.error ?? "failed"]) }
            return await MainActor.run { summary(p).merging(["background": "stock"]) { $1 } }
        case "set_background_url":
            let id = try pid()
            guard let s = a["url"] as? String, let u = URL(string: s) else { throw LibraryError.invalidURL }
            try await library.setBackground(id, remote: u)
            return await MainActor.run { summary(library.project(id)!) }
        case "set_platform":
            let id = try pid()
            guard let pf = (a["platform"] as? String).flatMap(Platform.init(rawValue:)) else { throw LibraryError.notFound }
            return try await MainActor.run {
                guard library.project(id) != nil else { throw LibraryError.notFound }
                library.edit(id, platform: pf); return summary(library.project(id)!)
            }
        case "render_video":
            let id = try pid()
            let problems: [Problem] = try await MainActor.run {
                guard let p = library.project(id) else { throw LibraryError.notFound }
                return Rules.validate(hook: p.hook, script: p.script, playbook: library.playbook(for: p))
            }
            if problems.contains(where: { $0.code == .empty }) { throw NSError(domain: "mcp", code: 2, userInfo: [NSLocalizedDescriptionKey: "The project has no script yet. Call submit_script first."]) }
            await MainActor.run { library.render(id) }
            if a["wait"] as? Bool == false { return ["status": "rendering", "project_id": id] }
            guard let p = await library.waitUntilIdle(id, timeout: 300) else { throw LibraryError.notFound }
            if p.status == .error { throw NSError(domain: "mcp", code: 1, userInfo: [NSLocalizedDescriptionKey: p.error ?? "render failed"]) }
            return await MainActor.run { summary(p).merging(problems.isEmpty ? [:] : ["warning": "Rendered with validation problems: " + Rules.describe(problems)]) { $1 } }
        default: throw LibraryError.notFound
        }
    }
}
