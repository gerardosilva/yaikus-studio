import Foundation

public struct AgentDraft: Equatable, Sendable {
    public var title = "", hook = "", script = "", clipQuery = ""
    public init(title: String = "", hook: String = "", script: String = "", clipQuery: String = "") {
        self.title = title; self.hook = hook; self.script = script; self.clipQuery = clipQuery
    }
}

public enum AgentError: LocalizedError {
    case keyMissing, keyInvalid, noJSON(String), http(Int)
    public var errorDescription: String? {
        switch self {
        case .keyMissing: return "agent_key_missing"
        case .keyInvalid: return "agent_key_invalid"
        case .noJSON(let s): return "The agent did not return JSON: \(s.prefix(200))"
        case .http(let c): return "HTTP \(c)"
        }
    }
}

/// One contract for every agent: news item + rules (+ problems from the previous attempt) in, {title, hook, script, clip_query} out.
/// External agents (OpenClaw, Hermes, Claude Code…) are not run from here: they connect over MCP and push their result.
public enum AgentService {
    static let languageNames = ["es": "Spanish (Mexican)", "en": "English (American)", "pt": "Portuguese", "fr": "French", "de": "German", "it": "Italian"]

    public static func systemPrompt(_ pb: Playbook) -> String {
        let note = pb.platform.orientation == .vertical ? "vertical short video (9:16), fast pace" : "horizontal video (16:9), a bit more detail is fine"
        return """
        \(pb.instructions)

        Hard rules (they are validated automatically):
        - Script: between \(pb.minWords) and \(pb.maxWords) words.
        - Hook: at most \(pb.hookMaxWords) words, one sentence that grabs attention.
        - Write title, hook and script in \(languageNames[pb.language] ?? pb.language).
        - Banned phrases: \(pb.banned.isEmpty ? "none" : pb.banned.joined(separator: ", ")).
        - Target format: \(note).

        Reply ONLY with valid JSON, no extra text and no code fences:
        {"title": "short title (max 6 words)", "hook": "...", "script": "...", "clip_query": "search query to find related footage"}
        """
    }

    public static func userPrompt(_ news: NewsItem, feedback: String?) -> String {
        var m = "News item from \(news.source):\nTitle: \(news.title)\nSummary: \(news.summary)\nLink: \(news.url)"
        if let fb = feedback, !fb.isEmpty { m += "\n\nYour previous attempt had these problems, fix them:\n\(fb)" }
        return m
    }

    public static func parse(_ text: String) throws -> AgentDraft {
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b,
              let obj = try? JSONSerialization.jsonObject(with: Data(text[a...b].utf8)) as? [String: Any] else { throw AgentError.noJSON(text) }
        func s(_ k: String) -> String { (obj[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        return AgentDraft(title: s("title"), hook: s("hook"), script: s("script"), clipQuery: s("clip_query"))
    }

    /// Asks for the script and retries with the validators' problems.
    public static func generate(settings: AgentSettings, apiKey: String, playbook: Playbook, news: NewsItem,
                                feedback: String? = nil, retries: Int = 2) async throws -> (AgentDraft, [Problem]) {
        var fb = feedback, draft = AgentDraft(), problems: [Problem] = []
        for _ in 0...retries {
            switch settings.provider {
            case .mock: draft = mock(playbook, news)
            case .anthropic: draft = try await anthropic(settings, apiKey, playbook, news, fb)
            case .openai: draft = try await openAI(settings, apiKey, playbook, news, fb)
            }
            problems = Rules.validate(hook: draft.hook, script: draft.script, playbook: playbook)
            if problems.isEmpty { break }
            fb = Rules.describe(problems)
        }
        return (draft, problems)
    }

    static func mock(_ pb: Playbook, _ news: NewsItem) -> AgentDraft {
        var w = (news.summary.isEmpty ? news.title : news.summary).split(separator: " ").map(String.init)
        while w.count < pb.minWords { w += (news.title + ".").split(separator: " ").map(String.init) }
        w = Array(w.prefix(pb.maxWords - 5))
        let t = news.title.split(separator: " ")
        return AgentDraft(title: t.prefix(6).joined(separator: " "), hook: t.prefix(pb.hookMaxWords).joined(separator: " "),
                          script: w.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".,")) + ".", clipQuery: news.title)
    }

    static func post(_ url: String, headers: [String: String], body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw AgentError.keyInvalid }
        guard code == 200 else { throw AgentError.http(code) }
        return data
    }

    static func anthropic(_ s: AgentSettings, _ key: String, _ pb: Playbook, _ news: NewsItem, _ fb: String?) async throws -> AgentDraft {
        if key.isEmpty { throw AgentError.keyMissing }
        let data = try await post("https://api.anthropic.com/v1/messages", headers: ["x-api-key": key, "anthropic-version": "2023-06-01"], body: [
            "model": s.model.isEmpty ? "claude-haiku-5-5" : s.model, "max_tokens": 1024, "system": systemPrompt(pb),
            "messages": [["role": "user", "content": userPrompt(news, feedback: fb)]]])
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = (j?["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
        return try parse(text)
    }

    static func openAI(_ s: AgentSettings, _ key: String, _ pb: Playbook, _ news: NewsItem, _ fb: String?) async throws -> AgentDraft {
        let base = s.baseURL.isEmpty ? "https://api.openai.com/v1" : s.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if key.isEmpty && base.contains("api.openai.com") { throw AgentError.keyMissing }
        let data = try await post(base + "/chat/completions", headers: key.isEmpty ? [:] : ["Authorization": "Bearer \(key)"], body: [
            "model": s.model.isEmpty ? "gpt-4o-mini" : s.model,
            "messages": [["role": "system", "content": systemPrompt(pb)], ["role": "user", "content": userPrompt(news, feedback: fb)]]])
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = ((j?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        return try parse(text)
    }
}
