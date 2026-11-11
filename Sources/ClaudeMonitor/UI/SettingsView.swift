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
                Toggle("Mitteilung, wenn eine Session auf dich wartet", isOn: $notificationsEnabled)
                Toggle("Bei der Anmeldung starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            } footer: {
                Text("Mitteilungen kommen nur beim Übergang nach „wartet auf dich“ — nie während des Arbeitens.")
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

            // Alle Zustände nebeneinander, damit die Wahl mit Punkt beurteilbar ist.
            HStack(spacing: 14) {
                ForEach(previewStates, id: \.self) { state in
                    VStack(spacing: 4) {
                        Image(nsImage: MenuBarIcon.image(for: state, symbol: menuBarSymbol))
                        Text(state?.title ?? "Ruhig")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 2)
        } header: {
            Text("Menüleiste")
        } footer: {
            Text("Feingliedrige Symbole fehlen in der Liste — sie verschmieren bei 16 Pixeln zu einem Fleck.")
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
                Text("Eigener Befehl …").tag(TerminalLauncher.customID)
            }

            if terminalBundleID == TerminalLauncher.customID {
                TextField("Befehl", text: $terminalCommand, prompt: Text(TerminalLauncher.defaultCommand))
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
                Button("Testen") { store.openInTerminal(directory: testDirectory) }
                    .buttonStyle(.glass)
            }
        } header: {
            Text("Terminal")
        } footer: {
            Text(terminalBundleID == TerminalLauncher.customID
                 ? "{dir} wird durch den Projektordner ersetzt, bereits in Anführungszeichen."
                 : "Wird für „Im Terminal öffnen“ im Popover benutzt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Nicht jedes Terminal nimmt einen Ordner über Launch Services entgegen.
    private var folderWarning: String? {
        guard terminalBundleID != TerminalLauncher.customID,
              let terminal = TerminalLauncher.installed().first(where: { $0.id == terminalBundleID }),
              !terminal.acceptsFolders
        else { return nil }
        return "\(terminal.name) nimmt laut seinem Bundle keine Ordner entgegen — es startet, wechselt aber nicht in den Projektordner. Dafür „Eigener Befehl“ nehmen."
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
                    Button("Entfernen") { store.uninstallHooks() }
                        .buttonStyle(.glass)
                } else {
                    Button("Hooks eintragen") { store.installHooks() }
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Hooks")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("""
                Ohne Hooks liest die App nur die Transkripte. „Arbeitet“ erkennt sie damit \
                zuverlässig, „wartet auf Freigabe“ aber nur geschätzt: eine hängende \
                Berechtigungsabfrage sieht im Transkript aus wie ein langer Werkzeugaufruf.
                """)
                Text("""
                Eingetragen wird ein Skript unter ~/.claude/monitor/hook.sh für \
                \(HookInstaller.events.joined(separator: ", ")). Vorhandene Hooks bleiben \
                stehen, von settings.json wird vorher eine Sicherung angelegt.
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
                .accessibilityLabel(isComplete ? "Hooks eingetragen" : "Hooks fehlen")
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
