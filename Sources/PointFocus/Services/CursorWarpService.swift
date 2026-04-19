import AppKit
import CoreGraphics

@MainActor
enum CursorWarpService {
    static func warp(to quartzTopLeftPoint: CGPoint) {
        let target = clampToDisplays(quartzTopLeftPoint)
        CGWarpMouseCursorPosition(target)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // Quartz uses top-left origin at the primary display; NSScreen uses bottom-left.
    // We convert the candidate point into NSScreen's coordinate space for containment
    // checks and nearest-screen clamping, then convert the clamped result back.
    private static func clampToDisplays(_ p: CGPoint) -> CGPoint {
        let screens = NSScreen.screens
        guard let primary = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first else {
            return p
        }
        let primaryMaxY = primary.frame.maxY
        let bottomLeft = CGPoint(x: p.x, y: primaryMaxY - p.y)

        if screens.contains(where: { $0.frame.contains(bottomLeft) }) {
            return p
        }

        let nearest = screens.min { a, b in
            hypot(a.frame.midX - bottomLeft.x, a.frame.midY - bottomLeft.y)
                < hypot(b.frame.midX - bottomLeft.x, b.frame.midY - bottomLeft.y)
        } ?? primary

        let clampedBL = CGPoint(
            x: min(max(bottomLeft.x, nearest.frame.minX + 1), nearest.frame.maxX - 1),
            y: min(max(bottomLeft.y, nearest.frame.minY + 1), nearest.frame.maxY - 1)
        )
        return CGPoint(x: clampedBL.x, y: primaryMaxY - clampedBL.y)
    }
}
