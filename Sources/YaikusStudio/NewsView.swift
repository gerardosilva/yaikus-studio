import SwiftUI
import YaikusCore

@MainActor struct NewsView: View {
    @Environment(Library.self) private var lib
    var openProject: (String) -> Void

    var body: some View {
        let _ = Strings.shared.code
        Group {
            if lib.newsLoading && lib.news.isEmpty {
                VStack { ProgressView(); Text(t("news.loading")).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lib.news.isEmpty {
                ContentUnavailableView(t("news.empty"), systemImage: "newspaper")
            } else {
                List(lib.news) { item in NewsRow(item: item, create: {
                    let p = lib.createProject(news: item); openProject(p.id)
                }) }
            }
        }
        .navigationTitle(t("news.title"))
        .toolbar { ToolbarItem { Button { Task { await lib.refreshNews() } } label: { Label(t("news.refresh"), systemImage: "arrow.clockwise") }.disabled(lib.newsLoading) } }
        .task { if lib.news.isEmpty { await lib.refreshNews() } }
    }
}

@MainActor struct NewsRow: View {
    let item: NewsItem
    var create: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let s = item.image, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                    case .empty: Color.secondary.opacity(0.15).frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                    default: EmptyView()          // the image failed to load (some CDNs block it): don't leave a gray gap
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.isError ? "⚠︎ " + t("news.sourceError", ["name": item.title]) : item.title).font(.headline)
                Text(item.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                if !item.isError { Text(item.source).font(.caption).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 8)
            if !item.isError { Button(t("news.create"), action: create).buttonStyle(.borderedProminent) }
        }
        .padding(.vertical, 6)
    }
}
