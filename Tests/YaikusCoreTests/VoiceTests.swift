import XCTest
@testable import YaikusCore

final class VoiceTests: XCTestCase {
    func testEstimateCoversWholeDuration() {
        let w = Aligner.estimate(text: "Hola mundo, esto es una prueba. Segunda frase aquí.", total: 10)
        XCTAssertEqual(w.count, 9)
        XCTAssertEqual(w.last!.end, 10, accuracy: 0.001)
        XCTAssertTrue(zip(w, w.dropFirst()).allSatisfy { $0.end <= $1.start + 1e-9 })
    }

    func testAlignSnapsBoundariesToSilences() {
        let w = Aligner.estimate(text: "uno dos tres cuatro, cinco seis siete ocho. nueve diez once doce", total: 12)
        let comma = w[3], period = w[7]
        let aligned = Aligner.align(w, silences: [(start: comma.end + 0.4, end: comma.end + 0.65), (start: period.end - 0.5, end: period.end - 0.25)], total: 12)
        XCTAssertEqual(aligned[3].end, comma.end + 0.4, accuracy: 0.001)
        XCTAssertEqual(aligned[4].start, comma.end + 0.65, accuracy: 0.001)
        XCTAssertEqual(aligned[7].end, period.end - 0.5, accuracy: 0.001)
        XCTAssertEqual(aligned.last!.end, 12, accuracy: 0.001)
        XCTAssertTrue(zip(aligned, aligned.dropFirst()).allSatisfy { $0.end <= $1.start + 1e-6 })
    }

    func testElevenLabsCharactersToWords() {
        let chars = ["H", "i", " ", "y", "o", "u"]
        let w = VoiceService.wordsFromCharacters(chars, [0, 0.1, 0.2, 0.3, 0.4, 0.5], [0.1, 0.2, 0.3, 0.4, 0.5, 0.6])
        XCTAssertEqual(w.map(\.word), ["Hi", "you"])
        XCTAssertEqual(w[1].start, 0.3, accuracy: 1e-9)
    }

    /// Real integration with the Mac voice (run: YAIKUS_INTEGRATION=1 swift test)
    func testSystemVoiceSynthesizes() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["YAIKUS_INTEGRATION"] == "1")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ys-voice-\(Ids.new())")
        let v = try await VoiceService.synthesize(text: "Hola, esta es una prueba de voz. Segunda frase corta.", language: "es", voiceName: "",
                                                  settings: VoiceSettings(), apiKey: "", into: dir)
        print("duration", v.duration, "words", v.words.count, "first", v.words.first as Any)
        XCTAssertGreaterThan(v.duration, 1.5)
        XCTAssertEqual(v.words.count, 10)
        XCTAssertEqual(v.words.last!.end, v.duration, accuracy: 0.05)
    }
}
