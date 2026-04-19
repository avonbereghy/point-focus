import AppKit

final class PickerOverlayWindow: NSWindow {
    var onPick: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(axTopLeftFrame frame: CGRect) {
        let primaryMaxY = (NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main!).frame.maxY
        let nsFrame = NSRect(
            x: frame.minX,
            y: primaryMaxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
        super.init(contentRect: nsFrame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        hasShadow = false
        isMovable = false

        let view = PickerOverlayView(frame: NSRect(origin: .zero, size: nsFrame.size))
        view.onPick = { [weak self] p in self?.onPick?(p) }
        view.onCancel = { [weak self] in self?.onCancel?() }
        contentView = view
    }
}
