import AVFoundation
import XCTest
@testable import YaikusCore

final class RenderTests: XCTestCase {
    var enabled: Bool { ProcessInfo.processInfo.environment["YAIKUS_INTEGRATION"] == "1" }

    func make(_ name: String, platform: Platform, bg: RenderBackground, lang: String = "es") async throws -> URL {
        let dir = URL(fileURLWithPath: "/tmp/ys-render-test", isDirectory: true)
        Paths.ensure(dir)
        let text = lang == "es"
            ? "Nintendo reveló hoy una nueva consola híbrida con pantalla OLED más grande, mejor batería y almacenamiento ampliado. Llegará en octubre. No olvides darle like, compartir y suscribirte."
            : "Nintendo revealed a new hybrid console with a larger OLED screen, better battery life and expanded storage. It arrives in October."
        let v = try await VoiceService.synthesize(text: text, language: lang, voiceName: "", settings: VoiceSettings(), apiKey: "", into: dir)
        let out = dir.appendingPathComponent("\(name).mp4")
        try await Renderer.render(RenderRequest(title: "Nintendo presenta nueva consola OLED", words: v.words, audio: v.url, duration: v.duration,
                                                platform: platform, background: bg, output: out))
        return out
    }

    func check(_ url: URL, w: Int, h: Int) async throws {
        let asset = AVURLAsset(url: url)
        let vt = try await asset.loadTracks(withMediaType: .video).first!
        let at = try await asset.loadTracks(withMediaType: .audio)
        let size = try await vt.load(.naturalSize)
        XCTAssertEqual(Int(size.width), w); XCTAssertEqual(Int(size.height), h)
        XCTAssertEqual(at.count, 1)
        let dur = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(dur, 5)
    }

    func testVerticalColor() async throws {
        try XCTSkipUnless(enabled)
        let u = try await make("vertical_color", platform: .tiktok, bg: .color)
        try await check(u, w: 1080, h: 1920)
    }

    func testHorizontalImage() async throws {
        try XCTSkipUnless(enabled)
        let ctx = Renderer.context(1280, 720)
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
        ctx.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 400, y: 150, width: 480, height: 420))
        let u = try await make("horizontal_image", platform: .youtube, bg: .image(ctx.makeImage()!), lang: "en")
        try await check(u, w: 1920, h: 1080)
    }

    func testVerticalVideoBackground() async throws {
        try XCTSkipUnless(enabled)
        let clip = ProcessInfo.processInfo.environment["YAIKUS_TEST_CLIP"] ?? ""
        try XCTSkipUnless(FileManager.default.fileExists(atPath: clip))
        let u = try await make("vertical_video", platform: .reels, bg: .video(URL(fileURLWithPath: clip)))
        try await check(u, w: 1080, h: 1920)
    }
}
