import SwiftUI

/// The five states from the design. Case order = sort order.
enum SessionState: String, Sendable, CaseIterable, Comparable {
    /// A permission prompt is pending (Bash, Edit, MCP tool).
    case awaitingApproval
    /// The turn has finished and ends with a question for the user.
    case awaitingReply
    /// Claude is running a turn.
    case working
    /// Turn stopped, API error, or the process is gone.
    case aborted
    /// An answer is in, nothing is pending.
    case idle

    /// 0 = waiting for you, 1 = working, 2 = idle.
    var group: Int {
        switch self {
        case .awaitingApproval, .awaitingReply: 0
        case .working: 1
        case .aborted, .idle: 2
        }
    }

    var groupTitle: String {
        switch group {
        case 0: "Waiting for you"
        case 1: "Working"
        default: "Idle"
        }
    }

    var title: String {
        switch self {
        case .awaitingApproval: "Needs approval"
        case .awaitingReply: "Awaiting reply"
        case .working: "Working"
        case .aborted: "Aborted"
        case .idle: "Idle"
        }
    }

    /// Needs attention: colors the menu bar symbol and fires a notification.
    var needsAttention: Bool { group == 0 }

    var tint: Color {
        switch self {
        case .awaitingApproval, .awaitingReply: Theme.waiting
        case .working: Theme.working
        case .aborted: Theme.aborted
        case .idle: Theme.resting
        }
    }

    /// Shape of the dot — so color is never the only distinguishing mark.
    enum DotStyle { case filled, ring, hollow }

    var dotStyle: DotStyle {
        switch self {
        case .awaitingApproval, .working: .filled
        case .awaitingReply, .aborted: .ring
        case .idle: .hollow
        }
    }

    static func < (lhs: SessionState, rhs: SessionState) -> Bool {
        guard let l = allCases.firstIndex(of: lhs), let r = allCases.firstIndex(of: rhs) else { return false }
        return l < r
    }
}
