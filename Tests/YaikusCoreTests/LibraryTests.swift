import XCTest
@testable import YaikusCore

@MainActor
final class LibraryTests: XCTestCase {
    func tempLibrary() -> Library {
        setenv("YAIKUS_HOME", NSTemporaryDirectory() + "ys-lib-\(Ids.new())", 1)
        return Library()
    }

    func testProjectLifecycleWithMockAgent() async throws {
        let lib = tempLibrary()
        let news = NewsItem(title: "Big story about the new console", summary: String(repeating: "details ", count: 50), url: "https://ex.com/1", source: "Ex")
        let p = lib.createProject(news: news, platform: .shorts)
        let done = await lib.waitUntilIdle(p.id, timeout: 10)
        XCTAssertEqual(done?.status, .draft)
        XCTAssertEqual(done?.problems, [])
        XCTAssertFalse(done!.script.isEmpty)

        // edit to a short script → the problem appears and the video is invalidated
        let problems = lib.edit(p.id, script: "muy corto")
        XCTAssertEqual(problems.first?.code, .tooShort)

        // persists and reloads
        let again = Library()
        XCTAssertEqual(again.projects.first?.id, p.id)

        lib.deleteProject(p.id)
        XCTAssertNil(lib.project(p.id))
    }

    func testSourcesValidationAndLanguageFollowsUntilEdited() throws {
        let lib = tempLibrary()
        XCTAssertThrowsError(try lib.addSource(kind: .rss, url: "not a url", label: ""))
        let n = lib.sources.count
        try lib.addSource(kind: .link, url: "https://ex.com/a", label: "A")
        XCTAssertEqual(lib.sources.count, n + 1)
        lib.setLanguage("es"); XCTAssertEqual(lib.playbook.language, "es")
        lib.setLanguage("en"); XCTAssertEqual(lib.playbook.language, "en")
        var pb = lib.playbook; pb.language = "es"; lib.savePlaybook(pb)
        lib.setLanguage("en"); XCTAssertEqual(lib.playbook.language, "es", "edited rules do not change with the language")
        lib.resetPlaybook(); XCTAssertEqual(lib.playbook.language, "en")
    }

    func testRenderEndToEnd() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["YAIKUS_INTEGRATION"] == "1")
        let lib = tempLibrary()
        lib.setLanguage("es")
        let news = NewsItem(title: "Nintendo presenta nueva consola", summary: "Nintendo reveló hoy una nueva versión de su consola híbrida con pantalla OLED más grande, mejor batería y almacenamiento ampliado. Llegará en octubre a un precio de 349 dólares y será compatible con todos los juegos actuales de la plataforma, según informó la compañía en un comunicado oficial.", url: "https://ex.com/2", source: "Ex")
        let p = lib.createProject(news: news)
        _ = await lib.waitUntilIdle(p.id, timeout: 10)
        lib.render(p.id)
        let done = await lib.waitUntilIdle(p.id, timeout: 120)
        XCTAssertEqual(done?.status, .ready, done?.error ?? "")
        XCTAssertTrue(done?.hasVideo ?? false)
        XCTAssertNotNil(lib.videoURL(p.id))
        print("rendered", lib.videoURL(p.id)!.path, done!.duration as Any)
    }
}

final class SettingsCompatTests: XCTestCase {
    /// A settings file from an earlier version (without newer fields) must not be lost when decoding.
    func testOldSettingsFileStillDecodes() throws {
        let json = #"{"agent":{"provider":"anthropic"},"uiLanguage":"es"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.agent.provider, .anthropic)
        XCTAssertEqual(s.uiLanguage, "es")
        XCTAssertEqual(s.voice.provider, .system)
        XCTAssertTrue(s.mcp.enabled)
        XCTAssertEqual(s.mcp.port, 8741)
        XCTAssertTrue(s.checkUpdates)
    }
}
