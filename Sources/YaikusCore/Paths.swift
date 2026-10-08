import Foundation

public enum Paths {
    /// User data folder. In a sandboxed app it lives inside its container.
    public static var root: URL {
        if let o = ProcessInfo.processInfo.environment["YAIKUS_HOME"] { return URL(fileURLWithPath: o, isDirectory: true) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Yaikus Studio", isDirectory: true)
    }
    public static var projects: URL { root.appendingPathComponent("projects", isDirectory: true) }
    public static func project(_ id: String) -> URL { projects.appendingPathComponent(id, isDirectory: true) }

    public static func ensure(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
