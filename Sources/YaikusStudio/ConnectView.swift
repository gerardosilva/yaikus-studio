import AppKit
import SwiftUI
import YaikusCore

@MainActor struct ConnectView: View {
    @Environment(Library.self) private var lib
    @Environment(MCPServer.self) private var mcp
    @State private var port = 8765
    var token: String { lib.settings.mcp.token }
    @State private var reveal = false
    @State private var copied: String?
    @State private var confirmRegen = false

    var url: String { "http://127.0.0.1:\(mcp.activePort ?? port)/mcp" }
    var shownToken: String { reveal ? token : String(repeating: "•", count: 24) }

    var body: some View {
        let _ = Strings.shared.code
        Page(title: t("connect.title"), subtitle: t("connect.intro")) {
            Card {
                Toggle(t("connect.enabled"), isOn: Binding(get: { lib.settings.mcp.enabled }, set: { on in
                    lib.updateSettings { $0.mcp.enabled = on }
                    if on { mcp.start(port: port) } else { mcp.stop() }
                }))
                HStack(alignment: .firstTextBaseline) {
                    Field(label: t("connect.port")) {
                        TextField("", value: $port, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 90)
                            .onSubmit { lib.updateSettings { $0.mcp.port = port }; if lib.settings.mcp.enabled { mcp.start(port: port) } }
                    }
                    Spacer()
                    statusLabel
                }
                Field(label: t("connect.url")) { copyRow(url, id: "url") }
                Field(label: t("connect.token")) {
                    HStack {
                        Text(shownToken).font(.system(.callout, design: .monospaced)).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(reveal ? t("connect.hide") : t("connect.show")) { reveal.toggle() }
                        Button(t("common.copy")) { copy(token, id: "token") }
                        Button(t("connect.regen")) { confirmRegen = true }
                    }
                    Text(copied == "token" ? t("common.copied") : " ").font(.caption).foregroundStyle(.green)
                }
            }
            Card {
                Text(t("connect.claudeCode")).font(.headline)
                snippet("claude mcp add --transport http yaikus-studio \(url) --header \"Authorization: Bearer \(token)\"", id: "claude")
                Text(t("connect.generic")).font(.headline).padding(.top, 6)
                snippet("""
                {
                  "mcpServers": {
                    "yaikus-studio": {
                      "type": "http",
                      "url": "\(url)",
                      "headers": { "Authorization": "Bearer \(token)" }
                    }
                  }
                }
                """, id: "json")
                Text(t("connect.genericHint")).font(.caption).foregroundStyle(.secondary)
                snippet("""
                { "command": "npx", "args": ["-y", "mcp-remote", "\(url)", "--header", "Authorization: Bearer \(token)"] }
                """, id: "remote")
            }
            Card {
                Text(t("connect.tools")).font(.headline)
                Text(t("connect.toolsText")).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .onAppear { port = lib.settings.mcp.port }
        .confirmationDialog(t("connect.regen") + "?", isPresented: $confirmRegen) {
            Button(t("connect.regen"), role: .destructive) { mcp.regenerateToken(); if lib.settings.mcp.enabled { mcp.start(port: port) } }
        } message: { Text(t("connect.regenWarn")) }
    }

    @ViewBuilder var statusLabel: some View {
        switch mcp.state {
        case .running(let p): Label(t("connect.running", ["port": p]), systemImage: "circle.fill").foregroundStyle(.green).font(.callout)
        case .stopped: Label(t("connect.stopped"), systemImage: "circle").foregroundStyle(.secondary).font(.callout)
        case .failed(let m): Label(t("connect.failed", ["msg": m]), systemImage: "exclamationmark.circle.fill").foregroundStyle(.red).font(.callout)
        }
    }

    func copy(_ s: String, id: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        copied = id; Task { try? await Task.sleep(nanoseconds: 2_000_000_000); if copied == id { copied = nil } }
    }

    func copyRow(_ s: String, id: String) -> some View {
        HStack { Text(s).font(.system(.callout, design: .monospaced)).textSelection(.enabled); Spacer(); Button(copied == id ? t("common.copied") : t("common.copy")) { copy(s, id: id) } }
    }

    func snippet(_ s: String, id: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(s.replacingOccurrences(of: token, with: reveal ? token : "<token>")).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8).background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            Button(copied == id ? t("common.copied") : t("common.copy")) { copy(s, id: id) }.controlSize(.small)   // always copies the real token
        }
    }
}
