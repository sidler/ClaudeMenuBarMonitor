import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var lastScan: Date?
    /// Taktgeber für die relativen Zeitangaben; ändert sich jede Sekunde.
    private(set) var now: Date = .now

    var config = ScanConfig()
    /// Welche Zeile das Popover zeigt. Liegt im Store, damit die Views ohne @State auskommen.
    var selectedID: Session.ID?

    private(set) var hookStatus: HookInstaller.Status = .notInstalled
    private(set) var hookError: String?
    private(set) var terminalError: String?

    @ObservationIgnored private var watcher: FSEventWatcher?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var announced: Set<String> = []

    // MARK: - Abgeleitete Zahlen fürs Menüleistensymbol

    var waiting: [Session] { sessions.filter { $0.state.group == 0 } }
    var working: [Session] { sessions.filter { $0.state == .working } }
    var resting: [Session] { sessions.filter { $0.state.group == 2 } }

    var summary: String {
        let parts = [
            working.isEmpty ? nil : "\(working.count) working",
            waiting.isEmpty ? nil : "\(waiting.count) waiting",
            resting.isEmpty ? nil : "\(resting.count) idle"
        ].compactMap { $0 }
        return parts.isEmpty ? "No active sessions" : parts.joined(separator: " · ")
    }

    /// Was das Symbol in der Menüleiste zeigt.
    var headlineState: SessionState? {
        if !waiting.isEmpty { return waiting[0].state }
        if !working.isEmpty { return .working }
        return nil
    }

    var badgeCount: Int { waiting.isEmpty ? working.count : waiting.count }

    // MARK: - Lebenszyklus

    func start() {
        Notifier.prepare()
        refreshHookStatus()
        watcher = FSEventWatcher(paths: [
            config.projectsRoot.path(percentEncoded: false),
            HookSpool.directory.path(percentEncoded: false)
        ]) { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        startTicker()
        scheduleRefresh(delay: .zero)
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        ticker?.cancel()
        debounce?.cancel()
    }

    /// FSEvents feuert in Schüben — erst sammeln, dann einmal lesen.
    func scheduleRefresh(delay: Duration = .milliseconds(150)) {
        debounce?.cancel()
        debounce = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.now = .now
                ticks += 1
                // Sicherheitsnetz, falls FSEvents einmal nichts meldet.
                if ticks % 10 == 0 { self.scheduleRefresh(delay: .zero) }
            }
        }
    }

    private func refresh() async {
        let config = config
        let found = await Task.detached(priority: .utility) {
            SessionScanner.scan(config)
        }.value

        announceTransitions(to: found)
        sessions = found
        lastScan = .now
        now = .now
    }

    /// Eine Mitteilung je Session und Wartezustand — nicht bei jedem Scan erneut.
    private func announceTransitions(to found: [Session]) {
        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true else { return }
        var seen: Set<String> = []
        for session in found where session.state.needsAttention {
            let key = "\(session.id)-\(session.state.rawValue)-\(Int(session.stateSince.timeIntervalSince1970))"
            seen.insert(key)
            guard !announced.contains(key) else { continue }
            // Beim ersten Scan nach dem Start nicht nachträglich alles melden.
            if lastScan != nil { Notifier.announce(session) }
            announced.insert(key)
        }
        announced.formIntersection(seen)
    }

    // MARK: - Hooks

    func refreshHookStatus() {
        hookStatus = HookInstaller.status()
    }

    func installHooks() {
        run { try HookInstaller.install() }
    }

    func uninstallHooks() {
        run { try HookInstaller.uninstall() }
    }

    private func run(_ work: () throws -> Void) {
        do {
            try work()
            hookError = nil
        } catch {
            hookError = error.localizedDescription
        }
        refreshHookStatus()
        scheduleRefresh(delay: .zero)
    }

    // MARK: - Aktionen

    func reveal(_ session: Session) {
        guard let cwd = session.cwd else {
            NSWorkspace.shared.activateFileViewerSelecting([session.transcript])
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
    }

    func openInTerminal(_ session: Session) {
        guard let cwd = session.cwd else { return }
        openInTerminal(directory: URL(fileURLWithPath: cwd))
    }

    /// Auch aus den Einstellungen heraus für den Testknopf.
    func openInTerminal(directory: URL) {
        do {
            try TerminalLauncher.open(directory: directory)
            terminalError = nil
        } catch {
            terminalError = error.localizedDescription
        }
    }

    func copyResumeCommand(_ session: Session) {
        let command = "cd \(session.cwd ?? "~") && claude --resume \(session.id)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}

extension SessionStore {
    static let shared = SessionStore()
}
