import AppKit
import ApplicationServices

@MainActor
enum FocusedWindowProbe {
    struct Result: Sendable {
        let bundleID: String
        let frame: CGRect
    }

    static func current() -> Result? {
        // Preferred path: system-wide focused app → focused window. Works for
        // native Cocoa apps.
        let sys = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(sys, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
           let appElement = appRef {
            if let r = resolve(app: appElement as! AXUIElement) { return r }
        }

        // Fallback: some non-Cocoa apps (Tauri, winit, Electron variants) don't
        // set kAXFocusedWindow reliably. Ask NSWorkspace which app is frontmost,
        // then probe its AX element directly. Apps that don't register with
        // either of these (certain Rust/Tauri apps) are undetectable without
        // Screen Recording permission — treated as out of scope.
        if let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            return resolve(app: AXUIElementCreateApplication(frontPID))
        }
        return nil
    }

    private static func resolve(app: AXUIElement) -> Result? {
        let window = focusedWindow(for: app) ?? mainWindow(for: app) ?? firstWindow(for: app)
        guard let window else { return nil }

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

    private static func focusedWindow(for app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let element = ref else { return nil }
        return (element as! AXUIElement)
    }

    private static func mainWindow(for app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &ref) == .success,
              let element = ref else { return nil }
        return (element as! AXUIElement)
    }

    private static func firstWindow(for app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let array = ref as? [AXUIElement],
              let first = array.first else { return nil }
        return first
    }
}
