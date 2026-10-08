import Foundation

public enum HTML {
    static let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&ndash;": "–", "&mdash;": "—"]

    public static func decode(_ s: String) -> String {
        var out = s
        for (k, v) in entities { out = out.replacingOccurrences(of: k, with: v) }
        // &#1234; and &#x1F600;
        let re = try! NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);")
        for m in re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
            let token = String(out[Range(m.range(at: 1), in: out)!])
            let code = token.hasPrefix("x") ? UInt32(token.dropFirst(), radix: 16) : UInt32(token)
            if let c = code, let u = Unicode.Scalar(c) { out.replaceSubrange(Range(m.range, in: out)!, with: String(Character(u))) }
        }
        return out
    }

    public static func clean(_ s: String) -> String {
        let noTags = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decode(noTags).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Reads RSS/Atom feeds and standalone article links.
public enum Feeds {
    public static let userAgent = "Mozilla/5.0 (Macintosh) YaikusStudio/1.0"

    // MARK: RSS/Atom parser
    final class Parser: NSObject, XMLParserDelegate {
        var items: [NewsItem] = []
        let label: String
        let limit: Int
        private var inItem = false
        private var stack: [String] = []
        private var text = ""
        private var f: [String: String] = [:]
        private var image: String?

        init(label: String, limit: Int) { self.label = label; self.limit = limit }

        func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            let n = local(name)
            if n == "item" || n == "entry" { inItem = true; f = [:]; image = nil }
            if inItem {
                if n == "link", let href = a["href"], f["link"] == nil || a["rel"] == "alternate" { f["link"] = href }
                if image == nil, let url = a["url"] ?? nil {
                    if n == "thumbnail" || (n == "content" && (a["medium"] == nil || a["medium"] == "image") && (a["type"] ?? "image").hasPrefix("image"))
                        || (n == "enclosure" && (a["type"] ?? "").hasPrefix("image")) { image = url }
                }
            }
            text = ""; stack.append(n)
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
        func parser(_ p: XMLParser, foundCDATA d: Data) { text += String(data: d, encoding: .utf8) ?? "" }

        func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let n = local(name)
            defer { _ = stack.popLast(); text = "" }
            guard inItem else { return }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch n {
            case "title": f["title"] = t
            case "link": if !t.isEmpty { f["link"] = t }
            case "encoded", "content": if !t.isEmpty { f["body"] = f["body"] ?? t }
            case "description", "summary": if !t.isEmpty { f["body"] = t }
            case "pubDate", "updated", "published": f["date"] = f["date"] ?? t
            case "item", "entry":
                inItem = false
                let body = f["body"] ?? ""
                var img = image
                if img == nil, let m = body.range(of: #"<img[^>]+src=["']([^"']+)"#, options: .regularExpression) {
                    let tag = String(body[m]); if let s = tag.range(of: #"src=["']"#, options: .regularExpression) { img = String(tag[s.upperBound...]) }
                }
                if let title = f["title"], !title.isEmpty, let link = f["link"], !link.isEmpty, items.count < limit {
                    items.append(NewsItem(title: HTML.clean(title), summary: String(HTML.clean(body).prefix(900)), url: link,
                                          image: img.map(HTML.decode), source: label, published: f["date"] ?? ""))
                }
            default: break
            }
        }
        private func local(_ n: String) -> String { n.split(separator: ":").last.map(String.init) ?? n }
    }

    public static func parseFeed(_ data: Data, label: String, limit: Int = 15) -> [NewsItem] {
        let delegate = Parser(label: label, limit: limit)
        let p = XMLParser(data: data); p.delegate = delegate; p.parse()
        return delegate.items
    }

    // MARK: Standalone article
    static func meta(_ page: String, _ names: [String]) -> String {
        for n in names {
            let esc = NSRegularExpression.escapedPattern(for: n)
            for pat in ["<meta[^>]+(?:property|name)=[\"']\(esc)[\"'][^>]+content=[\"']([^\"']*)", "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+(?:property|name)=[\"']\(esc)[\"']"] {
                if let r = try? NSRegularExpression(pattern: pat, options: .caseInsensitive), let m = r.firstMatch(in: page, range: NSRange(page.startIndex..., in: page)),
                   let rg = Range(m.range(at: 1), in: page) { return HTML.decode(String(page[rg])).trimmingCharacters(in: .whitespaces) }
            }
        }
        return ""
    }

    public static func parseArticle(_ page: String, url: String, label: String) -> NewsItem {
        var title = meta(page, ["og:title", "twitter:title"])
        if title.isEmpty, let m = page.range(of: "<title[^>]*>(.*?)</title>", options: [.regularExpression, .caseInsensitive]) { title = HTML.clean(String(page[m])) }
        let img = meta(page, ["og:image", "twitter:image"])
        return NewsItem(title: title.isEmpty ? url : title, summary: String(meta(page, ["og:description", "description", "twitter:description"]).prefix(900)),
                        url: url, image: img.isEmpty ? nil : img, source: label.isEmpty ? (URL(string: url)?.host ?? "") : label)
    }

    // MARK: Network
    static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 15); r.setValue(userAgent, forHTTPHeaderField: "User-Agent"); return r
    }

    public static func fetch(_ src: Source) async -> [NewsItem] {
        guard let url = URL(string: src.url) else { return [errorItem(src, "invalid URL")] }
        do {
            let (data, resp) = try await URLSession.shared.data(for: request(url))
            if let code = (resp as? HTTPURLResponse)?.statusCode, code >= 400 { throw URLError(.badServerResponse) }
            switch src.kind {
            case .rss:
                let items = parseFeed(data, label: src.label.isEmpty ? (url.host ?? "") : src.label)
                return items.isEmpty ? [errorItem(src, "no items")] : items
            case .link:
                let page = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                return [parseArticle(page, url: (resp.url ?? url).absoluteString, label: src.label)]
            }
        } catch { return [errorItem(src, error.localizedDescription)] }
    }

    static func errorItem(_ src: Source, _ msg: String) -> NewsItem {
        NewsItem(title: src.label.isEmpty ? src.url : src.label, summary: msg, url: src.url, source: "error", isError: true)
    }

    public static func fetchAll(_ sources: [Source]) async -> [NewsItem] {
        await withTaskGroup(of: (Int, [NewsItem]).self) { g in
            for (i, s) in sources.enumerated() { g.addTask { (i, await fetch(s)) } }
            var res: [(Int, [NewsItem])] = []
            for await r in g { res.append(r) }
            return res.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }
}
