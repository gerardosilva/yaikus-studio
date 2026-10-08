import SwiftUI
import YaikusCore

@MainActor struct SourcesView: View {
    @Environment(Library.self) private var lib
    @State private var kind: Source.Kind = .rss
    @State private var url = ""
    @State private var label = ""
    @State private var error: String?

    var body: some View {
        let _ = Strings.shared.code
        Page(title: t("sources.title")) {
            Card {
                ViewThatFits {
                    HStack { fields }
                    VStack(alignment: .leading) { fields }
                }
                if let e = error { Text(errorText(e)).foregroundStyle(.red).font(.callout) }
            }
            if lib.sources.isEmpty { Text(t("sources.empty")).foregroundStyle(.secondary) }
            ForEach(lib.sources) { s in
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.label.isEmpty ? s.url : s.label).font(.headline)
                            Text((s.kind == .rss ? "RSS · " : "Link · ") + s.url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        Button(t("common.remove"), role: .destructive) { lib.removeSource(s.id) }
                    }
                }
            }
        }
    }

    @ViewBuilder var fields: some View {
        Picker("", selection: $kind) { Text(t("sources.rss")).tag(Source.Kind.rss); Text(t("sources.link")).tag(Source.Kind.link) }.labelsHidden().fixedSize()
        TextField("https://…", text: $url).textFieldStyle(.roundedBorder).frame(minWidth: 220)
        TextField(t("sources.name"), text: $label).textFieldStyle(.roundedBorder).frame(minWidth: 140)
        Button(t("sources.add")) {
            do { try lib.addSource(kind: kind, url: url, label: label); url = ""; label = ""; error = nil }
            catch { self.error = error.localizedDescription }
        }.buttonStyle(.borderedProminent)
    }
}
