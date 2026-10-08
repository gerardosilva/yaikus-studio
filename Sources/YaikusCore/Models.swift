import Foundation

// MARK: - Target platforms (they only prepare the format; publishing the video is the user's decision)

public enum Platform: String, Codable, CaseIterable, Sendable {
    case tiktok, reels, shorts, youtube

    public enum Orientation: String, Sendable { case vertical, horizontal }

    public var orientation: Orientation { self == .youtube ? .horizontal : .vertical }
    public var width: Int { orientation == .vertical ? 1080 : 1920 }
    public var height: Int { orientation == .vertical ? 1920 : 1080 }
    public var minWords: Int { self == .youtube ? 90 : 40 }
    public var maxWords: Int { self == .youtube ? 150 : (self == .shorts ? 60 : 55) }
    public var hookMaxWords: Int { self == .youtube ? 20 : 15 }
    /// Distance from the bottom/top edge; keeps clear the areas each app's interface covers.
    public var captionMargin: Double { [.tiktok: 430, .reels: 520, .shorts: 450, .youtube: 90][self]! }
    public var titleMargin: Double { [.tiktok: 170, .reels: 250, .shorts: 200, .youtube: 60][self]! }
    public var wordsPerChunk: Int { orientation == .vertical ? 3 : 5 }
    public var captionSize: Double { orientation == .vertical ? 104 : 84 }
    public var titleSize: Double { orientation == .vertical ? 64 : 52 }
}

// MARK: - Rules (playbook)

public struct Playbook: Codable, Equatable, Sendable {
    public var name: String
    public var language: String          // es, en, pt, fr, de, it
    public var platform: Platform
    public var voice: String             // "" = automatic; name or ID at the voice provider
    public var minWords: Int
    public var maxWords: Int
    public var hookMaxWords: Int
    public var banned: [String]
    public var outro: String
    public var instructions: String

    public static func defaults(language: String) -> Playbook {
        if language.hasPrefix("es") {
            return Playbook(
                name: "Noticias (default)", language: "es", platform: .tiktok, voice: "",
                minWords: 40, maxWords: 55, hookMaxWords: 15,
                banned: ["en este video", "no te lo pierdas", "increíble", "épico", "bombazo"],
                outro: "No olvides darle like, compartir y suscribirte.",
                instructions: """
                Eres editor de noticias para video corto. Escribe en español mexicano, tono directo y natural, como si le contaras la noticia a un amigo.
                - Empieza con el dato más importante, sin saludo.
                - Una sola idea por frase, frases cortas.
                - No inventes datos: usa solo lo que dicen el título y el resumen.
                - Nombres propios y de juegos tal cual, sin traducirlos.
                - Sin emojis, sin hashtags, sin clickbait.
                """)
        }
        return Playbook(
            name: "News (default)", language: "en", platform: .tiktok, voice: "",
            minWords: 40, maxWords: 55, hookMaxWords: 15,
            banned: ["in this video", "don't miss", "incredible", "epic", "game-changer"],
            outro: "Don't forget to like, share and subscribe.",
            instructions: """
            You are a news editor for short-form video. Write in clear, natural American English, as if you were telling a friend the news.
            - Start with the single most important fact, no greeting.
            - One idea per sentence, short sentences.
            - Do not invent facts: use only what the title and summary say.
            - Keep proper nouns and game titles as they are, untranslated.
            - No emojis, no hashtags, no clickbait.
            """)
    }

    /// Same rules but with another platform's limits (for a project whose format changed).
    public func effective(for platform: Platform) -> Playbook {
        guard platform != self.platform else { return self }
        var p = self
        p.platform = platform
        p.minWords = platform.minWords; p.maxWords = platform.maxWords; p.hookMaxWords = platform.hookMaxWords
        return p
    }
}

// MARK: - Sources and news

public struct Source: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case rss, link }
    public var id: String
    public var kind: Kind
    public var url: String
    public var label: String
    public init(id: String = Ids.new(), kind: Kind, url: String, label: String = "") {
        self.id = id; self.kind = kind; self.url = url; self.label = label
    }
}

public struct NewsItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String { url }
    public var title: String
    public var summary: String
    public var url: String
    public var image: String?
    public var source: String
    public var published: String
    public var isError: Bool
    public init(title: String, summary: String, url: String, image: String? = nil, source: String, published: String = "", isError: Bool = false) {
        self.title = title; self.summary = summary; self.url = url; self.image = image
        self.source = source; self.published = published; self.isError = isError
    }
}

// MARK: - Validation

public struct Problem: Codable, Hashable, Sendable {
    public enum Code: String, Codable, Sendable { case empty, tooShort = "too_short", tooLong = "too_long", hookLong = "hook_long", banned, junk }
    public var code: Code
    public var n: Int?
    public var min: Int?
    public var max: Int?
    public var phrase: String?
    public init(_ code: Code, n: Int? = nil, min: Int? = nil, max: Int? = nil, phrase: String? = nil) {
        self.code = code; self.n = n; self.min = min; self.max = max; self.phrase = phrase
    }
}

// MARK: - Project (one news item → one video)

public enum ProjectStatus: String, Codable, Sendable { case generating, draft, rendering, ready, fetching, error }

public struct StockCredit: Codable, Hashable, Sendable {
    public var author: String
    public var page: String
}

public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var created: Date
    public var news: NewsItem
    public var status: ProjectStatus
    public var title: String
    public var hook: String
    public var script: String
    public var clipQuery: String
    public var problems: [Problem]
    public var platform: Platform
    public var lang: String
    public var hasVideo: Bool
    public var duration: Double?
    public var renderedAt: Date?
    public var error: String?
    public var bgImage: String?       // user's own file (absolute path)
    public var bgVideo: String?
    public var imageURL: String?      // the story's image
    public var stockCredit: StockCredit?

    public init(news: NewsItem, platform: Platform, lang: String) {
        id = Ids.new(); created = Date(); self.news = news; status = .draft
        title = String(news.title.prefix(60)); hook = ""; script = ""; clipQuery = ""
        problems = []; self.platform = platform; self.lang = lang; hasVideo = false
        imageURL = news.image
    }

    public enum Background: Sendable { case none, article, image, video, stock }
    public var background: Background {
        if bgVideo != nil { return stockCredit != nil ? .stock : .video }
        if bgImage != nil { return .image }
        return imageURL != nil ? .article : .none
    }
}

// MARK: - Settings

public struct AgentSettings: Codable, Equatable, Sendable {
    public enum Provider: String, Codable, CaseIterable, Sendable { case mock, anthropic, openai }
    public var provider: Provider = .mock
    public var model: String = ""
    public var baseURL: String = ""
    public init() {}
    enum CodingKeys: String, CodingKey { case provider, model, baseURL }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(Provider.self, forKey: .provider) ?? .mock
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
    }
}

public struct VoiceSettings: Codable, Equatable, Sendable {
    public enum Provider: String, Codable, CaseIterable, Sendable { case system, openai, elevenlabs }
    public var provider: Provider = .system
    public var model: String = ""
    public var baseURL: String = ""
    public init() {}
    enum CodingKeys: String, CodingKey { case provider, model, baseURL }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(Provider.self, forKey: .provider) ?? .system
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
    }
}

public struct MCPSettings: Codable, Equatable, Sendable {
    public var enabled: Bool = true
    public var port: Int = 8741
    /// Local access token (loopback only). It is not an external-service key, so it does not go in the Keychain.
    public var token: String = ""
    public init() {}
    enum CodingKeys: String, CodingKey { case enabled, port, token }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 8741
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var agent = AgentSettings()
    public var voice = VoiceSettings()
    public var mcp = MCPSettings()
    public var checkUpdates = true
    public var uiLanguage: String? = nil     // nil = system language
    public init() {}
    enum CodingKeys: String, CodingKey { case agent, voice, mcp, checkUpdates, uiLanguage }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        agent = try c.decodeIfPresent(AgentSettings.self, forKey: .agent) ?? AgentSettings()
        voice = try c.decodeIfPresent(VoiceSettings.self, forKey: .voice) ?? VoiceSettings()
        mcp = try c.decodeIfPresent(MCPSettings.self, forKey: .mcp) ?? MCPSettings()
        checkUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkUpdates) ?? true
        uiLanguage = try c.decodeIfPresent(String.self, forKey: .uiLanguage)
    }
}

public enum Ids {
    public static func new() -> String { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(10)) }
}
