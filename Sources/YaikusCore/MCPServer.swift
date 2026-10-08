import Foundation
import Network
import Observation

/// MCP "Streamable HTTP" transport on 127.0.0.1 (local only), with a Bearer token.
///   POST /mcp   JSON-RPC message(s) → application/json reply (or 202 if they were only notifications)
@MainActor @Observable
public final class MCPServer {
    public enum State: Equatable { case stopped, running(Int), failed(String) }
    public private(set) var state: State = .stopped
    /// Port actually in use (may differ from the requested one if it was busy).
    public var activePort: Int? { if case .running(let p) = state { return p }; return nil }
    private var listener: NWListener?
    private let handler: MCPHandler
    private let library: Library
    nonisolated(unsafe) private var port: UInt16 = 0

    public init(library: Library) { self.library = library; handler = MCPHandler(library: library) }

    // MARK: Token
    public var token: String { library.settings.mcp.token }
    public func regenerateToken() { library.regenerateMCPToken() }

    // MARK: Lifecycle
    /// Can this port be opened on loopback?
    nonisolated static func isFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET); addr.sin_port = in_port_t(port).bigEndian; addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 } }
    }

    public func start(port preferred: Int) {
        stop()
        guard let requested = (preferred..<(preferred + 20)).first(where: { $0 < 65536 && Self.isFree($0) }) else { state = .failed("port in use"); return }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(requested)) else { state = .failed("invalid port"); return }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)   // loopback only
            let l = try NWListener(using: params)
            port = UInt16(requested)
            let token = self.token
            let handler = self.handler
            l.newConnectionHandler = { conn in
                Connection(conn, port: UInt16(requested), token: token, handler: handler).start()
            }
            l.stateUpdateHandler = { [weak self] st in
                let owner = self          // a constant: a captured `var` is not valid in concurrent code
                Task { @MainActor in
                    switch st {
                    case .ready: owner?.state = .running(requested)
                    case .failed(let e): owner?.state = .failed(e.localizedDescription); owner?.listener?.cancel()
                    default: break
                    }
                }
            }
            l.start(queue: .global(qos: .userInitiated))
            listener = l
        } catch { state = .failed(error.localizedDescription) }
    }

    public func stop() { listener?.cancel(); listener = nil; state = .stopped }

    // MARK: Minimal HTTP/1.1 connection
    final class Connection: @unchecked Sendable {
        let conn: NWConnection, port: UInt16, token: String, handler: MCPHandler
        var buffer = Data()
        init(_ c: NWConnection, port: UInt16, token: String, handler: MCPHandler) { conn = c; self.port = port; self.token = token; self.handler = handler }

        func start() { conn.start(queue: .global(qos: .userInitiated)); receive() }

        func receive() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] data, _, done, err in
                if let data { buffer.append(data) }
                if err != nil { conn.cancel(); return }
                switch parse() {
                case .some(let req): Task { await respond(req) }
                case .none: if done || buffer.count > 8_000_000 { conn.cancel() } else { receive() }
                }
            }
        }

        struct Request { var method: String; var path: String; var headers: [String: String]; var body: Data }

        func parse() -> Request? {
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let first = head[0].split(separator: " ")
            guard first.count >= 2 else { return Request(method: "", path: "", headers: [:], body: Data()) }
            var headers: [String: String] = [:]
            for l in head.dropFirst() { if let i = l.firstIndex(of: ":") { headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) } }
            let len = Int(headers["content-length"] ?? "0") ?? 0
            let bodyStart = end.upperBound
            guard buffer.count - bodyStart >= len else { return nil }
            return Request(method: String(first[0]), path: String(first[1]), headers: headers, body: buffer.subdata(in: bodyStart..<(bodyStart + len)))
        }

        func respond(_ r: Request) async {
            // Anti DNS-rebinding: Host must be loopback and, if an Origin is sent, it must be too.
            let host = (r.headers["host"] ?? "").split(separator: ":").first.map(String.init) ?? ""
            guard ["127.0.0.1", "localhost", "[::1]"].contains(host) else { return send(403, "Forbidden host") }
            if let o = r.headers["origin"], !["http://127.0.0.1", "http://localhost"].contains(where: { o.hasPrefix($0) }) { return send(403, "Forbidden origin") }
            guard r.path.split(separator: "?").first.map(String.init) == "/mcp" else { return send(404, "Not found") }
            guard (r.headers["authorization"] ?? "") == "Bearer \(token)" else {
                return send(401, "Unauthorized", extra: ["WWW-Authenticate": "Bearer realm=\"yaikus-studio\""])
            }
            switch r.method {
            case "POST":
                if let reply = await handler.handle(r.body) { send(200, String(decoding: reply, as: UTF8.self), type: "application/json") }
                else { send(202, "") }
            case "DELETE": send(200, "")
            default: send(405, "Method not allowed", extra: ["Allow": "POST"])   // no server-initiated SSE stream
            }
        }

        func send(_ code: Int, _ body: String, type: String = "text/plain", extra: [String: String] = [:]) {
            let reasons = [200: "OK", 202: "Accepted", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed"]
            let data = Data(body.utf8)
            var head = "HTTP/1.1 \(code) \(reasons[code] ?? "Error")\r\nContent-Type: \(type); charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\n"
            for (k, v) in extra { head += "\(k): \(v)\r\n" }
            conn.send(content: Data((head + "\r\n").utf8) + data, completion: .contentProcessed { [conn] _ in conn.cancel() })
        }
    }
}
