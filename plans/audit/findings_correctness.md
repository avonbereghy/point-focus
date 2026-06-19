# Correctness Findings

## Summary
The core coordinate math (AX top-left frame → relative point → Quartz-top-left warp → global Y-flip via `primaryMaxY - p.y`) is sound and consistent end-to-end, including for non-primary displays. The notable correctness issues are in event/router logic: the Cmd+Tab state machine misfires when an app switch is cancelled (Escape), and `FocusRouter`'s bundle-change settle loop is defeated when the initial probe returns nil.

## Findings

### F-correctness-001: Cancelled Cmd+Tab (Escape) still fires a warp
- **Severity:** medium
- **Confidence:** 72
- **Files:** Sources/PointFocus/Services/EventTapService.swift:87-100
- **What:** `tabPending` is set true on any Tab keyDown while Cmd is held, and is only cleared when it fires on Cmd release. macOS lets the user cancel an in-progress switch by pressing Escape (keycode 53) while still holding Cmd; no activation occurs. Escape is a keyDown with keycode != 48, so `handleKeyDown` ignores it and leaves `tabPending == true`. On the subsequent Cmd release, `handleFlagsChanged` yields `.cmdTabReleased`, warping the cursor though the focused window never changed.
- **Why it matters:** The cursor jumps on a gesture the user explicitly cancelled — surprising, unwanted cursor movement.
- **Suggested fix:** Treat Escape as cancel in `handleKeyDown`: `if keycode == 53 { tabPending = false }`.
- **Verification:** Manual — hold Cmd, press Tab, press Escape, release Cmd → observe no warp after fix. `grep -n "keycode ==" Sources/PointFocus/Services/EventTapService.swift`.

### F-correctness-002: Bundle-change settle loop is defeated when the initial probe returns nil
- **Severity:** medium
- **Confidence:** 80
- **Files:** Sources/PointFocus/Services/FocusRouter.swift:60-74
- **What:** `initialBundle` is `FocusedWindowProbe.current()?.bundleID`, which can be `nil` (no AX-resolvable focused window at the instant of Cmd release — common during the activation race). The poll break condition `cur.bundleID != initialBundle` becomes `cur.bundleID != nil` when `initialBundle == nil`, which is true for the first successful probe — so the loop breaks after the first 20ms tick on whatever AX reports, which per the code's own comment is frequently still the PREVIOUS app. The 0.3s settle window is bypassed in exactly the case it exists to handle.
- **Why it matters:** When the initial snapshot is nil, the warp targets the outgoing app's window frame instead of the newly-focused one. Intermittent but real.
- **Suggested fix:** When `initialBundle == nil`, require the loop to wait for the deadline (or two consecutive stable identical reads) rather than breaking on first non-nil; or snapshot the baseline via `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` (more reliable than AX during the race).
- **Verification:** FocusRouter.swift:60,68-69 — `initialBundle` is `String?` and the comparison short-circuits to true for any non-nil `cur.bundleID` when baseline is nil.

### F-correctness-003: Non-focused fallback window can be warped into the wrong window
- **Severity:** medium
- **Confidence:** 55
- **Files:** Sources/PointFocus/Services/FocusedWindowProbe.swift:32-33, 55-75
- **What:** `resolve` picks `focusedWindow ?? mainWindow ?? firstWindow`. When `kAXFocusedWindow` is unavailable (the documented non-Cocoa case), it uses `kAXMainWindow` or `array.first` of `kAXWindows`. That ordering is not guaranteed front-to-back z-order and may include minimized/off-screen/auxiliary windows; the computed frame can belong to a window other than the active one.
- **Why it matters:** For apps without a focused window, the cursor warps relative to a background/minimized window's frame, landing in the wrong place.
- **Suggested fix:** Filter `kAXWindows` to non-minimized (`kAXMinimizedAttribute == false`), or skip the warp when only a non-focused window is resolvable.
- **Verification:** FocusedWindowProbe.swift:69-75 — `firstWindow` returns `array.first` with no visibility filter.

### F-correctness-004: Nearest-display selection uses center distance, not edge distance (DEFERRED — below floor)
- **Severity:** low
- **Confidence:** 65
- **Files:** Sources/PointFocus/Services/CursorWarpService.swift:27-35
- **What:** For off-screen targets, "nearest" screen is chosen by distance to each screen's CENTER. In asymmetric/mixed-size layouts the closest-center screen isn't always the closest-edge one; a point just past a shared edge can clamp onto the farther-by-edge display.
- **Why it matters:** Off-screen targets can land on a counter-intuitive display. Cosmetic in symmetric setups.
- **Suggested fix:** Minimize distance from the point to the nearest point on each screen's rect (`dx=max(minX-x,0,x-maxX)`, similarly `dy`) instead of to the center.
- **Verification:** CursorWarpService.swift:27-30 uses center-based `hypot(midX-x, midY-y)`.

### F-correctness-005: Half-open containment can clamp a genuinely on-screen boundary point (DEFERRED — below floor)
- **Severity:** low
- **Confidence:** 50
- **Files:** Sources/PointFocus/Services/CursorWarpService.swift:23-25, 32-35
- **What:** `CGRect.contains` is half-open. A focus point of `(1.0, …)` or `(…, 0.0)` flush with a display edge yields `bottomLeft` at a screen's `maxX`/`maxY`; the containment test reports "off all screens" and the point is inset by `-1`, nudging 1px inward.
- **Why it matters:** Benign (1px) but a logic inconsistency.
- **Suggested fix:** Use inclusive containment for the on-screen test, or accept the 1px inset as intentional margin.
- **Verification:** CursorWarpService.swift:23 uses half-open `contains`.

## Out of scope
- The `primaryMaxY - p.y` global flip is correct for non-primary displays (anchor-based conversion depending only on primary height); `screens.first(where: { origin == .zero })` correctly identifies the primary. End-to-end coordinate contract (AX top-left → warp top-left) is consistent. No bug.
- EventTapService fires exactly once for ordinary Cmd+Tab, Cmd+Shift+Tab, and multi-Tab cycling; correctly ignores bare Tab, Cmd+arrows, non-Cmd modifiers. Only gap is the Escape-cancel case (F-001).
- A missed Cmd-up flagsChanged could leave state stale, but the next cycle self-corrects and cannot double-fire. Below floor.
- `FocusPoint.init` clamping and `Settings.default` are correct; no dead/unreachable branches.
