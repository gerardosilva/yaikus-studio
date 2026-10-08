import AVFoundation
import SwiftUI
import YaikusCore

@MainActor
final class SamplePlayer: ObservableObject {
    var player: AVAudioPlayer?
    func play(_ url: URL) { player = try? AVAudioPlayer(contentsOf: url); player?.play() }
}

@MainActor struct VoiceView: View {
    @Environment(Library.self) private var lib
    @State private var s = VoiceSettings()
    @State private var key = ""
    @State private var flash: String?
    @State private var testing = false
    @State private var error: String?
    @State private var loaded = false
    @StateObject private var sample = SamplePlayer()

    var body: some View {
        let _ = Strings.shared.code
        Page(title: t("voice.title"), subtitle: t("voice.intro")) {
            Card {
                Field(label: t("voice.provider")) {
                    Picker("", selection: $s.provider) { ForEach(VoiceSettings.Provider.allCases, id: \.self) { Text(t("voice." + $0.rawValue)).tag($0) } }.labelsHidden().fixedSize()
                }
                Text(t("voice." + s.provider.rawValue + "Hint")).font(.callout).foregroundStyle(.secondary)
                if s.provider != .system {
                    Field(label: t("agent.model") + " (" + t("common.optional") + ")") { TextField("", text: $s.model).textFieldStyle(.roundedBorder) }
                    Field(label: t("agent.key")) { SecureField("API key", text: $key).textFieldStyle(.roundedBorder) }
                }
                if s.provider == .openai {
                    Field(label: t("agent.base") + " (" + t("common.optional") + ")") { TextField("https://api.openai.com/v1", text: $s.baseURL).textFieldStyle(.roundedBorder) }
                }
                if let e = error { Text(errorText(e)).foregroundStyle(.red).font(.callout) }
            }
            HStack {
                Button(t("common.save")) { save(); flash = t("common.saved") }.buttonStyle(.borderedProminent)
                Button { Task { await test() } } label: { testing ? AnyView(HStack { ProgressView().controlSize(.small); Text(t("voice.testing")) }) : AnyView(Text(t("voice.test"))) }.disabled(testing)
                Flash(text: $flash)
            }
        }
        .onAppear { if !loaded { s = lib.settings.voice; key = Secrets.get(.voiceKey); loaded = true } }
    }

    func save() { lib.updateSettings { $0.voice = s }; Secrets.set(.voiceKey, key) }

    func test() async {
        save(); testing = true; error = nil; defer { testing = false }
        let pb = lib.playbook
        let text = pb.language == "es" ? "Hola, así sonará la voz de tus videos." : "Hello, this is how your videos will sound."
        do {
            let v = try await VoiceService.synthesize(text: text, language: pb.language, voiceName: pb.voice, settings: s, apiKey: key, into: FileManager.default.temporaryDirectory.appendingPathComponent("ys-sample"))
            sample.play(v.url)
        } catch { self.error = error.localizedDescription }
    }
}
