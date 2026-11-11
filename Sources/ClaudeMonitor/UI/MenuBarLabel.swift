import SwiftUI

/// Das Symbol in der Menüleiste: ruhig ohne Punkt, sonst mit Punkt und Anzahl.
struct MenuBarLabel: View {
    let state: SessionState?
    let count: Int

    /// Über @AppStorage, damit das Symbol sofort wechselt, wenn es in den
    /// Einstellungen umgestellt wird.
    @AppStorage("menuBarSymbol") private var symbol = MenuBarIcon.defaultSymbol

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.image(for: state, symbol: symbol))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: state?.needsAttention == true ? .bold : .semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let state else { return "Claude Monitor — keine aktive Session" }
        return "Claude Monitor — \(count) × \(state.title)"
    }
}
