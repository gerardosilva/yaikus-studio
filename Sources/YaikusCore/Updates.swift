import Foundation

/// New-version notice from the public GitHub releases. Fails silently; sends no user data.
public enum Updates {
    public static let repo = "gerardosilva/yaikus-studio"
    public struct Info: Sendable { public var current: String; public var latest: String?; public var url: URL; public var isNewer: Bool }

    public static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    public static func compare(_ a: String, _ b: String) -> Bool {   // a > b
        func parts(_ s: String) -> [Int] { s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) { let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0; if p != q { return p > q } }
        return false
    }

    public static func check() async -> Info {
        let page = URL(string: "https://github.com/\(repo)/releases/latest")!
        var info = Info(current: currentVersion, latest: nil, url: page, isNewer: false)
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!, timeoutInterval: 8)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = j["tag_name"] as? String else { return info }
        info.latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        info.url = (j["html_url"] as? String).flatMap(URL.init(string:)) ?? page
        info.isNewer = compare(tag, info.current)
        return info
    }
}
