import XCTest
@testable import YaikusCore

final class FeedTests: XCTestCase {
    func testRSS() {
        let xml = """
        <?xml version="1.0"?><rss xmlns:media="http://search.yahoo.com/mrss/" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel>
        <item><title>Nintendo &amp; friends: &quot;big&quot; news</title><link>https://ex.com/a</link>
        <description><![CDATA[<p>Hello <b>world</b> &amp; more</p><img src="https://ex.com/img.jpg">]]></description><pubDate>Mon, 01 Jan 2026</pubDate>
        <media:thumbnail url="https://ex.com/thumb.jpg"/></item>
        <item><title>Second</title><link>https://ex.com/b</link><description>plain</description></item>
        <item><title></title><link>https://ex.com/c</link></item>
        </channel></rss>
        """
        let items = Feeds.parseFeed(Data(xml.utf8), label: "Ex")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Nintendo & friends: \"big\" news")
        XCTAssertEqual(items[0].summary, "Hello world & more")
        XCTAssertEqual(items[0].image, "https://ex.com/thumb.jpg")
        XCTAssertEqual(items[1].url, "https://ex.com/b")
        XCTAssertEqual(items[1].source, "Ex")
    }

    func testAtomAndInlineImage() {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Atom title</title><link rel="alternate" href="https://ex.com/x"/>
        <summary>&lt;p&gt;Sum &lt;img src="https://ex.com/i.png"&gt;&lt;/p&gt;</summary><updated>2026-01-01</updated></entry></feed>
        """
        let items = Feeds.parseFeed(Data(xml.utf8), label: "A")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].url, "https://ex.com/x")
    }

    func testArticleMeta() {
        let page = """
        <html><head><title>T</title><meta property="og:title" content="OG &amp; Title"><meta content="Desc here" name="description">
        <meta property="og:image" content="https://ex.com/og.jpg"></head></html>
        """
        let n = Feeds.parseArticle(page, url: "https://ex.com/p", label: "")
        XCTAssertEqual(n.title, "OG & Title"); XCTAssertEqual(n.summary, "Desc here"); XCTAssertEqual(n.image, "https://ex.com/og.jpg"); XCTAssertEqual(n.source, "ex.com")
    }

    func testHTMLEntities() { XCTAssertEqual(HTML.clean("a&#8217;s &#x41; <i>b</i>"), "a’s A b") }

    func testAgentParseAndMock() throws {
        let d = try AgentService.parse("Sure!\n```json\n{\"title\":\"T\",\"hook\":\"H\",\"script\":\"S s\",\"clip_query\":\"q\"}\n```")
        XCTAssertEqual(d, AgentDraft(title: "T", hook: "H", script: "S s", clipQuery: "q"))
        XCTAssertThrowsError(try AgentService.parse("no json"))
    }

    func testMockPassesValidators() async throws {
        let pb = Playbook.defaults(language: "en")
        let news = NewsItem(title: "A big story about games", summary: String(repeating: "words ", count: 30), url: "u", source: "s")
        let (draft, problems) = try await AgentService.generate(settings: AgentSettings(), apiKey: "", playbook: pb, news: news)
        XCTAssertTrue(problems.isEmpty, "\(problems)")
        XCTAssertFalse(draft.script.isEmpty)
    }

    func testVersionCompare() {
        XCTAssertTrue(Updates.compare("v0.10.0", "0.9.5")); XCTAssertFalse(Updates.compare("0.1.0", "0.1.0")); XCTAssertTrue(Updates.compare("1.0", "0.9.9"))
    }
}
