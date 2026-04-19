# PointFocus — Feature Spec

#### 3.1 Overview

**Feature name:** PointFocus

**Description:** PointFocus is a macOS menu-bar utility that warps the mouse cursor to a configurable point within the focused window every time the user switches apps via Cmd+Tab. The focus point can be set globally (one default for all apps) and optionally overridden per-app via a screenshot-tool-style picker. The point is stored as a *relative* coordinate `(x, y) ∈ [0,1]²` so it remains meaningful across window resizes and different monitors.

**Target users:** Keyboard-driven macOS power users who want to eliminate the mouse hunt after Cmd+Tab — the cursor lands on the most useful spot of each app (e.g. the editor gutter in VS Code, the prompt in Terminal, the message composer in Messages) without manual pointing.

**User value:** Faster context switches, less RSI, and a repeatable tactile "home" position per app.

---

#### 3.2 Functional Requirements (EARS)

##### Event Tap & Trigger Detection

- **FR-001** — The system shall install a `CGEventTap` on `.cgSessionEventTap` observing `keyDown` and `flagsChanged` events.
- **FR-002** — When the Tab key (keycode `48`) transitions to `keyDown` **while the Command modifier flag is set**, the system shall mark a "switch pending" state.
- **FR-003** — When the Command modifier flag transitions from set to cleared **and** a switch is pending, the system shall (a) clear the pending state and (b) schedule a cursor warp for the newly focused window.
- **FR-004** — When the Command flag is cleared without a prior Tab keyDown during the Command-held window, the system shall not warp the cursor.
- **FR-005** — Where the user presses Cmd+Shift+Tab, the system shall behave identically to Cmd+Tab (the Shift modifier is ignored for trigger detection).
- **FR-006** — Where the user holds Command and presses Tab multiple times before releasing Command, the system shall warp exactly once (on Command release) to the finally focused window.

##### Focused-Window Probe (Accessibility API)

- **FR-010** — When a warp is scheduled, the system shall resolve the focused window via `AXUIElementCreateSystemWide()` → `kAXFocusedApplicationAttribute` → `kAXFocusedWindowAttribute`.
- **FR-011** — The system shall read the focused window's frame via `kAXPositionAttribute` and `kAXSizeAttribute` in absolute screen coordinates (AX top-left origin).
- **FR-012** — Where no focused window is resolvable (e.g. Finder with no open window, permission denied, AX query fails), the system shall skip the warp silently (no cursor movement, no error dialog).
- **FR-013** — The system shall identify the focused application by its `bundleIdentifier` (via `NSRunningApplication(processIdentifier:)` on the AX PID).

##### Cursor Warp

- **FR-020** — Where the focused app has a per-app override, the system shall compute the warp target as `origin + (size.width * rx, size.height * ry)` using the stored relative point `(rx, ry)`.
- **FR-021** — Where no per-app override exists, the system shall use the global default relative point.
- **FR-022** — The system shall warp the cursor via `CGWarpMouseCursorPosition(target)` followed by `CGAssociateMouseAndMouseCursorPosition(1)` to re-link hardware mouse input.
- **FR-023** — Where the computed target point falls outside all active display bounds, the system shall clamp the point to the nearest visible display before warping.

##### Menu-Bar UI

- **FR-030** — The system shall register an `NSStatusItem` in the system menu bar on launch.
- **FR-031** — When the user left-clicks the menu-bar icon, the system shall toggle the enabled state (on ↔ off) and update the icon symbol to reflect the new state.
- **FR-032** — When the user right-clicks (or Option-clicks) the menu-bar icon, the system shall show a menu with: enabled toggle checkmark, "Settings…", "Launch at Login" checkmark, "Quit".
- **FR-033** — Where enabled state is `off`, the system shall still observe events (for UI state) but shall not warp the cursor.

##### Settings Window (SwiftUI)

- **FR-040** — When the user selects "Settings…" from the menu, the system shall open a single SwiftUI window titled "PointFocus".
- **FR-041** — The settings window shall contain: (a) enabled toggle, (b) Launch-at-Login toggle, (c) global-default focus point editor with two numeric fields `x`, `y` (range `0.0–1.0`, step `0.01`) and a "Pick on screen…" button, (d) a list of per-app overrides, (e) an "Add app…" button, (f) a permissions status panel.
- **FR-042** — The per-app override list shall show, per row: app icon, app name, bundle ID, current relative point as `(x, y)`, "Re-pick" button, "Remove" button.
- **FR-043** — When the user clicks "Add app…", the system shall present an `NSOpenPanel` scoped to `/Applications` and `/System/Applications` filtering to `.app` bundles; on selection, an override entry is created with the app's default point inherited from the global default and the picker is launched immediately.

##### Per-App Point Picker (Overlay)

- **FR-050** — When the point picker is launched for an app, the system shall activate the target app via `NSRunningApplication.activate(options: [.activateAllWindows])` so its focused window is raised.
- **FR-051** — Where the target app is not running, the system shall launch it via `NSWorkspace.shared.openApplication` and wait up to 5 seconds for it to register a focused window before cancelling the picker with an inline error.
- **FR-052** — Once the focused window frame is resolved, the system shall present a borderless, transparent `NSWindow` at level `.statusBar` covering exactly the window's frame, tinted with a semi-transparent accent color (alpha ≈ 0.18) and a 2pt accent-color border.
- **FR-053** — The overlay shall draw an edge-to-edge crosshair (1pt horizontal line + 1pt vertical line in accent color) intersecting the current cursor position, updating live on every `mouseMoved` event.
- **FR-054** — The overlay shall display a floating HUD label near the cursor showing the current relative coordinates formatted as `x: 0.42  y: 0.17` with 2 decimal places.
- **FR-055** — When the user left-clicks anywhere on the overlay, the system shall (a) compute the relative point from the click location in the window's frame, (b) persist it as the per-app override, (c) dismiss the overlay, (d) return focus to the settings window.
- **FR-056** — When the user presses the Escape key while the overlay is active, the system shall dismiss the overlay without saving.
- **FR-057** — Where the target app quits or its focused window closes while the picker is active, the system shall dismiss the overlay and show an inline error in settings: "App closed before a point was picked."

##### Permissions Onboarding

- **FR-060** — On launch, the system shall check Accessibility permission via `AXIsProcessTrustedWithOptions` (without the prompt option) and Input Monitoring permission via `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`.
- **FR-061** — Where either permission is `denied` or `unknown`, the system shall show an onboarding window listing the missing permissions with "Open System Settings" buttons deep-linking to the appropriate privacy pane (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` and `…?Privacy_ListenEvent`).
- **FR-062** — While the onboarding window is visible, the system shall poll the permission states every 1 second and automatically advance past each section once granted.
- **FR-063** — Where either permission is revoked while the app is running, the system shall (a) pause all warping, (b) change the menu-bar icon to a warning variant, (c) re-show the onboarding panel for the missing permission on next menu-bar click.

##### Persistence

- **FR-070** — The system shall persist settings to `UserDefaults.standard` under key `com.avb.pointfocus.v1` as a single JSON-encoded payload.
- **FR-071** — The persisted payload shall contain: `enabled: Bool`, `launchAtLogin: Bool`, `globalPoint: {x: Double, y: Double}`, `overrides: [bundleID: {x: Double, y: Double}]`.
- **FR-072** — The system shall debounce writes by ≥ 200 ms when the user edits numeric fields.
- **FR-073** — Where the stored payload is malformed or absent, the system shall initialize defaults: `enabled=true`, `launchAtLogin=false`, `globalPoint=(0.5, 0.5)`, `overrides={}`.

##### Launch at Login

- **FR-080** — Where the user enables Launch at Login, the system shall register the app via `SMAppService.mainApp.register()`.
- **FR-081** — Where the user disables Launch at Login, the system shall call `SMAppService.mainApp.unregister()`.

##### Build / Deploy

- **FR-090** — The project shall build via `./build.sh` producing `PointFocus.app` in `./build/` with a proper `Info.plist` declaring `LSUIElement = true`, `NSAccessibilityUsageDescription`, bundle id `com.avb.pointfocus`, and version `1.0.0`.
- **FR-091** — `./build.sh` shall, on success, copy `PointFocus.app` into `~/Applications/` (replacing any existing copy) and ad-hoc-sign the bundle (`codesign --force --sign -`).

---

#### 3.3 Non-Functional Requirements

| Category       | Requirement |
|----------------|-------------|
| Performance    | Warp-to-screen latency ≤ 30 ms from Command key release. |
| Performance    | CPU usage while idle ≤ 1% on Apple Silicon. |
| Performance    | Overlay crosshair redraws at display refresh rate with no visible lag at cursor speeds up to 1000 px/s. |
| Security       | No network access. All persistence local to `UserDefaults`. No third-party runtime dependencies beyond Apple frameworks. |
| Security       | Event tap operates on `.listenOnly` passthrough — never modifies or drops user events. |
| Usability      | Enabling/disabling via menu-bar click produces immediate visible icon change (< 100 ms). |
| Usability      | Picker overlay dismisses on Escape with no residual artifacts. |
| Memory         | Steady-state RSS ≤ 40 MB. |
| Compatibility  | Target macOS 14 (Sonoma) or later. Swift 6 language mode. Universal binary (arm64 + x86_64). |

---

#### 3.4 Data Sources / Integration Points

| Data | Source | Fields | Example |
|------|--------|--------|---------|
| Key events | `CGEventTap(.cgSessionEventTap)` | keycode, flags, type | `{type: keyDown, keycode: 48, flags: .maskCommand}` |
| Focused app | AX system-wide element | pid, bundleIdentifier | `{pid: 12345, bundleID: "com.apple.Terminal"}` |
| Focused window frame | AX `kAXPosition` + `kAXSize` | origin.x, origin.y, width, height | `{x: 200, y: 100, w: 1200, h: 800}` |
| Running apps | `NSWorkspace.shared.runningApplications` | bundleIdentifier, icon, localizedName, processIdentifier | used for app-picker and re-pick flows |
| Permission state | `AXIsProcessTrustedWithOptions`, `IOHIDCheckAccess` | Bool / enum | `(accessibility: true, inputMonitoring: false)` |
| Settings payload | `UserDefaults.standard` | JSON blob under key `com.avb.pointfocus.v1` | see FR-071 |
| Launch-at-login state | `SMAppService.mainApp.status` | `.enabled / .notRegistered / …` | — |

---

#### 3.5 Error Handling

| Scenario | Behavior | User Message |
|----------|----------|--------------|
| No focused window on warp (e.g. Finder desktop) | Skip warp silently | — |
| AX query returns nil / error | Skip warp silently | — |
| Permission denied for AX or Input Monitoring on launch | Show onboarding window | "PointFocus needs Accessibility and Input Monitoring to detect Cmd+Tab and read window positions." |
| Permission revoked mid-session | Pause warping, change icon to warning | Menu item: "Permissions required — click to fix" |
| Target app not running when user adds override | Attempt launch, wait 5s for focused window | Inline toast: "Couldn't reach {app} — try again after opening it." |
| Target app quits during picker | Dismiss overlay, return to settings | Inline toast: "App closed before a point was picked." |
| Stored settings JSON malformed | Overwrite with defaults | — |
| Event tap fails to install (rare) | Log to stderr, show warning in menu | Menu item: "Event tap failed — restart PointFocus" |
| Computed warp target outside all displays | Clamp to nearest display before warping | — |
| Cmd+Tab while app is globally disabled | Do not warp | — |

---

#### 3.6 Acceptance Criteria

```
AC-1 (happy path — global default) [FR-001, FR-002, FR-003, FR-010, FR-011, FR-021, FR-022]
Given PointFocus is enabled and no per-app override exists for Terminal,
  and the global default point is (0.5, 0.5),
  and Terminal has an open window at origin (100, 100) size 800×600,
When the user presses Cmd+Tab to switch to Terminal and releases Cmd,
Then the cursor is at screen coordinate (500, 400) within 30 ms of Cmd release.
Verify by: place cursor at (0,0), Cmd+Tab to Terminal, assert CGEventSource.mouseLocation == (500, 400) ± 1 px.
```

```
AC-2 (per-app override) [FR-020, FR-042, FR-055]
Given a per-app override for com.apple.Terminal at relative (0.1, 0.9),
  and Terminal window frame is (100, 100, 800, 600),
When the user Cmd+Tabs to Terminal,
Then the cursor is warped to (180, 640).
Verify by: assert cursor position matches after switch.
```

```
AC-3 (hold Cmd, multi-tab, single warp) [FR-006]
Given Chrome and Terminal are both open,
When the user holds Command, presses Tab three times (landing back on Chrome), then releases Command,
Then the cursor is warped exactly once, to Chrome's focus point.
Verify by: count CGWarpMouseCursorPosition calls via instrumentation hook — must equal 1 between Cmd down and Cmd up.
```

```
AC-4 (no focused window) [FR-012]
Given the Finder is frontmost with no open Finder windows,
When the user Cmd+Tabs to Finder,
Then the cursor does not move.
Verify by: record cursor position before/after switch, assert equal.
```

```
AC-5 (picker stores relative point) [FR-050, FR-052, FR-053, FR-055, FR-070]
Given the user clicks "Pick on screen…" for Safari whose window frame is (0, 0, 1000, 800),
When the user clicks at screen coordinate (250, 600) on the overlay,
Then UserDefaults under key com.avb.pointfocus.v1 contains overrides["com.apple.Safari"] == (0.25, 0.75).
Verify by: read UserDefaults immediately after click, decode JSON, assert exact point.
```

```
AC-6 (resize stability) [FR-020]
Given an override for Safari at relative (0.25, 0.75) and Safari window is (0, 0, 1000, 800) — expected warp (250, 600),
When the user resizes Safari to (0, 0, 2000, 1600) then Cmd+Tabs to Safari,
Then the cursor is warped to (500, 1200).
Verify by: scripted resize via AX setValue, then switch, assert cursor position.
```

```
AC-7 (picker cancel on Escape) [FR-056]
Given the picker overlay is visible for Safari,
  and an existing override of (0.5, 0.5) exists for Safari,
When the user presses Escape,
Then the overlay dismisses and the stored override is still (0.5, 0.5).
Verify by: read stored override before/after; assert unchanged; assert no overlay NSWindow on screen.
```

```
AC-8 (permission denied shows onboarding) [FR-060, FR-061]
Given Accessibility permission is denied,
When PointFocus is launched,
Then the onboarding window is visible within 500 ms of launch and shows an "Open System Settings" button deep-linking to the Accessibility pane.
Verify by: revoke permission via tccutil reset Accessibility com.avb.pointfocus, relaunch, observe onboarding window.
```

```
AC-9 (menu-bar toggle pauses warping) [FR-031, FR-033]
Given PointFocus is enabled,
When the user left-clicks the menu-bar icon and the state becomes disabled,
  and the user then Cmd+Tabs to Terminal,
Then the cursor does not move and the menu-bar icon shows the disabled variant.
Verify by: manual click + Cmd+Tab; record cursor position; assert unchanged and icon symbol == "cursorarrow.slash".
```

```
AC-10 (multi-monitor spanning window) [FR-011, FR-023]
Given Safari's window spans two monitors with frame (1800, 0, 1200, 800) crossing the seam at x=1920,
When the user Cmd+Tabs to Safari with global default (0.5, 0.5),
Then the cursor lands at absolute screen (2400, 400).
Verify by: position on secondary display + assertion on cursor location.
```

Every AC above cites at least one FR-ID. Traceability OK.

---

#### 3.7 Implementation Checklist

##### Phase 1 — Core Infrastructure

- [ ] Create `Package.swift` declaring executable target `PointFocus`, Swift 6 tools version, macOS 14 platform → verify: `swift build` succeeds.
- [ ] Create `Sources/PointFocus/Models/FocusPoint.swift` with `struct FocusPoint: Codable, Equatable { var x: Double; var y: Double }` clamped to `[0,1]` on init → verify: unit test `FocusPoint(x: 1.2, y: -0.1)` yields `(1.0, 0.0)`.
- [ ] Create `Sources/PointFocus/Models/Settings.swift` with `struct Settings: Codable` holding `enabled`, `launchAtLogin`, `globalPoint`, `overrides: [String: FocusPoint]` and static `default` → verify: round-trip JSON encode/decode equality.
- [ ] Create `Sources/PointFocus/Services/SettingsStore.swift` — `@Observable` class wrapping `UserDefaults.standard` under key `com.avb.pointfocus.v1`, with debounced persist (≥200 ms) → verify: mutate store, wait 250 ms, relaunch instance, assert value survives.
- [ ] Create `Sources/PointFocus/Services/PermissionsService.swift` exposing `@Observable` `(accessibility, inputMonitoring): (PermissionState, PermissionState)` polled every 1 s → verify: toggle permission, observe state change within 2 s.
- [ ] Create `Sources/PointFocus/Services/EventTapService.swift` installing `CGEventTap`; exposes a `Combine`/async stream of `.cmdTabReleased` events → verify: unit hook counts events during scripted Cmd+Tab.
- [ ] Create `Sources/PointFocus/Services/FocusedWindowProbe.swift` returning `(bundleID: String, frame: CGRect)?` via AX API → verify: call while Terminal frontmost, assert non-nil with plausible frame.
- [ ] Create `Sources/PointFocus/Services/CursorWarpService.swift` with `warp(to absolute: CGPoint)` that clamps to display bounds, calls `CGWarpMouseCursorPosition` + `CGAssociateMouseAndMouseCursorPosition(1)` → verify: call with (500,500), assert cursor at (500,500).
- [ ] Create `Sources/PointFocus/Services/FocusRouter.swift` — the orchestrator that consumes `EventTapService` events, queries `FocusedWindowProbe`, resolves override vs default from `SettingsStore`, calls `CursorWarpService` → verify: integration test simulating Cmd+Tab moves cursor to expected point.
- [ ] Create `Sources/PointFocus/Services/LaunchAtLoginService.swift` wrapping `SMAppService.mainApp` → verify: toggle on, quit app, log in, observe autostart.

##### Phase 2 — UI

- [ ] Create `Sources/PointFocus/UI/MenuBarController.swift` — `NSStatusItem` with two SF Symbols (`scope` enabled, `scope.slash` disabled, `exclamationmark.triangle` warning) and a right-click `NSMenu` → verify: launch app, click icon, state toggles.
- [ ] Create `Sources/PointFocus/UI/SettingsView.swift` SwiftUI view with sections: Enabled, Launch at Login, Global Point, Per-App Overrides list, Permissions status → verify: open via menu, all controls bound to store.
- [ ] Create `Sources/PointFocus/UI/SettingsWindowController.swift` — single-instance `NSWindowController` hosting `SettingsView` → verify: opening multiple times focuses existing window.
- [ ] Create `Sources/PointFocus/UI/AppOverrideRow.swift` — row view showing icon, name, bundle id, `(x, y)`, Re-pick button, Remove button → verify: displays correctly for com.apple.Terminal.
- [ ] Create `Sources/PointFocus/UI/OnboardingView.swift` with permission checklist and `Open System Settings` buttons deep-linking via `x-apple.systempreferences:` URLs → verify: click button opens Privacy pane.
- [ ] Create `Sources/PointFocus/UI/OnboardingWindowController.swift` shown when either permission missing on launch → verify: revoke AX permission, relaunch, window appears.

##### Phase 3 — Picker Integration

- [ ] Create `Sources/PointFocus/UI/Picker/PickerCoordinator.swift` — `@MainActor` type that: activates target app, resolves frame via `FocusedWindowProbe`, creates `PickerOverlayWindow`, returns `async` result (`FocusPoint?`) → verify: call from settings, overlay appears on target app.
- [ ] Create `Sources/PointFocus/UI/Picker/PickerOverlayWindow.swift` — borderless transparent `NSWindow` at level `.statusBar` sized to window frame, accepting mouse events → verify: overlay covers expected rect exactly.
- [ ] Create `Sources/PointFocus/UI/Picker/PickerOverlayView.swift` — `NSView` drawing accent-tinted fill, border, edge-to-edge crosshair at cursor, HUD label with live relative `(x, y)`; handles `mouseMoved`, `mouseDown`, Escape via `keyDown` → verify: move cursor, crosshair follows; click computes correct relative point.
- [ ] Wire `AppOverrideRow`'s Re-pick and global "Pick on screen…" buttons to `PickerCoordinator` → verify: click Re-pick, picker appears for that app.
- [ ] Handle app-quit / window-close during picker via AX observer notification → dismiss overlay with inline error → verify: launch picker, quit target app, observe dismissal.

##### Phase 4 — Build & Polish

- [ ] Create `Resources/Info.plist` with `LSUIElement=YES`, bundle id, version, usage descriptions → verify: embedded in final `.app`.
- [ ] Create `Resources/PointFocus.entitlements` (empty sandbox off; app-groups not needed) → verify: ad-hoc sign succeeds.
- [ ] Create `build.sh` that runs `swift build -c release --arch arm64 --arch x86_64`, assembles `PointFocus.app/Contents/{MacOS,Resources,Info.plist}`, ad-hoc signs, and copies to `~/Applications/` → verify: `./build.sh` produces a double-clickable app in `~/Applications/`.
- [ ] Create `README.md` covering install, permissions, and uninstall → verify: follow README from scratch to get a working install.
- [ ] Add debounce on global-point numeric field edits (≥ 200 ms) → verify: rapid typing writes once.
- [ ] Add multi-display clamping in `CursorWarpService` (FR-023) → verify: set override to (10, 10) on a single-monitor window that's been dragged off-screen; warp lands on visible display.
- [ ] Add menu-bar warning variant + pause-warping behaviour when permission revoked mid-session (FR-063) → verify: revoke AX during run, icon changes, Cmd+Tab no longer warps.

---

#### 3.8 Out of Scope (V1)

- Cmd+` (backtick) same-app window cycling
- Mission Control / Spaces switches
- Click-to-focus cursor warping (e.g. warping on any app activation, not just Cmd+Tab)
- Per-window (vs per-app) focus points
- Multiple named focus points per app (e.g. "coding mode" vs "review mode")
- Importing BetterTouchTool or Hammerspoon configs
- Cursor animation / easing (warp is instantaneous)
- iCloud sync of settings
- Keyboard shortcuts for opening settings or toggling (only menu-bar click in V1)
- Localization (English-only V1)
- Notarization / developer-ID signing (ad-hoc only)

---

#### 3.9 Open Questions

- [x] Menu bar app vs dock app? → **menu bar (LSUIElement)**
- [x] Crosshair style? → **edge-to-edge horizontal + vertical lines**
- [x] Triggers beyond Cmd+Tab? → **Cmd+Tab only in V1**
- [x] Persistence backend? → **UserDefaults**
- [x] Minimum macOS? → **macOS 14 (Sonoma)**
- [x] Code signing? → **ad-hoc only**
