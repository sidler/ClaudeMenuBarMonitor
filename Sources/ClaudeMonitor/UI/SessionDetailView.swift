import SwiftUI

/// Das Popover: kurz, prägnant, immer am aktuellen Stand der Session.
struct SessionDetailView: View {
    let store: SessionStore
    let sessionID: Session.ID

    private var session: Session? {
        store.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        if let session {
            VStack(alignment: .leading, spacing: 0) {
                head(session)
                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    if session.state.needsAttention { waitingCard(session) }
                    numbers(session)
                    if let fraction = session.contextFraction { context(session, fraction: fraction) }
                    if !session.recent.isEmpty { history(session) }
                    actions(session)
                }
                .padding(14)
            }
            .frame(width: 400)
        } else {
            Text("Session ended")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(20)
        }
    }

    private func head(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StateDot(state: session.state, size: 9)
                Text(session.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(session.state.title)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(session.state.tint.opacity(0.16)))
                    .foregroundStyle(session.state.tint)
            }

            Text(subtitle(session))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func subtitle(_ session: Session) -> String {
        [session.cwd.map(shortPath), session.gitBranch]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count - 1) : path
    }

    private func waitingCard(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(session.state == .awaitingApproval ? "Permission requested" : "Question") — \(Fmt.elapsed(since: session.stateSince, now: store.now)) ago")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.3)
                .textCase(.uppercase)
                .foregroundStyle(session.state.tint)

            Text(session.detail ?? session.headline)
                .font(.system(size: 12, design: session.state == .awaitingApproval ? .monospaced : .default))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassEffect(.regular.tint(session.state.tint.opacity(0.18)), in: .rect(cornerRadius: 9))
    }

    private func numbers(_ session: Session) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 12) {
            metric("Model", Fmt.modelName(session.model) ?? "—")
            metric("Running", session.startedAt.map { Fmt.elapsed(since: $0, now: store.now) } ?? "—")
            metric("Prompts", "\(session.turns)")
            metric("Cost", session.costUSD.map(Fmt.money) ?? "—")
            metric("Changes", "+\(session.linesAdded) / −\(session.linesRemoved)")
            metric("Tools", "\(session.toolCalls)")
        }
        .overlay(alignment: .bottomLeading) {
            Text("Prompts and tools counted from the tail of the transcript")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .offset(y: 13)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func context(_ session: Session, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Context window")
                    .font(.system(size: 10, weight: .medium))
                    .kerning(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fraction * 100)) % · \(Fmt.tokens(session.contextTokens ?? 0)) / \(Fmt.tokens(session.contextLimit))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(fraction > 0.85 ? Theme.waiting : Theme.working)
        }
    }

    private func history(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Recent steps")
                .font(.system(size: 10, weight: .medium))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            ForEach(session.recent.prefix(4)) { item in
                HStack(alignment: .top, spacing: 9) {
                    Circle()
                        .fill(item.id == session.recent.first?.id ? session.state.tint : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)
                    Text(label(for: item))
                        .font(.system(size: 12))
                        .foregroundStyle(item.id == session.recent.first?.id ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(Fmt.clock(item.at))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func label(for item: ActivityItem) -> String {
        switch item.kind {
        case .prompt: "You: \(item.text)"
        case .tool, .answer, .notice: item.text
        }
    }

    private func actions(_ session: Session) -> some View {
        HStack(spacing: 8) {
            Button("Open in terminal") { store.openInTerminal(session) }
                .buttonStyle(.glassProminent)
                .disabled(session.cwd == nil)

            Button("Copy resume command") { store.copyResumeCommand(session) }
                .buttonStyle(.glass)

            Button {
                store.reveal(session)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Reveal in Finder")
        }
        .controlSize(.small)
    }
}
