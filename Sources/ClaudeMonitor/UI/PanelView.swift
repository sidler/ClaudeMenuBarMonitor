import SwiftUI

struct PanelView: View {
    let store: SessionStore

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
                        group("Wartet auf dich", store.waiting, tint: Theme.waiting)
                        group("Arbeitet", store.working, tint: nil)
                        group("Ruht", store.resting, tint: nil)
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

    // MARK: - Höhe

    /// Eine ScrollView hat keine Eigenhöhe. In einem Fenster, das sich auf seinen Inhalt
    /// zusammenzieht, fiele sie auf null zusammen — also die Höhe selbst ausrechnen und
    /// bei `panelMaxHeight` kappen, ab dann wird gescrollt.
    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 48
        let groupHeader: CGFloat = 26
        let groups = [store.waiting, store.working, store.resting].count { !$0.isEmpty }
        let content = CGFloat(store.sessions.count) * rowHeight + CGFloat(groups) * groupHeader + 12
        return min(content, Theme.panelMaxHeight)
    }

    // MARK: - Teile

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
            SettingsLink {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Einstellungen")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func group(_ title: String, _ sessions: [Session], tint: Color?) -> some View {
        if !sessions.isEmpty {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(tint ?? .secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 2)

            ForEach(sessions) { session in
                SessionRow(
                    session: session,
                    now: store.now,
                    isSelected: store.selectedID == session.id
                ) {
                    store.selectedID = store.selectedID == session.id ? nil : session.id
                }
                // Der Modifier gehört an die Zeile: am Gesamtfenster angebracht,
                // klappte das Popover unten am Panel auf statt neben dem Eintrag.
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

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("Keine Session der letzten 24 Stunden")
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
                    Text("Aktualisiert vor \(Fmt.elapsed(since: lastScan, now: store.now))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }

            HStack(spacing: 8) {
                Button("Projektordner") {
                    NSWorkspace.shared.open(store.config.projectsRoot)
                }
                .buttonStyle(.glass)

                Spacer()

                Button("Beenden") {
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
