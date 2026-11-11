import AppKit
import SwiftUI

/// Entry point. `--scan` prints the detected state to the console and exits.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--scan") {
            ScanDump.run()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--icon-preview"),
           CommandLine.arguments.count > index + 1 {
            IconPreview.write(to: CommandLine.arguments[index + 1])
            return
        }
        if CommandLine.arguments.contains("--hooks") {
            print(HookInstaller.status().text)
            return
        }
        if CommandLine.arguments.contains("--install-hooks") {
            do { try HookInstaller.install(); print(HookInstaller.status().text) }
            catch { print("Failed: \(error.localizedDescription)") }
            return
        }
        if CommandLine.arguments.contains("--uninstall-hooks") {
            do { try HookInstaller.uninstall(); print(HookInstaller.status().text) }
            catch { print("Failed: \(error.localizedDescription)") }
            return
        }
        ClaudeMonitorApp.main()
    }
}

struct ClaudeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let store = SessionStore.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            MenuBarLabel(state: store.headlineState, count: store.badgeCount)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, no window at launch — the app lives in the menu bar.
        NSApp.setActivationPolicy(.accessory)
        SessionStore.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionStore.shared.stop()
    }
}
