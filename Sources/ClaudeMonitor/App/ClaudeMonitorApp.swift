import AppKit
import ServiceManagement
import SwiftUI

/// Entry point. The flags are development tools: `--scan` and `--usage` print what
/// the app would show, `--demo` fills it with fabricated sessions, `--screenshots`
/// photographs it for the README.
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
        if CommandLine.arguments.contains("--usage") {
            UsageDump.run()
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
        #if DEBUG
        // A login item can only be withdrawn by a bundle carrying the identifier it
        // was registered under. After the identifier changed, the old registration
        // was left pointing at a build directory with nothing to call back to --
        // this is how such a leftover is taken out.
        if CommandLine.arguments.contains("--unregister-login-item") {
            let service = SMAppService.mainApp
            do {
                try service.unregister()
                print("unregistered \(Bundle.main.bundleIdentifier ?? "?") -- status is now \(service.status.rawValue)")
            } catch {
                print("failed: \(error.localizedDescription)")
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--screenshots"),
           CommandLine.arguments.count > index + 1 {
            Screenshots.run(outputDirectory: CommandLine.arguments[index + 1])
            return
        }
        #endif
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
        #if DEBUG
        // `--demo` fills the panel with fabricated sessions instead of reading the
        // machine's own: the app to look at and click through, with nobody's real
        // work in it.
        if CommandLine.arguments.contains("--demo") {
            SessionStore.shared.loadDemo()
            return
        }
        #endif
        SessionStore.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionStore.shared.stop()
    }
}
