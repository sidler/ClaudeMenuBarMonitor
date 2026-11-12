import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var lastScan: Date?
    /// Clock for the relative time labels; changes once a second.
    private(set) var now: Date = .now

    var config = ScanConfig()
    /// Which row the popover shows. Kept in the store so the views need no @State.
    var selectedID: Session.ID?

    private(set) var hookStatus: HookInstaller.Status = .notInstalled
    private(set) var hookError: String?
    private(set) var terminalError: String?
    /// Usage across all sessions. Costly to compute, so it runs on its own slow timer.
    private(set) var usage: UsageSnapshot?
    /// Idle sessions are the normal case and rarely what you came to look at.
    var idleExpanded = false
    /// Set by `--demo`. The timers then stay off and nothing overwrites the
    /// fabricated data the store was handed.
    private(set) var isDemo = false

    @ObservationIgnored private var watcher: FSEventWatcher?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var announced: Set<String> = []
    @ObservationIgnored private var usageInFlight = false

    // MARK: - Numbers behind the menu bar symbol

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

    /// What the menu bar symbol shows.
    var headlineState: SessionState? {
        if !waiting.isEmpty { return waiting[0].state }
        if !working.isEmpty { return .working }
        return nil
    }

    var badgeCount: Int { waiting.isEmpty ? working.count : waiting.count }

    // MARK: - Lifecycle

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
        refreshUsage()
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        ticker?.cancel()
        debounce?.cancel()
    }

    /// FSEvents fires in bursts — collect first, then read once.
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
                // Safety net in case FSEvents ever stays silent.
                if ticks % 10 == 0 { self.scheduleRefresh(delay: .zero) }
                // The usage scan reads whole transcripts — every five minutes is plenty.
                if ticks % 300 == 0 { self.refreshUsage() }
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

    /// One notification per session and waiting state — not again on every scan.
    private func announceTransitions(to found: [Session]) {
        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true else { return }
        var seen: Set<String> = []
        for session in found where session.state.needsAttention {
            let key = "\(session.id)-\(session.state.rawValue)-\(Int(session.stateSince.timeIntervalSince1970))"
            seen.insert(key)
            guard !announced.contains(key) else { continue }
            // Don't announce everything retroactively on the first scan after launch.
            if lastScan != nil { Notifier.announce(session) }
            announced.insert(key)
        }
        announced.formIntersection(seen)
    }

    // MARK: - Usage

    func refreshUsage() {
        guard !isDemo, !usageInFlight else { return }
        usageInFlight = true
        let config = config
        Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                UsageReader.snapshot(config)
            }.value
            self?.usage = snapshot
            self?.usageInFlight = false
        }
    }

    /// Called when a popover opens, so the figures are never stale by minutes.
    func refreshUsageIfStale(maxAge: TimeInterval = 60) {
        guard let usage else { return refreshUsage() }
        if Date.now.timeIntervalSince(usage.computedAt) > maxAge { refreshUsage() }
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

    // MARK: - Actions

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

    /// Also used by the Test button in Settings.
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

#if DEBUG
extension SessionStore {
    /// Fills the store with fabricated sessions, so the panel can be shown -- and
    /// photographed for the README -- without anybody's real work in the picture.
    ///
    /// Deliberately not `start()`: no watcher, no ticker, no scan. Nothing here
    /// moves, which is what a screenshot wants.
    func loadDemo(now: Date = .now) {
        isDemo = true
        sessions = DemoData.sessions(now: now)
        usage = DemoData.usage(now: now)
        lastScan = now.addingTimeInterval(-6)
        self.now = now
        hookStatus = .installed
    }
}
#endif
