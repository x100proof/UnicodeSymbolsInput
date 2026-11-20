import Cocoa

/// The suggestion list under the text being typed.
///
/// It's this process's own floating window, not part of the app, so it works
/// wherever the input method does. The app only tells us where the text is
/// (`IMKTextInput.attributes(forCharacterIndex:lineHeightRectangle:)`); when it
/// can't, the panel goes next to the mouse pointer instead. It never takes
/// focus or mouse clicks: everything is driven from the keyboard.
final class CandidatePanel {
    static let shared = CandidatePanel()

    static let visibleRows = 8

    private let panel: NSPanel
    private let list = ListView()

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // ListView paints its own solid background: a translucent (vibrancy) one
        // takes on the colour of whatever is behind it, so over a dark terminal
        // it turned mid-grey and the grey text on it was hard to read.
        let container = NSView()
        container.addSubview(list)
        panel.contentView = container
    }

    func hide() { panel.orderOut(nil) }

    func show(candidates: [Candidate], highlighted: Int?, typed: String, near caret: NSRect?) {
        list.update(candidates: candidates, highlighted: highlighted, typed: typed)
        let size = list.fittingSize
        list.frame = NSRect(origin: .zero, size: size)

        // Below the line of text, left-aligned with it; above it if there's no room.
        let anchor = caret ?? NSRect(origin: NSEvent.mouseLocation, size: NSSize(width: 0, height: 0))
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 10_000, height: 10_000)
        let gap: CGFloat = caret == nil ? 16 : 4
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - gap - size.height)
        if origin.y < visible.minY { origin.y = anchor.maxY + gap }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }
}

/// Draws the rows: symbol, then command; the row Space would insert is
/// highlighted. A footer gives the keys and the position in a long list.
private final class ListView: NSView {
    private var rows: [Candidate] = []
    private var first = 0
    private var highlighted: Int?
    private var total = 0
    private var message: String?
    private var footer = ""

    private let rowHeight: CGFloat = 26
    private let footerHeight: CGFloat = 22
    private let padding: CGFloat = 6
    private let symbolWidth: CGFloat = 34
    private let symbolFont = NSFont.systemFont(ofSize: 17)
    private let commandFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let smallFont = NSFont.systemFont(ofSize: 11)

    override var isFlipped: Bool { true }

    func update(candidates: [Candidate], highlighted: Int?, typed: String) {
        total = candidates.count
        self.highlighted = highlighted
        if candidates.isEmpty {
            rows = []
            message = "No command starts with \\\(typed)"
            footer = "Space types it as is"
        } else {
            message = nil
            // Scroll so the highlighted row stays in view.
            let n = CandidatePanel.visibleRows
            let h = highlighted ?? 0
            first = min(max(0, h - n + 1), max(0, total - n))
            if h < first { first = h }
            rows = Array(candidates[first..<min(total, first + n)])
            let position = highlighted.map { "\($0 + 1) of \(total)" } ?? "\(total) match\(total == 1 ? "" : "es")"
            footer = "⇥ complete   ↑↓ choose   ␣ insert   ·   \(position)"
        }
        needsDisplay = true
    }

    override var fittingSize: NSSize {
        let commandWidth = rows.map { width($0.command, commandFont) + 6 }.max() ?? 0
        let messageWidth = message.map { width($0, commandFont) } ?? 0
        let footerWidth = width(footer, smallFont)
        let content = max(symbolWidth + commandWidth, messageWidth, footerWidth, 180)
        let lines = message == nil ? CGFloat(rows.count) : 1
        return NSSize(width: ceil(content + 2 * padding + 8),
                      height: ceil(lines * rowHeight + footerHeight + 2 * padding))
    }

    private func width(_ s: String, _ font: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    override func draw(_ dirtyRect: NSRect) {
        // Opaque, appearance-aware background (white-ish in light mode, dark in
        // dark mode) with a hairline border, so text contrast never depends on
        // what's behind the panel.
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.textBackgroundColor.setFill()
        outline.fill()
        NSColor.separatorColor.setStroke()
        outline.lineWidth = 1
        outline.stroke()

        var y = padding
        if let message {
            draw(message, font: commandFont, color: .secondaryLabelColor,
                 in: NSRect(x: padding + 4, y: y, width: bounds.width, height: rowHeight))
            y += rowHeight
        }
        for (i, row) in rows.enumerated() {
            let rect = NSRect(x: padding, y: y, width: bounds.width - 2 * padding, height: rowHeight)
            let isOn = first + i == highlighted
            if isOn {
                NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            }
            let text: NSColor = isOn ? .white : .labelColor
            draw(row.symbol, font: symbolFont, color: text, centeredIn:
                    NSRect(x: rect.minX, y: rect.minY, width: symbolWidth, height: rowHeight))
            draw("\\" + row.command, font: commandFont, color: text,
                 in: NSRect(x: rect.minX + symbolWidth, y: rect.minY, width: rect.width - symbolWidth, height: rowHeight))
            y += rowHeight
        }
        NSColor.separatorColor.setFill()
        NSRect(x: padding, y: y + 2, width: bounds.width - 2 * padding, height: 1).fill()
        draw(footer, font: smallFont, color: .secondaryLabelColor,
             in: NSRect(x: padding + 4, y: y + 3, width: bounds.width, height: footerHeight))
    }

    private func draw(_ s: String, font: NSFont, color: NSColor, in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let h = (s as NSString).size(withAttributes: attrs).height
        (s as NSString).draw(at: NSPoint(x: rect.minX, y: rect.midY - h / 2), withAttributes: attrs)
    }

    private func draw(_ s: String, font: NSFont, color: NSColor, centeredIn rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (s as NSString).size(withAttributes: attrs)
        (s as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                             withAttributes: attrs)
    }
}
