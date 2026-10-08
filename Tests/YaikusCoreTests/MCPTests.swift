import XCTest
@testable import YaikusCore

@MainActor
final class MCPTests: XCTestCase {
    var lib: Library!, server: MCPServer!, port = 0

    override func setUp() async throws {
        setenv("YAIKUS_HOME", NSTemporaryDirectory() + "ys-mcp-\(Ids.new())", 1)
        lib = Library()
        port = 20000 + Int.random(in: 0..<20000)
        server = MCPServer(library: lib)
        server.start(port: port)
        for _ in 0..<50 { if case .running = server.state { break }; try await Task.sleep(nanoseconds: 100_000_000) }
        guard case .running = server.state else { throw XCTSkip("could not open the port: \(server.state)") }
    }
    override func tearDown() async throws { server.stop() }

    func rpc(_ method: String, _ params: [String: Any] = [:], id: Int? = 1, token: String? = nil, useToken: Bool = true) async throws -> (Int, [String: Any]?) {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        else if useToken { req.setValue("Bearer \(server.token)", forHTTPHeaderField: "Authorization") }
        var body: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        if let id { body["id"] = id }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        return ((resp as! HTTPURLResponse).statusCode, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
    }

    func call(_ tool: String, _ args: [String: Any]) async throws -> (isError: Bool, json: [String: Any]) {
        let (code, r) = try await rpc("tools/call", ["name": tool, "arguments": args])
        XCTAssertEqual(code, 200)
        let result = r?["result"] as! [String: Any]
        let text = ((result["content"] as! [[String: Any]])[0]["text"] as! String)
        return (result["isError"] as? Bool ?? false, (try JSONSerialization.jsonObject(with: Data(text.utf8))) as! [String: Any])
    }

    func testHandshakeAndToolList() async throws {
        let (code, r) = try await rpc("initialize", ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "t", "version": "1"]])
        XCTAssertEqual(code, 200)
        let res = r?["result"] as! [String: Any]
        XCTAssertEqual(res["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual((res["serverInfo"] as! [String: Any])["name"] as? String, "yaikus-studio")
        let (_, list) = try await rpc("tools/list", id: 2)
        let names = ((list?["result"] as! [String: Any])["tools"] as! [[String: Any]]).map { $0["name"] as! String }
        XCTAssertEqual(Set(names), ["list_news", "get_rules", "create_project", "submit_script", "get_project", "list_projects", "find_stock_footage", "set_background_url", "set_platform", "render_video"])
        let (c3, _) = try await rpc("notifications/initialized", id: nil)
        XCTAssertEqual(c3, 202)
        let (_, unk) = try await rpc("nope", id: 9)
        XCTAssertEqual((unk?["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testAuthIsRequired() async throws {
        let (noToken, _) = try await rpc("ping", useToken: false)
        XCTAssertEqual(noToken, 401)
        let (bad, _) = try await rpc("ping", token: "wrong")
        XCTAssertEqual(bad, 401)
        var get = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
        get.setValue("Bearer \(server.token)", forHTTPHeaderField: "Authorization")
        let (_, r405) = try await URLSession.shared.data(for: get)
        XCTAssertEqual((r405 as! HTTPURLResponse).statusCode, 405)
        var evil = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!); evil.httpMethod = "POST"
        evil.setValue("Bearer \(server.token)", forHTTPHeaderField: "Authorization"); evil.setValue("https://evil.example", forHTTPHeaderField: "Origin")
        let (_, r403) = try await URLSession.shared.data(for: evil)
        XCTAssertEqual((r403 as! HTTPURLResponse).statusCode, 403)
    }

    func testAgentFlowCreateSubmitValidate() async throws {
        let rules = try await call("get_rules", [:])
        XCTAssertFalse(rules.isError)
        XCTAssertNotNil(rules.json["instructions"])

        let created = try await call("create_project", ["title": "Story from my agent", "summary": "Something happened.", "news_url": "https://ex.com/s", "platform": "reels"])
        XCTAssertFalse(created.isError)
        let id = created.json["project_id"] as! String
        XCTAssertEqual(created.json["platform"] as? String, "reels")
        XCTAssertEqual(created.json["status"] as? String, "draft")   // the built-in AI was not used

        let short = try await call("submit_script", ["project_id": id, "title": "T", "hook": "H", "script": "too short"])
        XCTAssertEqual(short.json["ok"] as? Bool, false)
        XCTAssertFalse((short.json["problems"] as! [String]).isEmpty)

        let good = try await call("submit_script", ["project_id": id, "script": Array(repeating: "word", count: 45).joined(separator: " ")])
        XCTAssertEqual(good.json["ok"] as? Bool, true)

        let proj = try await call("get_project", ["project_id": id])
        XCTAssertEqual(proj.json["word_count"] as? Int, 45)
        let missing = try await call("get_project", ["project_id": "nope"])
        XCTAssertTrue(missing.isError)

        let switched = try await call("set_platform", ["project_id": id, "platform": "youtube"])
        XCTAssertEqual((switched.json["problems"] as! [String]).count, 1)   // 45 words < YouTube minimum
        let noScript = try await call("create_project", ["title": "Empty", "news_url": "x"])
        let r = try await call("render_video", ["project_id": noScript.json["project_id"] as! String])
        XCTAssertTrue(r.isError)
    }

    func testRenderThroughMCP() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["YAIKUS_INTEGRATION"] == "1")
        let c = try await call("create_project", ["title": "Render via MCP", "summary": "x", "news_url": "https://ex.com/r"])
        let id = c.json["project_id"] as! String
        _ = try await call("submit_script", ["project_id": id, "hook": "A short hook here.", "script": Array(repeating: "interesting", count: 45).joined(separator: " ") + "."])
        let r = try await call("render_video", ["project_id": id])
        XCTAssertFalse(r.isError, "\(r.json)")
        XCTAssertEqual(r.json["has_video"] as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.json["video_path"] as! String))
    }
}
