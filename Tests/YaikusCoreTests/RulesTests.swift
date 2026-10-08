import XCTest
@testable import YaikusCore

final class RulesTests: XCTestCase {
    func words(_ n: Int) -> String { Array(repeating: "palabra", count: n).joined(separator: " ") }

    func testValidScriptHasNoProblems() {
        let pb = Playbook.defaults(language: "es")
        XCTAssertEqual(Rules.validate(hook: "Un hook corto", script: words(45), playbook: pb), [])
    }

    func testLengthLimits() {
        let pb = Playbook.defaults(language: "en")
        XCTAssertEqual(Rules.validate(hook: "", script: words(10), playbook: pb).first?.code, .tooShort)
        XCTAssertEqual(Rules.validate(hook: "", script: words(80), playbook: pb).first?.code, .tooLong)
        XCTAssertEqual(Rules.validate(hook: "", script: "", playbook: pb).first?.code, .empty)
    }

    func testBannedAndJunk() {
        let pb = Playbook.defaults(language: "es")
        let p = Rules.validate(hook: "", script: words(45) + " Es INCREÍBLE https://x.com #tag [1,2]", playbook: pb)
        XCTAssertTrue(p.contains { $0.code == .banned && $0.phrase == "increíble" })
        XCTAssertTrue(p.contains { $0.code == .junk })
    }

    func testPlatformEffectiveLimits() {
        let pb = Playbook.defaults(language: "en").effective(for: .youtube)
        XCTAssertEqual(pb.minWords, 90)
        XCTAssertEqual(Platform.youtube.width, 1920)
        XCTAssertEqual(Platform.reels.height, 1920)
    }
}
