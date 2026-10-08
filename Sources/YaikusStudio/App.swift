import SwiftUI
import YaikusCore

@main
struct YaikusStudioApp: App {
    @State private var library: Library
    @State private var mcp: MCPServer

    init() {
        let lib = Library()
        _library = State(initialValue: lib)
        _mcp = State(initialValue: MCPServer(library: lib))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(mcp)
                .frame(minWidth: 860, minHeight: 560)
                .task {
                    Strings.shared.code = library.uiLanguage
                    if library.settings.mcp.enabled { mcp.start(port: library.settings.mcp.port) }
                }
        }
        .defaultSize(width: 1180, height: 780)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
