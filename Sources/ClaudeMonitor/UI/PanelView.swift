import SwiftUI

struct PanelView: View {
    let store: SessionStore

    @Environment(\.openSettings) private var openSettings

    private func presented(_ id: Session.ID) -> Binding<Bool> {
        Binding(
            get: { store.selectedID == id },
            set: { store.selectedID = $0 ? id : nil }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.sessions.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        group("Waiting for you", store.waiting, tint: Theme.waiting)
                        group("Working", store.working, tint: nil)
                        group("Idle", store.resting, tint: nil, collapsible: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: listHeight)
            }

            Divider()
            footer
        }
        .frame(width: Theme.panelWidth)
    }

    // MARK: - Height

    /// A ScrollView has no intrinsic height. In a window that shrinks to fit its
    /// content it would collapse to zero — so compute the height here and cap it
    /// at `panelMaxHeight`; beyond that it scrolls.
    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 48
        let groupHeader: CGFloat = 26
        let groups = [store.waiting, store.working, store.resting].count { !$0.isEmpty }
        let rows = store.waiting.count + store.working.count + (store.idleExpanded ? store.resting.count : 0)
        let content = CGFloat(rows) * rowHeight + CGFloat(groups) * groupHeader + 12
        return min(content, Theme.panelMaxHeight)
    }

    /// `SettingsLink` opens the window, but an accessory app never takes focus, so it
    /// appeared behind everything else and looked like nothing had happened. Opening it
    /// means activating the app and raising that window by hand.
    private func showSettings() {
        openSettings()
        NSApp.activate()
        DispatchQueue.main.async {
            let settings = NSApp.windows.first {
                ($0.identifier?.rawValue ?? "").localizedCaseInsensitiveContains("settings")
            }
            settings?.makeKeyAndOrderFront(nil)
            settings?.center()
        }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Sessions")
                    .font(.system(size: 13, weight: .semibold))
                Text(store.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: showSettings) {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func group(_ title: String, _ sessions: [Session], tint: Color?, collapsible: Bool = false) -> some View {
        if !sessions.isEmpty {
            if collapsible {
                Button {
                    store.idleExpanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text("\(title) (\(sessions.count))")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(0.6)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        Image(systemName: store.idleExpanded ? "chevron.down" : "chevron.forward")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .accessibilityLabel("\(title), \(sessions.count) sessions, \(store.idleExpanded ? "expanded" : "collapsed")")
            } else {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(tint ?? .secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
            }

            if !collapsible || store.idleExpanded {
                ForEach(sessions) { session in
                    SessionRow(
                        session: session,
                        now: store.now,
                        isSelected: store.selectedID == session.id
                    ) {
                        store.selectedID = store.selectedID == session.id ? nil : session.id
                    }
                    // The modifier belongs on the row: attached to the whole window,
                    // the popover opened at the bottom of the panel instead of next to the entry.
                    .popover(
                        isPresented: presented(session.id),
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .trailing
                    ) {
                        SessionDetailView(store: store, sessionID: session.id)
                    }
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("No sessions in the last 24 hours")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if let lastScan = store.lastScan {
                HStack {
                    Text("Updated \(Fmt.elapsed(since: lastScan, now: store.now)) ago")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }

            HStack(spacing: 8) {
                Button("Project folder") {
                    NSWorkspace.shared.open(store.config.projectsRoot)
                }
                .buttonStyle(.glass)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.glass)
                .keyboardShortcut("q")
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}
