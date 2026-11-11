import SwiftUI

/// Die fünf Zustände aus dem Entwurf. Reihenfolge der Cases = Sortierreihenfolge.
enum SessionState: String, Sendable, CaseIterable, Comparable {
    /// Eine Berechtigungsabfrage steht offen (Bash, Edit, MCP-Tool).
    case awaitingApproval
    /// Der Turn ist beendet und endet mit einer Rückfrage an den Menschen.
    case awaitingReply
    /// Claude führt gerade einen Turn aus.
    case working
    /// Turn gestoppt, API-Fehler oder Prozess weg.
    case aborted
    /// Antwort liegt vor, nichts ist offen.
    case idle

    /// 0 = wartet auf dich, 1 = arbeitet, 2 = ruht.
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

    /// Verlangt Aufmerksamkeit: färbt das Menüleistensymbol und löst eine Mitteilung aus.
    var needsAttention: Bool { group == 0 }

    var tint: Color {
        switch self {
        case .awaitingApproval, .awaitingReply: Theme.waiting
        case .working: Theme.working
        case .aborted: Theme.aborted
        case .idle: Theme.resting
        }
    }

    /// Form des Punkts — damit Farbe nie das einzige Unterscheidungsmerkmal ist.
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
