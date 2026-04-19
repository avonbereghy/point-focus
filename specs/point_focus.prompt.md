# PointFocus — Implementation Prompt

## Context

PointFocus is a greenfield macOS menu-bar utility that warps the mouse cursor to a configurable point in the focused window on every Cmd+Tab switch. See `specs/point_focus.spec.md` for the full spec including functional requirements (EARS), acceptance criteria, and implementation checklist.

- Repo: ``
- Bundle id: `com.avb.pointfocus`
- Target: macOS 14+, Swift 6, universal binary (arm64 + x86_64)
- Build: SwiftPM executable target → `build.sh` wraps into `PointFocus.app` → installs to `~/Applications/`

## Architecture Overview

**Layers (strict — do not cross):**

```
┌──────────────────────────────────────────────────────┐
│  UI (SwiftUI + AppKit)                               │
│    MenuBarController  SettingsWindowController       │
│    SettingsView       OnboardingWindowController     │
│    PickerCoordinator  PickerOverlayWindow/View       │
├──────────────────────────────────────────────────────┤
│  Orchestrator                                        │
│    FocusRouter                                       │
├──────────────────────────────────────────────────────┤
│  Services                                            │
│    EventTapService      FocusedWindowProbe           │
│    CursorWarpService    SettingsStore                │
│    PermissionsService   LaunchAtLoginService         │
├──────────────────────────────────────────────────────┤
│  Models                                              │
│    FocusPoint  Settings                              │
└──────────────────────────────────────────────────────┘
```

**Patterns:**

- `@Observable` macro (Swift 5.9+) for `SettingsStore` and `PermissionsService` — SwiftUI views bind directly.
- **One** `FocusRouter` actor-like `@MainActor` orchestrator; services are injectable. No global singletons except a single `App` entry point.
- Async interfaces where possible (`async` picker, `AsyncStream<Event>` from `EventTapService`).
- Services are value-producing, side-effect-limited, and mock-free — tests exercise them directly against real macOS APIs where feasible.

## Key Files

| File | Role |
|------|------|
| `Package.swift` | SwiftPM manifest — executable target `PointFocus`, `.macOS(.v14)` |
| `Sources/PointFocus/main.swift` | Entry — applies Info.plist as resources, boots `AppDelegate` |
| `Sources/PointFocus/AppDelegate.swift` | Wires services, starts `FocusRouter`, owns `MenuBarController` |
| `Sources/PointFocus/Models/FocusPoint.swift` | Clamped `(x,y) ∈ [0,1]²` |
| `Sources/PointFocus/Models/Settings.swift` | Codable settings payload |
| `Sources/PointFocus/Services/SettingsStore.swift` | `@Observable`, UserDefaults-backed, debounced writes |
| `Sources/PointFocus/Services/EventTapService.swift` | `CGEventTap`, emits `.cmdTabReleased` |
| `Sources/PointFocus/Services/FocusedWindowProbe.swift` | AX API → `(bundleID, frame)?` |
| `Sources/PointFocus/Services/CursorWarpService.swift` | `warp(to:)` with display clamping |
| `Sources/PointFocus/Services/PermissionsService.swift` | `@Observable` AX + Input Monitoring |
| `Sources/PointFocus/Services/LaunchAtLoginService.swift` | `SMAppService.mainApp` wrapper |
| `Sources/PointFocus/Services/FocusRouter.swift` | Orchestrator (events → probe → warp) |
| `Sources/PointFocus/UI/MenuBarController.swift` | `NSStatusItem` + menu |
| `Sources/PointFocus/UI/SettingsView.swift` | Main SwiftUI settings surface |
| `Sources/PointFocus/UI/SettingsWindowController.swift` | `NSWindowController` wrapping `SettingsView` |
| `Sources/PointFocus/UI/AppOverrideRow.swift` | One row per per-app override |
| `Sources/PointFocus/UI/OnboardingView.swift` | Permission checklist |
| `Sources/PointFocus/UI/OnboardingWindowController.swift` | Window for first-run and revocation |
| `Sources/PointFocus/UI/Picker/PickerCoordinator.swift` | Async picker driver |
| `Sources/PointFocus/UI/Picker/PickerOverlayWindow.swift` | Borderless transparent `NSWindow` |
| `Sources/PointFocus/UI/Picker/PickerOverlayView.swift` | Crosshair + HUD + click/keyDown |
| `Resources/Info.plist` | `LSUIElement=YES`, usage strings, bundle id, version |
| `Resources/PointFocus.entitlements` | Empty (no sandbox) |
| `build.sh` | swift build → .app bundle → ad-hoc sign → copy to ~/Applications/ |
| `README.md` | Install + permissions + uninstall |

## What to Build

### Models (`Sources/PointFocus/Models/`)

**`FocusPoint.swift`**
```swift
struct FocusPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    init(x: Double, y: Double) {
        self.x = max(0, min(1, x))
        self.y = max(0, min(1, y))
    }
    static let center = FocusPoint(x: 0.5, y: 0.5)
}
```

**`Settings.swift`**
```swift
struct Settings: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var launchAtLogin: Bool = false
    var globalPoint: FocusPoint = .center
    var overrides: [String: FocusPoint] = [:]   // key = bundleID
    static let `default` = Settings()
}
```

### Services (`Sources/PointFocus/Services/`)

**`SettingsStore.swift`** — `@Observable` class. UserDefaults key: `com.avb.pointfocus.v1`. Public API:
```swift
@Observable @MainActor
final class SettingsStore {
    private(set) var settings: Settings
    init(defaults: UserDefaults = .standard)
    func update(_ mutate: (inout Settings) -> Void)  // debounced persist ≥200ms
    func focusPoint(for bundleID: String) -> FocusPoint  // override ?? global
}
```
Implementation: decode on init with `try? JSONDecoder().decode` falling back to `.default` on failure. Use a `DispatchWorkItem` debounce — cancel and reschedule on each mutation.

**`PermissionsService.swift`** — `@Observable` class polling every 1s via a `Timer` on main RunLoop:
```swift
enum PermissionState { case granted, denied, unknown }

@Observable @MainActor
final class PermissionsService {
    private(set) var accessibility: PermissionState = .unknown
    private(set) var inputMonitoring: PermissionState = .unknown
    func refreshNow()
    func startPolling()
    func stopPolling()
}
```
Uses `AXIsProcessTrustedWithOptions(nil)` and `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` (from `<IOKit/hid/IOHIDLib.h>`).

**`EventTapService.swift`** — Installs `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: cb, userInfo: self)`. Event mask: `keyDown | flagsChanged`. Internal state machine:
- `flagsChanged` → store `cmdIsDown` from `.maskCommand` bit.
- `keyDown` keycode 48 while `cmdIsDown` → set `tabPending = true`.
- `flagsChanged` to cmd-up while `tabPending` → emit `.cmdTabReleased`, reset `tabPending`.

Emission: `AsyncStream<Event> { continuation = $0; ... }` exposed as `var events: AsyncStream<Event>`. The C callback bridges back to the Swift instance via `Unmanaged.passUnretained(self).toOpaque()`.

**`FocusedWindowProbe.swift`** — Single function:
```swift
@MainActor
enum FocusedWindowProbe {
    struct Result { let bundleID: String; let frame: CGRect }
    static func current() -> Result?
}
```
Implementation:
1. `let sys = AXUIElementCreateSystemWide()`
2. `AXUIElementCopyAttributeValue(sys, kAXFocusedApplicationAttribute as CFString, &app)` → `AXUIElement`
3. `AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window)`
4. Read position + size as `AXValue` → `CGPoint` / `CGSize` via `AXValueGetValue`.
5. Get pid with `AXUIElementGetPid`, then `NSRunningApplication(processIdentifier:)?.bundleIdentifier`.
6. **AX coords are top-left origin**; leave as-is — we'll convert at warp time.

**`CursorWarpService.swift`**
```swift
@MainActor
enum CursorWarpService {
    static func warp(to axTopLeftPoint: CGPoint)
}
```
Implementation:
1. Convert AX-top-left to Quartz screen coords: `let y = NSScreen.screens.map(\.frame.maxY).max()! - axY` (actually use primary display height since AX uses top-left of primary display as origin — use `CGDisplayPixelsHigh(CGMainDisplayID())` as reference height, matching Apple's conversion).
2. Clamp into the nearest `NSScreen.frame`.
3. `CGWarpMouseCursorPosition(point)`; `CGAssociateMouseAndMouseCursorPosition(1)`.

**`FocusRouter.swift`** — `@MainActor` class:
```swift
@MainActor
final class FocusRouter {
    init(store: SettingsStore, events: EventTapService, perms: PermissionsService)
    func start()
}
```
Start subscribes to `events.events` in a `Task`. On each `.cmdTabReleased`:
- Guard `store.settings.enabled == true`.
- Guard `perms.accessibility == .granted && perms.inputMonitoring == .granted`.
- `guard let w = FocusedWindowProbe.current() else { return }`.
- `let rp = store.focusPoint(for: w.bundleID)`.
- `let target = CGPoint(x: w.frame.minX + w.frame.width * rp.x, y: w.frame.minY + w.frame.height * rp.y)`.
- `CursorWarpService.warp(to: target)`.

**`LaunchAtLoginService.swift`** — Thin `SMAppService.mainApp` wrapper; expose `var isEnabled: Bool` computed + `func set(_ on: Bool) throws`.

### UI — Menu Bar (`MenuBarController.swift`)

```swift
@MainActor
final class MenuBarController: NSObject {
    init(store: SettingsStore, perms: PermissionsService, onShowSettings: @escaping () -> Void,
         onShowOnboarding: @escaping () -> Void, onQuit: @escaping () -> Void)
}
```
- Owns `NSStatusItem` variable length.
- Button image: `NSImage(systemSymbolName:...)`:
  - enabled + granted → `"scope"`
  - disabled → `"scope.slash"`
  - missing permissions → `"exclamationmark.triangle"` (accessory color red)
- Left click → toggle `store.settings.enabled`.
- Right / Option click → build `NSMenu` on the fly with enabled check, Settings…, Launch at Login check, Quit.
- Observe `store` and `perms` via `withObservationTracking` to refresh icon.

### UI — Settings (`SettingsView.swift`, `SettingsWindowController.swift`, `AppOverrideRow.swift`)

`SettingsView` — `@Bindable var store: SettingsStore` + `perms: PermissionsService`. Sections:

1. **Status** — enabled `Toggle`, permissions chip (green/red), "Open onboarding" link if red.
2. **Global default** — two `TextField`s with `.decimalPad`-style formatters (`0.00–1.00`), stepper buttons, "Pick on screen…" calling `PickerCoordinator.pickGlobal()`.
3. **Per-app overrides** — `List` of `AppOverrideRow`. Trailing toolbar: "Add app…" button → `NSOpenPanel(directoryURL: /Applications, allowedContentTypes: [.application])` → on selection invoke `PickerCoordinator.pick(bundleID:)`.
4. **Launch at login** — `Toggle` bound to `LaunchAtLoginService`.
5. **Quit PointFocus** button at bottom.

`SettingsWindowController` — single-instance pattern: static shared instance, `showWindow` brings to front.

`AppOverrideRow` — `HStack { icon; VStack{name; bundleID}; Spacer(); pointLabel; Button("Re-pick"); Button("Remove") }`. `pointLabel` → `"x: 0.42  y: 0.17"`.

### UI — Onboarding (`OnboardingView.swift`, `OnboardingWindowController.swift`)

- Checklist:
  - Accessibility — red/green chip + "Open System Settings" button opening `URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")`.
  - Input Monitoring — same pattern with `…?Privacy_ListenEvent`.
- Auto-dismiss when both granted, driven by observation of `PermissionsService`.
- Window controller is single-instance like settings.

### UI — Picker (`PickerCoordinator.swift`, `PickerOverlayWindow.swift`, `PickerOverlayView.swift`)

**`PickerCoordinator`** — public async API:
```swift
@MainActor
final class PickerCoordinator {
    init(store: SettingsStore)
    func pickGlobal() async -> Bool           // returns true if saved
    func pick(bundleID: String) async -> Bool
}
```
Flow for `pick(bundleID:)`:
1. Locate `NSRunningApplication` by bundle id; if nil, `NSWorkspace.shared.openApplication(at:configuration:)` and poll for focused window up to 5s.
2. Call `.activate(options: [.activateAllWindows])`.
3. Poll `FocusedWindowProbe.current()` until `result.bundleID == bundleID` or timeout.
4. Create `PickerOverlayWindow(frame: result.frame)`. Show.
5. `await` the overlay's completion (`withCheckedContinuation`). Result is `CGPoint?` in window-local coordinates (or `nil` if Escape/cancel).
6. If non-nil: compute `FocusPoint(x: p.x/frame.w, y: p.y/frame.h)`, write via `store.update { ... }`.
7. Observe AX notification `kAXWindowMiniaturizedNotification` + app-terminate notification → call overlay's `cancel(error:)`.

**`PickerOverlayWindow`** — subclass of `NSWindow`:
- `init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)`
- `isOpaque = false; backgroundColor = .clear; level = .statusBar; ignoresMouseEvents = false; acceptsMouseMovedEvents = true; hasShadow = false`
- `canBecomeKey = true` (override) so it receives `keyDown`.
- Content view is `PickerOverlayView`.

**`PickerOverlayView`** — `NSView` subclass:
- Tracking area covering `bounds`, `.mouseMoved | .activeAlways`.
- `override func draw(_ rect:)`:
  1. Fill with accent color alpha 0.18.
  2. Stroke border 2pt accent.
  3. Horizontal + vertical 1pt lines intersecting `cursorPoint` (stored `@State` equivalent — plain `var cursorPoint: NSPoint`).
  4. Draw HUD: rounded rect + `"x: 0.42  y: 0.17"` string at `cursorPoint + (16, 16)`, keep in bounds by flipping offset near edges.
- `mouseMoved` → update `cursorPoint` via `convert(event.locationInWindow, from: nil)`, `setNeedsDisplay(bounds)`.
- `mouseDown` → `onPick?(cursorPoint)`.
- `keyDown` with `keyCode == 53` (Escape) → `onCancel?()`.
- Publishers: `var onPick: ((NSPoint) -> Void)?`, `var onCancel: (() -> Void)?`.

### Entry — `main.swift` + `AppDelegate.swift`

**`main.swift`**
```swift
import Cocoa
let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)   // redundant with LSUIElement but safe
app.run()
```

**`AppDelegate.swift`** — wires everything:
```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore()
    let perms = PermissionsService()
    let events = EventTapService()
    let launch = LaunchAtLoginService()
    lazy var picker = PickerCoordinator(store: store)
    lazy var router = FocusRouter(store: store, events: events, perms: perms)
    var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ n: Notification) {
        perms.refreshNow()
        perms.startPolling()
        if perms.accessibility != .granted || perms.inputMonitoring != .granted {
            OnboardingWindowController.shared.show(perms: perms)
        }
        events.start()
        router.start()
        menuBar = MenuBarController(store: store, perms: perms,
            onShowSettings:   { SettingsWindowController.shared.show(store: self.store, perms: self.perms, picker: self.picker, launch: self.launch) },
            onShowOnboarding: { OnboardingWindowController.shared.show(perms: self.perms) },
            onQuit:           { NSApp.terminate(nil) })
    }
}
```

### Integration Points

- `FocusRouter` is the **only** caller of `CursorWarpService`.
- `MenuBarController`, `SettingsView`, `OnboardingView` are the only callers of `SettingsStore.update` (plus `PickerCoordinator`).
- `PickerCoordinator` is the only caller of `NSWorkspace.shared.openApplication` and the only creator of `PickerOverlayWindow`.
- `PermissionsService` is read-only by every UI surface and by `FocusRouter`.

## Constraints

- **Swift 6** strict concurrency. Keep most types `@MainActor` — this is a UI app, not a throughput-bound service. `EventTapService` callback is a C function pointer; jump back to main via `DispatchQueue.main.async` before touching shared state.
- **No third-party packages.** Apple frameworks only: AppKit, SwiftUI, Observation, ApplicationServices (AX), Carbon (for keycode constants only if needed), IOKit (for Input Monitoring check), ServiceManagement (for Launch at Login).
- **No sandboxing.** Sandboxed apps cannot install a session-level `CGEventTap`.
- **Ad-hoc signing.** `codesign --force --sign -` in `build.sh`. No Developer ID required for V1.
- **Style:**
  - 4-space indent.
  - No trailing whitespace.
  - Filenames match their primary type name.
  - Prefer `enum` with static functions over "service" classes for stateless services (`CursorWarpService`, `FocusedWindowProbe`).
  - Use `@Observable` — do not use `ObservableObject` / `@Published`.
- **No comments** except for non-obvious platform quirks (e.g. AX origin convention).

## Build & Test

**Build (dev):**
```
swift build -c debug
swift run PointFocus    # runs from SwiftPM — no LSUIElement in dev, but functional
```

**Build (release / deploy):**
```
./build.sh
# → build/PointFocus.app
# → ~/Applications/PointFocus.app (installed, ad-hoc signed)
```

`build.sh` outline:
```bash
#!/usr/bin/env bash
set -euo pipefail
swift build -c release --arch arm64 --arch x86_64
APP="build/PointFocus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/PointFocus "$APP/Contents/MacOS/PointFocus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# copy any icon assets once we add them
codesign --force --sign - --entitlements Resources/PointFocus.entitlements "$APP"
rm -rf "$HOME/Applications/PointFocus.app"
cp -R "$APP" "$HOME/Applications/"
echo "Installed to $HOME/Applications/PointFocus.app"
```

**Manual verification flow (after first build & permissions granted):**
1. Launch `~/Applications/PointFocus.app`. Icon appears in menu bar.
2. Open Terminal, then Cmd+Tab to Safari, release. Cursor lands near Safari window center.
3. Open PointFocus settings, add Terminal override via Pick on screen, click on terminal prompt line.
4. Cmd+Tab to Terminal → cursor lands on prompt.
5. Resize Terminal → Cmd+Tab again → cursor still lands on prompt (relative sticks).
6. Left-click menu bar icon → icon becomes `scope.slash`, Cmd+Tab no longer warps.
7. Revoke AX permission via `tccutil reset Accessibility com.avb.pointfocus` → icon becomes warning, warping paused.

## Dependencies

**Sequential (Wave 0 — foundation):** `Package.swift` → Models → `SettingsStore`, `PermissionsService`, `CursorWarpService`, `FocusedWindowProbe` (independent siblings, can be co-built serially in one pass).

**Parallelizable (Wave 1):**
- **Track A — Event pipeline:** `EventTapService`, `FocusRouter`
- **Track B — Menu bar + settings UI:** `MenuBarController`, `SettingsWindowController`, `SettingsView`, `AppOverrideRow`, `LaunchAtLoginService`
- **Track C — Onboarding:** `OnboardingView`, `OnboardingWindowController`
- **Track D — Picker:** `PickerCoordinator`, `PickerOverlayWindow`, `PickerOverlayView`

Tracks A/B/C/D share only the already-built Wave-0 types. Cross-track coordination: Track B consumes `PickerCoordinator` (Track D) and `LaunchAtLoginService`; expose the signatures above early so Track B can compile against stubs.

**Sequential (Wave 2 — integration):** `main.swift`, `AppDelegate.swift`, `Resources/Info.plist`, `Resources/PointFocus.entitlements`, `build.sh`, `README.md`. Must run last because it imports every track's public types.
