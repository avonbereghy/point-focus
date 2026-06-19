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
           let appElement = asElement(appRef),
           let r = resolve(app: appElement) {
            return r
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
              // The dynamic type of an AX attribute value is controlled by the
              // target app's accessibility server. Verify it really is an
              // AXValue before reading it — a misbehaving app returning some
              // other CFType must yield nil (no warp), not trap the process.
              let posValue = asValue(posRef),
              let sizeValue = asValue(sizeRef) else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success,
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            return nil
        }
        return Result(bundleID: bundleID, frame: CGRect(origin: origin, size: size))
    }

    private static func focusedWindow(for app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref) == .success else { return nil }
        return asElement(ref)
    }

    private static func mainWindow(for app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &ref) == .success else { return nil }
        return asElement(ref)
    }

    private static func firstWindow(for app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return nil }
        // The window list isn't guaranteed to be z-ordered and can include
        // minimized/auxiliary windows. Prefer the first non-minimized window so
        // we don't warp into a window the user can't see; fall back to the first
        // if every window reports minimized (or the attribute is unavailable).
        return windows.first(where: { !isMinimized($0) }) ?? windows.first
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    // CoreFoundation `as?` always succeeds (it reinterprets the pointer without
    // checking), so dynamic type checks must compare CFTypeIDs explicitly. These
    // helpers do that, then force-cast only after the type is confirmed.
    private static func asElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func asValue(_ value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
