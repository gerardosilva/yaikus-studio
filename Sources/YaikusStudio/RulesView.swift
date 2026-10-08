import SwiftUI
import YaikusCore

@MainActor struct RulesView: View {
    @Environment(Library.self) private var lib
    @State private var pb = Playbook.defaults(language: "en")
    @State private var banned = ""
    @State private var flash: String?
    @State private var loaded = false
    let languages = [("es", "Español"), ("en", "English"), ("pt", "Português"), ("fr", "Français"), ("de", "Deutsch"), ("it", "Italiano")]

    var body: some View {
        let _ = Strings.shared.code
        Page(title: t("rules.title"), subtitle: t("rules.intro")) {
            Card {
                Field(label: t("rules.platform")) {
                    Picker("", selection: $pb.platform) { ForEach(Platform.allCases, id: \.self) { Text(platformName($0)).tag($0) } }.labelsHidden().fixedSize()
                        .onChange(of: pb.platform) { _, p in pb.minWords = p.minWords; pb.maxWords = p.maxWords; pb.hookMaxWords = p.hookMaxWords }
                    Text(t("rules.platformHint")).font(.caption).foregroundStyle(.secondary)
                }
                Field(label: t("rules.instructions")) {
                    TextEditor(text: $pb.instructions).frame(minHeight: 170).scrollContentBackground(.hidden)
                        .padding(6).background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                }
                HStack(alignment: .top, spacing: 14) {
                    Field(label: t("rules.min")) { TextField("", value: $pb.minWords, format: .number).textFieldStyle(.roundedBorder) }
                    Field(label: t("rules.max")) { TextField("", value: $pb.maxWords, format: .number).textFieldStyle(.roundedBorder) }
                    Field(label: t("rules.hookMax")) { TextField("", value: $pb.hookMaxWords, format: .number).textFieldStyle(.roundedBorder) }
                }
                Field(label: t("rules.language")) { Picker("", selection: $pb.language) { ForEach(languages, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().fixedSize() }
                Field(label: t("rules.banned")) {
                    TextEditor(text: $banned).frame(height: 70).scrollContentBackground(.hidden).padding(6).background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                }
                Field(label: t("rules.voice")) { voiceField }
                Field(label: t("rules.outro")) { TextField("", text: $pb.outro).textFieldStyle(.roundedBorder) }
                HStack {
                    Button(t("common.save")) {
                        pb.banned = banned.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        lib.savePlaybook(pb); flash = t("common.saved")
                    }.buttonStyle(.borderedProminent)
                    Button(t("rules.reset")) { lib.resetPlaybook(); load() }
                    Flash(text: $flash)
                }
            }
        }
        .onAppear { if !loaded { load(); loaded = true } }
    }

    func load() { pb = lib.playbook; banned = pb.banned.joined(separator: "\n") }

    @ViewBuilder var voiceField: some View {
        if lib.settings.voice.provider == .system {
            let voices = SystemSpeech.installedVoices().filter { $0.language.lowercased().hasPrefix(pb.language) }
            Picker("", selection: $pb.voice) {
                Text(t("rules.voiceAuto")).tag("")
                ForEach(voices) { Text("\($0.name) (\($0.language))").tag($0.name) }
                if !pb.voice.isEmpty, !voices.contains(where: { $0.name == pb.voice }) { Text(pb.voice).tag(pb.voice) }
            }.labelsHidden().fixedSize()
        } else {
            TextField(t("rules.voiceId"), text: $pb.voice).textFieldStyle(.roundedBorder)
        }
    }
}
