import Foundation

/// Royalty-free footage (Pexels). The user supplies their own free API key.
public enum Stock {
    public struct Hit: Sendable { public var url: URL; public var author: String; public var page: String }
    public enum StockError: LocalizedError {
        case keyMissing, keyInvalid, noResults
        public var errorDescription: String? {
            switch self { case .keyMissing: return "stock_key_missing"; case .keyInvalid: return "stock_key_invalid"; case .noResults: return "stock_no_results" }
        }
    }

    public static func find(apiKey: String, query: String, platform: Platform) async throws -> Hit {
        guard !apiKey.isEmpty else { throw StockError.keyMissing }
        var c = URLComponents(string: "https://api.pexels.com/videos/search")!
        c.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "per_page", value: "15"),
                        URLQueryItem(name: "orientation", value: platform.orientation == .vertical ? "portrait" : "landscape")]
        var req = URLRequest(url: c.url!, timeoutInterval: 30)
        req.setValue(apiKey, forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw StockError.keyInvalid }
        guard code == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any], let vids = j["videos"] as? [[String: Any]] else { throw StockError.noResults }
        for v in vids {
            guard (v["duration"] as? Double ?? Double(v["duration"] as? Int ?? 0)) >= 5, let files = v["video_files"] as? [[String: Any]] else { continue }
            let mp4 = files.filter { ($0["file_type"] as? String) == "video/mp4" && ($0["width"] as? Int) != nil }
            let target = min(platform.width, 1280)
            guard let best = mp4.min(by: { abs(($0["width"] as! Int) - target) < abs(($1["width"] as! Int) - target) }),
                  let link = (best["link"] as? String).flatMap(URL.init(string:)) else { continue }
            let user = v["user"] as? [String: Any]
            return Hit(url: link, author: user?["name"] as? String ?? "", page: v["url"] as? String ?? "")
        }
        throw StockError.noResults
    }

    public static func download(_ url: URL, to dest: URL) async throws {
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }
}
