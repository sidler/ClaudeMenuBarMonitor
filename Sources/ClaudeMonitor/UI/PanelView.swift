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
            usage
            footer
        }
        .frame(width: Theme.panelWidth)
        // A menu surface, and macOS draws no focus ring in a menu. SwiftUI gives the
        // first control in the window keyboard focus as it opens, which put a blue
        // ring around the gear every time the panel appeared.
        .focusEffectDisabled()
        .task { store.refreshUsageIfStale() }
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

    // MARK: - Usage

    /// The five-hour block and the week count for the machine, not for one session —
    /// so they belong here once, not repeated in every popover. What is per-session is
    /// the context window, and that stays in the popover.
    @ViewBuilder
    private var usage: some View {
        if let usage = store.usage {
            VStack(spacing: 5) {
                usageRow(
                    "5-hour block",
                    percent: usage.planFiveHourPercent,
                    tokens: usage.fiveHour.tokens,
                    trailing: usage.fiveHour.resets.map {
                        "resets \(Fmt.clockOrDate($0, now: store.now))\(usage.fiveHour.resetIsEstimate ? "*" : "")"
                    }
                )
                usageRow(
                    "Week",
                    percent: usage.planWeekPercent,
                    tokens: usage.week.tokens,
                    trailing: usage.planSampledAt.map { "sampled \(Fmt.elapsed(since: $0, now: store.now)) ago" }
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 2)
            .help("Percentages come from the plan figures the desktop app sampled; tokens are counted locally, cache reads excluded. * means the reset is estimated from activity.")
        }
    }

    private func usageRow(_ label: String, percent: Int?, tokens: Int, trailing: String?) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)

            if let percent {
                ProgressView(value: min(1, Double(percent) / 100))
                    .progressViewStyle(.linear)
                    .tint(percent >= 80 ? Theme.waiting : Theme.working)
                    .frame(width: 70)
                Text("\(percent) %")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            } else {
                Text("\(Fmt.tokens(tokens)) tokens")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(percent.map { "\($0) percent of plan" } ?? "\(Fmt.tokens(tokens)) tokens")")
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
