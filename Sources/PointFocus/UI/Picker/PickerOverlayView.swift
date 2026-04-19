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
        window?.makeFirstResponder(self)
    }

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
    }

    override func mouseMoved(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let topLeft = CGPoint(x: p.x, y: bounds.height - p.y)
        onPick?(topLeft)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
