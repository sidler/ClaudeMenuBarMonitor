import AppKit

/// `ClaudeMonitor --icon-preview <datei.png>` rendert jedes wählbare Symbol in allen
/// Zuständen — einmal in echter Menüleistengröße auf dunklem Grund, einmal vergrößert.
enum IconPreview {
    private static let states: [SessionState?] = [nil, .working, .awaitingApproval, .awaitingReply, .aborted]

    static func write(to path: String) {
        let rowHeight: CGFloat = 42
        let labelWidth: CGFloat = 150
        let cellWidth: CGFloat = 62
        let width = labelWidth + CGFloat(states.count) * cellWidth + 20
        let height = CGFloat(MenuBarIcon.choices.count) * rowHeight + 34

        let sheet = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            header(labelWidth: labelWidth, cellWidth: cellWidth)

            for (row, choice) in MenuBarIcon.choices.enumerated() {
                let y = 26 + CGFloat(row) * rowHeight
                draw(choice.name, at: NSPoint(x: 12, y: y + 6), size: 11, weight: .medium)
                // Lange Symbolnamen liefen sonst unter die Kacheln.
                let id = choice.id.count > 24 ? choice.id.prefix(23) + "…" : choice.id[...]
                draw(String(id), at: NSPoint(x: 12, y: y + 20), size: 9, color: NSColor(calibratedWhite: 0.5, alpha: 1), monospaced: true)

                for (column, state) in states.enumerated() {
                    let x = labelWidth + CGFloat(column) * cellWidth
                    let icon = MenuBarIcon.image(for: state, symbol: choice.id)

                    // Dunkler Streifen wie in der Menüleiste.
                    NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
                    NSRect(x: x, y: y, width: cellWidth - 6, height: 34).fill()

                    let light = NSImage(size: icon.size, flipped: false) { rect in
                        icon.draw(in: rect)
                        NSColor.white.set()
                        rect.fill(using: .sourceAtop)
                        return true
                    }
                    light.draw(in: NSRect(
                        x: x + (cellWidth - 6 - icon.size.width) / 2,
                        y: y + (34 - icon.size.height) / 2,
                        width: icon.size.width,
                        height: icon.size.height
                    ))
                }
            }
            return true
        }

        guard let tiff = sheet.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            print("Rendering failed")
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("Written: \(path)")
        } catch {
            print("Write failed: \(error.localizedDescription)")
        }
    }

    private static func header(labelWidth: CGFloat, cellWidth: CGFloat) {
        let titles = ["quiet", "working", "approval", "question", "aborted"]
        for (column, title) in titles.enumerated() {
            draw(title, at: NSPoint(x: labelWidth + CGFloat(column) * cellWidth + 4, y: 8), size: 9,
                 color: NSColor(calibratedWhite: 0.45, alpha: 1))
        }
    }

    private static func draw(
        _ text: String,
        at point: NSPoint,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .black,
        monospaced: Bool = false
    ) {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            .draw(at: point)
    }
}
