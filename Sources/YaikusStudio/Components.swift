import SwiftUI
import YaikusCore

@MainActor struct Page<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let s = subtitle { Text(s).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                content
            }
            .padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .navigationTitle(title)
    }
}

@MainActor struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

@MainActor struct Field<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption).foregroundStyle(.secondary); content }
    }
}

@MainActor struct StatusBadge: View {
    let status: ProjectStatus
    var body: some View {
        HStack(spacing: 5) {
            if [.generating, .rendering, .fetching].contains(status) { ProgressView().controlSize(.mini) }
            Text(t("status." + status.rawValue))
        }
        .font(.caption).padding(.horizontal, 8).padding(.vertical, 2)
        .background(color.opacity(0.18), in: Capsule()).foregroundStyle(color)
    }
    var color: Color {
        switch status { case .ready: return .green; case .error: return .red; case .draft: return .secondary; default: return .orange }
    }
}

/// Short notice ("Saved") that fades away.
@MainActor struct Flash: View {
    @Binding var text: String?
    var body: some View {
        if let text { Text(text).font(.caption).foregroundStyle(.green).transition(.opacity).task(id: text) { try? await Task.sleep(nanoseconds: 2_000_000_000); self.text = nil } }
    }
}

func problemText(_ p: Problem) -> String {
    t("prob." + p.code.rawValue, ["n": p.n ?? 0, "min": p.min ?? 0, "max": p.max ?? 0, "phrase": p.phrase ?? ""])
}
func platformName(_ p: Platform) -> String { "\(t("plat." + p.rawValue)) · \(t("orient." + p.orientation.rawValue))" }
