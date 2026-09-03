import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct STLViewerApp: App {
    @StateObject private var store = ModelStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .windowStyle(.titleBar)
        .commands {
            // Replace the default "New" with an "Open…" action.
            CommandGroup(replacing: .newItem) {
                Button("Open STL File…") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    /// Presents an AppKit open panel and loads the chosen STL file.
    @MainActor
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let stl = UTType(filenameExtension: "stl") {
            panel.allowedContentTypes = [stl]
        }
        panel.allowsOtherFileTypes = true

        if panel.runModal() == .OK, let url = panel.url {
            store.load(url: url)
        }
    }
}
