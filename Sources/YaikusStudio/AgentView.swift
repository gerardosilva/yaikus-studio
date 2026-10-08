import SwiftUI
import YaikusCore

@MainActor struct AgentView: View {
    @Environment(Library.self) private var lib
    @State private var s = AgentSettings()
    @State private var key = ""
    @State private var pexels = ""
    @State private var flash: String?
    @State private var loaded = false

    var body: some View {
        let _ = Strings.shared.code
        Page(title: t("agent.title"), subtitle: t("agent.intro")) {
            Card {
                Field(label: t("agent.provider")) {
                    Picker("", selection: $s.provider) { ForEach(AgentSettings.Provider.allCases, id: \.self) { Text(t("agent." + $0.rawValue)).tag($0) } }.labelsHidden().fixedSize()
                }
                Text(t("agent." + s.provider.rawValue + "Hint")).font(.callout).foregroundStyle(.secondary)
                if s.provider != .mock {
                    Field(label: t("agent.model")) { TextField(t("agent.modelHint"), text: $s.model).textFieldStyle(.roundedBorder) }
                    Field(label: t("agent.key")) { SecureField("API key", text: $key).textFieldStyle(.roundedBorder) }
                }
                if s.provider == .openai {
                    Field(label: t("agent.base")) { TextField("https://api.x.ai/v1  ·  http://localhost:11434/v1", text: $s.baseURL).textFieldStyle(.roundedBorder) }
                }
            }
            Card {
                Field(label: t("stock.title")) {
                    SecureField("Pexels API key", text: $pexels).textFieldStyle(.roundedBorder)
                    Text(t("stock.hint")).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(t("common.save")) {
                    lib.updateSettings { $0.agent = s }
                    Secrets.set(.agentKey, key); Secrets.set(.pexelsKey, pexels)
                    flash = t("common.saved")
                }.buttonStyle(.borderedProminent)
                Flash(text: $flash)
            }
        }
        .onAppear { if !loaded { s = lib.settings.agent; key = Secrets.get(.agentKey); pexels = Secrets.get(.pexelsKey); loaded = true } }
    }
}
