import SwiftUI

struct SessionRow: View {
    let session: Session
    let now: Date
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                StateDot(state: session.state)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(session.title)
                            .font(.system(size: 13, weight: session.state.group == 2 ? .medium : .semibold))
                            .foregroundStyle(session.state.group == 2 ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 0)
                        trailing
                    }

                    Text(session.headline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected || session.state.needsAttention {
                RoundedRectangle(cornerRadius: 8)
                    .fill(session.state.tint.opacity(isSelected ? 0.16 : 0.08))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(session.state.title), \(session.headline)")
    }

    @ViewBuilder
    private var trailing: some View {
        switch session.state {
        case .awaitingApproval, .awaitingReply:
            Text("\(badgeWord) · \(Fmt.elapsed(since: session.stateSince, now: now))")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(session.state.tint.opacity(0.16)))
                .foregroundStyle(session.state.tint)
        case .aborted:
            Text("Abgebrochen")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(session.state.tint.opacity(0.14)))
                .foregroundStyle(session.state.tint)
        case .working, .idle:
            Text(Fmt.elapsed(since: session.lastActivity, now: now))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var badgeWord: String {
        session.state == .awaitingApproval ? "Freigabe" : "Rückfrage"
    }
}
