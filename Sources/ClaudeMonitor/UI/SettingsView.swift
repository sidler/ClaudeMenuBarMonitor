import ServiceManagement
import SwiftUI

struct SettingsView: View {
    private let store = SessionStore.shared

    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("terminalBundleID") private var terminalBundleID = "com.apple.Terminal"
    @AppStorage("terminalCommand") private var terminalCommand = TerminalLauncher.defaultCommand
    @AppStorage("menuBarSymbol") private var menuBarSymbol = MenuBarIcon.defaultSymbol

    var body: some View {
        Form {
            symbolSection
            hooksSection
            terminalSection

            Section {
                Toggle("Notify me when a session needs me", isOn: $notificationsEnabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            } footer: {
                Text("Notifications fire only on the transition into a waiting state — never while a session works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .scenePadding()
        .task { store.refreshHookStatus() }
    }

    // MARK: - Symbol

    private var symbolSection: some View {
        Section {
            Picker("Symbol", selection: $menuBarSymbol) {
                ForEach(MenuBarIcon.choices) { choice in
                    HStack(spacing: 8) {
                        Image(nsImage: MenuBarIcon.image(for: .working, symbol: choice.id))
                        Text(choice.name)
                    }
                    .tag(choice.id)
                }
            }

            // Every state side by side — the dot suits some glyphs and crowds others.
            HStack(spacing: 14) {
                ForEach(previewStates, id: \.self) { state in
                    VStack(spacing: 4) {
                        Image(nsImage: MenuBarIcon.image(for: state, symbol: menuBarSymbol))
                        Text(state?.title ?? "Quiet")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 2)
        } header: {
            Text("Menu bar")
        } footer: {
            Text("Finely detailed symbols are left out — at 16 pixels they smear into a blob.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var previewStates: [SessionState?] {
        [nil, .working, .awaitingApproval, .awaitingReply, .aborted]
    }

    // MARK: - Terminal

    private var terminalSection: some View {
        Section {
            Picker("Terminal", selection: $terminalBundleID) {
                ForEach(TerminalLauncher.installed()) { terminal in
                    Text(terminal.name).tag(terminal.id)
                }
                Text("Custom command …").tag(TerminalLauncher.customID)
            }

            if terminalBundleID == TerminalLauncher.customID {
                TextField("Command", text: $terminalCommand, prompt: Text(TerminalLauncher.defaultCommand))
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .top) {
                if let warning = folderWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.waiting)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let error = store.terminalError {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.aborted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Test") { store.openInTerminal(directory: testDirectory) }
                    .buttonStyle(.glass)
            }
        } header: {
            Text("Terminal")
        } footer: {
            Text(terminalBundleID == TerminalLauncher.customID
                 ? "{dir} is replaced with the project folder, already shell-quoted. {dirurl} gives the percent-encoded path."
                 : "Used by “Open in terminal” in the popover.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Not every terminal accepts a folder through Launch Services.
    private var folderWarning: String? {
        guard terminalBundleID != TerminalLauncher.customID,
              let terminal = TerminalLauncher.installed().first(where: { $0.id == terminalBundleID }),
              !terminal.acceptsFolders
        else { return nil }
        return "\(terminal.name) declares no folder support — it will launch but stay in its previous directory. Use a custom command instead."
    }

    private var testDirectory: URL {
        if let cwd = store.sessions.compactMap(\.cwd).first {
            return URL(fileURLWithPath: cwd)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Hooks

    private var hooksSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                StatusGlyph(isComplete: store.hookStatus.isComplete)

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.hookStatus.text)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)

                    if let error = store.hookError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.aborted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if store.hookStatus.isComplete {
                    Button("Remove") { store.uninstallHooks() }
                        .buttonStyle(.glass)
                } else {
                    Button("Install hooks") { store.installHooks() }
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Hooks")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("""
                Without hooks the app only reads transcripts. It detects “working” reliably that \
                way, but “needs approval” is a guess: a pending permission prompt looks exactly \
                like a long-running tool call.
                """)
                Text("""
                Installing writes a script to ~/.claude/monitor/hook.sh and registers it for \
                \(HookInstaller.events.joined(separator: ", ")). Existing hooks stay, and \
                settings.json is backed up first.
                """)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private struct StatusGlyph: View {
        let isComplete: Bool

        var body: some View {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isComplete ? Theme.working : Theme.waiting)
                .imageScale(.medium)
                .padding(.top, 1)
                .accessibilityLabel(isComplete ? "Hooks installed" : "Hooks missing")
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
