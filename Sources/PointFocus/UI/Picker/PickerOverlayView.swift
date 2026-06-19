import AppKit

final class PickerOverlayView: NSView {
    var onPick: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    private var cursorPoint: NSPoint = .zero

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // Start the crosshair at the centre so the picker is usable from the
        // keyboard alone (arrow keys nudge from here) and never sits at (0, 0).
        if cursorPoint == .zero {
            cursorPoint = NSPoint(x: bounds.midX, y: bounds.midY)
        }
        window?.makeFirstResponder(self)
        configureAccessibility()
        announceOpening()
        needsDisplay = true
    }

    // MARK: Accessibility

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Focus point picker")
        setAccessibilityHelp("Move the crosshair with the mouse or arrow keys, then click or press Return to set the focus point. Press Escape to cancel.")
    }

    private func announceOpening() {
        guard let window else { return }
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "Focus point picker opened. Use the mouse or arrow keys to position the crosshair, then click or press Return to set the point. Press Escape to cancel.",
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        bounds.fill()

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        border.stroke()

        let h = NSBezierPath()
        h.move(to: NSPoint(x: bounds.minX, y: cursorPoint.y))
        h.line(to: NSPoint(x: bounds.maxX, y: cursorPoint.y))
        h.lineWidth = 1
        h.stroke()

        let v = NSBezierPath()
        v.move(to: NSPoint(x: cursorPoint.x, y: bounds.minY))
        v.line(to: NSPoint(x: cursorPoint.x, y: bounds.maxY))
        v.lineWidth = 1
        v.stroke()

        let rx = cursorPoint.x / max(bounds.width, 1)
        let ry = 1.0 - (cursorPoint.y / max(bounds.height, 1))
        let text = String(format: "x: %.2f  y: %.2f", rx, ry) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        var origin = NSPoint(x: cursorPoint.x + 16, y: cursorPoint.y + 16)
        if origin.x + size.width + 12 > bounds.maxX { origin.x = cursorPoint.x - size.width - 20 }
        if origin.y + size.height + 8 > bounds.maxY { origin.y = cursorPoint.y - size.height - 20 }
        let bgRect = NSRect(x: origin.x - 6, y: origin.y - 4, width: size.width + 12, height: size.height + 8)
        let bg = NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        bg.fill()
        text.draw(at: origin, withAttributes: attrs)

        drawInstructionBanner()
    }

    /// On-screen guidance so the overlay isn't a context-free full-screen tint:
    /// tells the user how to commit and how to cancel.
    private func drawInstructionBanner() {
        let text = "Click or press Return to set the focus point    ·    Esc to cancel" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        let padX: CGFloat = 14, padY: CGFloat = 9
        let rect = NSRect(
            x: bounds.midX - textSize.width / 2 - padX,
            y: bounds.maxY - textSize.height - 2 * padY - 28,
            width: textSize.width + 2 * padX,
            height: textSize.height + 2 * padY
        )
        let bg = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        bg.fill()
        text.draw(at: NSPoint(x: rect.minX + padX, y: rect.minY + padY), withAttributes: attrs)
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        commit()
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        // Shift = coarse nudge, otherwise a fine 4pt step.
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 20 : 4
        switch event.keyCode {
        case 53: // Escape
            onCancel?()
        case 36, 76: // Return, keypad Enter
            commit()
        case 123: moveCursor(dx: -step, dy: 0) // left arrow
        case 124: moveCursor(dx: step, dy: 0)  // right arrow
        case 125: moveCursor(dx: 0, dy: -step) // down arrow
        case 126: moveCursor(dx: 0, dy: step)  // up arrow
        default:
            super.keyDown(with: event)
        }
    }

    private func moveCursor(dx: CGFloat, dy: CGFloat) {
        cursorPoint.x = min(max(cursorPoint.x + dx, bounds.minX), bounds.maxX)
        cursorPoint.y = min(max(cursorPoint.y + dy, bounds.minY), bounds.maxY)
        needsDisplay = true
    }

    private func commit() {
        let topLeft = CGPoint(x: cursorPoint.x, y: bounds.height - cursorPoint.y)
        onPick?(topLeft)
    }
}
