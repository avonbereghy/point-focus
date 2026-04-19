import AppKit
import ApplicationServices

@MainActor
enum FocusedWindowProbe {
    struct Result: Sendable {
        let bundleID: String
        let frame: CGRect
    }

    static func current() -> Result? {
        let sys = AXUIElementCreateSystemWide()

        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let appElement = appRef else { return nil }
        let app = appElement as! AXUIElement

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowElement = windowRef else { return nil }
        let window = windowElement as! AXUIElement

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success,
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            return nil
        }

        return Result(bundleID: bundleID, frame: CGRect(origin: origin, size: size))
    }
}
