import SwiftUI
import AppKit

@main
struct MoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppViewModel()
    @ObservedObject private var prefs = MolePreferences.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(appModel: appModel)
                .frame(minWidth: 900, minHeight: 650)
                .background(MainWindowAccessor())
                .glassWindowBackground()
                .onReceive(appModel.$showingSettings) { _ in }
        }
        // No default title bar / border: content fills the window; on macOS 26
        // the window itself is a Liquid Glass slab. (.plain needs macOS 15;
        // .automatic + the fullSizeContentView mask below covers macOS 14.)
        .windowToolbarStyle(.unified(showsTitle: false))
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

        // Menu bar mini monitor (Section 11), gated by the General setting.
        // SceneBuilder cannot branch, so visibility is enforced in AppKit:
        // the status item hides itself when the preference is off.
        MenuBarScene(appModel: appModel)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running so the menu bar monitor stays alive.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock-icon click reopens the (hidden) main window.
        if !flag { MainWindow.activate() }
        return true
    }
}

// MARK: - Hide-on-close main window

/// Holds the main window so it can be re-shown after being hidden, and acts
/// as its delegate: closing hides the window instead of destroying it, so the
/// app stays reachable from the menu bar monitor and the Dock icon.
enum MainWindow {
    static weak var window: NSWindow?

    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
        } else if !NSApp.windows.contains(where: { $0.isVisible && !$0.isSheet }) {
            // Window not yet tracked (e.g. first launch ordering): fall back to
            // showing whatever main-ish window exists.
            NSApp.windows.first { $0.frameAutosaveName.isEmpty == false }?.makeKeyAndOrderFront(nil)
        }
    }
}

struct MainWindowAccessor: NSViewRepresentable {
    final class Coordinator: NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            MainWindow.window = sender
            sender.orderOut(nil) // hide, keep the app + window alive
            return false
        }

        func windowDidBecomeMain(_ notification: Notification) {
            MainWindow.window = notification.object as? NSWindow
            GlassWindowChrome.apply(to: MainWindow.window!)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.delegate = context.coordinator
                MainWindow.window = window
                GlassWindowChrome.apply(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
