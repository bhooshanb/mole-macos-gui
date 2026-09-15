import SwiftUI

@main
struct MoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel)
                .frame(minWidth: 900, minHeight: 650)
                .onReceive(appModel.$showingSettings) { _ in }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Clean…") { appModel.section = .clean }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Apps…") { appModel.section = .apps }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Optimize…") { appModel.section = .optimize }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Analyze…") { appModel.section = .analyze }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Status…") { appModel.section = .status }
                    .keyboardShortcut("5", modifiers: [.command])
            }
            CommandGroup(after: .toolbar) {
                Button("Operation History…") { appModel.openHistory() }
                    .keyboardShortcut("y", modifiers: [.command])
                Divider()
                Button("Settings…") { appModel.openSettings() }
                    .keyboardShortcut(",", modifiers: [.command])
            }
        }

        // Menu bar mini monitor (Section 11). Lives on its own status item.
        MenuBarScene(appModel: appModel)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running so the menu bar monitor stays alive.
        false
    }
}
