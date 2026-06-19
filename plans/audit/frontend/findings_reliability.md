# Reliability Findings

## Summary
The picker flow contains a genuine, repeatable retain cycle that leaks an `NSWindow` (and its tracking-area-bearing view) on every pick, because the overlay's callbacks strongly capture a `Box` that strongly captures the overlay, and teardown never breaks the link. Beyond that, a `LaunchAtLoginService.set` failure is silently swallowed leaving the UI inconsistent with reality, the onboarding window can present stale permission state because its hosting view is built once and reused, and the picker has no re-entrancy guard so overlapping invocations can stack orphaned overlays.

## Findings

### F-reliability-001: Picker overlay window/view leaks via retain cycle on every pick
- **Severity:** high
- **Confidence:** 88
- **Files:** Sources/PointFocus/UI/Picker/PickerCoordinator.swift:55-100
- **What:** In `runOverlay`, the `Box` holds a strong `let overlay`, and the overlay's callbacks capture the box strongly: `overlay.onPick = { [box] p in box.resume(p) }` and `overlay.onCancel = { [box] in box.resume(nil) }`. This forms a cycle overlay → onPick/onCancel closure → box → overlay. `Box.resume()` calls `overlay.orderOut(nil)` and resumes the continuation, but never nils the overlay's `onPick`/`onCancel` nor releases its `overlay` reference. Once the continuation returns and the local `overlay`/`box` go out of scope, the cycle keeps both alive permanently.
- **Why it matters:** Every pick leaks one borderless `NSWindow` plus its `PickerOverlayView` (which installs an `NSTrackingArea`). For a long-running menu-bar utility this is unbounded growth of hidden windows and tracking areas.
- **Suggested fix:** In `Box.resume()`, after `orderOut`, break the cycle: set `overlay.onPick = nil; overlay.onCancel = nil`.
- **Verification:** Add `deinit { print("overlay deinit") }` to `PickerOverlayWindow` and `Box`, perform several picks, confirm deinits fire. Or Instruments (Leaks) filtering on `PickerOverlayWindow`.

### F-reliability-002: LaunchAtLoginService.set failure silently swallowed, leaving toggle out of sync
- **Severity:** medium
- **Confidence:** 90
- **Files:** Sources/PointFocus/UI/SettingsView.swift:52-60
- **What:** `launchBinding`'s setter does `try? launch.set(newValue)` then `store.update { $0.launchAtLogin = launch.isEnabled }`. If `set` throws `LaunchAtLoginError`, the error is discarded. The user receives no feedback: they flip the toggle, registration fails (a documented `SMAppService` possibility, e.g. requires user approval), and the switch silently snaps back with no explanation.
- **Why it matters:** A core advertised feature (Launch at login) can fail with zero user-visible signal.
- **Suggested fix:** Capture the thrown `LaunchAtLoginError` with `do/catch` and surface it (NSAlert or inline error) so the user knows the toggle did not take effect and why.
- **Verification:** grep SettingsView for `try? launch.set`; force a failure and observe no UI indication.

### F-reliability-003: Onboarding window reuses a hosting view built with the initial perms object; teardown is order-out only
- **Severity:** medium
- **Confidence:** 60
- **Files:** Sources/PointFocus/UI/OnboardingWindowController.swift:11-30, 50-61
- **What:** `show(perms:)` constructs `NSHostingView(rootView: OnboardingView(perms: perms))` only inside the `if window == nil` branch. On every subsequent `show()` the stale hosting view is reused and the freshly passed `perms` is ignored for the view (only re-used for `startWatching`). Correct only because the app always passes the same `AppDelegate.perms` instance — a latent hazard if a different `perms` is ever passed. The window is dismissed via `orderOut(nil)` with `isReleasedWhenClosed = false`, so the SwiftUI hierarchy + Observation trackers persist for the app's lifetime.
- **Why it matters:** The "reuse the first perms" coupling is an invisible invariant; a future change passing a per-call `perms` would silently show stale permission state.
- **Suggested fix:** Rebuild `window?.contentView = NSHostingView(rootView: OnboardingView(perms: perms))` on each `show()`, or assert/document the single-instance assumption.
- **Verification:** Confirm the `NSHostingView` is only assigned in the `window == nil` branch; call `show` with two distinct `PermissionsService` instances and observe stale rendering.

### F-reliability-004: No re-entrancy guard on the picker; overlapping invocations stack orphaned overlays
- **Severity:** medium
- **Confidence:** 55
- **Files:** Sources/PointFocus/UI/Picker/PickerCoordinator.swift:11-53, 79-100; Sources/PointFocus/UI/SettingsView.swift call sites
- **What:** `pickGlobal()` and `pick(bundleID:)` each unconditionally create a new `PickerOverlayWindow` with no guard preventing a second overlay while one is live. `pick(bundleID:)` can spend up to 5s polling `FocusedWindowProbe` before showing its overlay, so a second pick (or a Cmd+Tab-triggered path) during that window produces two stacked status-bar-level overlays.
- **Why it matters:** Stacked transparent overlays at `.statusBar` level intercept all clicks/keys; the user can end up with a full-screen overlay they cannot dismiss except via Escape on the topmost one, with the lower one still active — a confusing soft-lock.
- **Suggested fix:** Add an `isPicking` flag (or stored reference to the active overlay) on `PickerCoordinator`; early-return or replace the existing overlay when a pick is already in progress.
- **Verification:** Inspect both public methods for an in-progress guard (none today); manually start two overlapping picks.

## Out of scope
- `PermissionsService.startPolling` Timer invalidated only in `applicationWillTerminate` — collaborator, lifecycle-correct for a singleton.
- `MenuBarController.startObservation` re-registration loop weak-captures `self` correctly; no leak there.
- `AppDelegate.onShowOnboarding` uses `[unowned self]` — out of scope file.
