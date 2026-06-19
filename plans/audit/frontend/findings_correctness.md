# Correctness Findings

## Summary
The picker coordinate math (AX top-left ↔ Cocoa bottom-left flips, normalization, HUD readout) is internally consistent and correct end-to-end. The material correctness issues are in the onboarding window, which is sized smaller than its SwiftUI content and uses a non-auto-sizing host, and in the launch-at-login toggle binding, which reads a non-observable, externally-mutable source so the control becomes stale.

## Findings

### F-correctness-001: Onboarding window content rect is smaller than the SwiftUI content, with no auto-sizing host
- **Severity:** medium
- **Confidence:** 80
- **Files:** Sources/PointFocus/UI/OnboardingWindowController.swift:13-22; Sources/PointFocus/UI/OnboardingView.swift:32-34
- **What:** The window is created with a fixed `contentRect` of 460×360 and its content view is a plain `NSHostingView(rootView: OnboardingView(...))`. `OnboardingView` declares `.frame(width: 460)` then `.padding(24)`, giving an intrinsic content size of 460 + 48 = **508pt wide** and an intrinsic height that exceeds 360pt. A bare `NSHostingView` does not resize the host window to fit its content, so content is laid out into 460×360 → ~48pt horizontal clipping and likely vertical clipping/compression.
- **Why it matters:** The onboarding/permissions window (first-run + "Fix permissions…" entry) renders with clipped/truncated content — the caption and/or the right edge of permission rows can be cut off, undermining the only screen that explains how to grant permissions.
- **Suggested fix:** Give `OnboardingView` a size matching the window, or size the window from content: use `NSHostingController` + `window.setContentSize(hostingController.view.fittingSize)`, removing the hard-coded 460×360. One source of truth for dimensions.
- **Verification:** Show the window with permissions ungranted; observe clipped right edge / bottom caption. Or compare `NSHostingView(rootView: OnboardingView(perms:)).fittingSize` against `NSSize(460, 360)`.

### F-correctness-002: Launch-at-login toggle binds to a non-observable, externally-mutable source and becomes stale
- **Severity:** medium
- **Confidence:** 72
- **Files:** Sources/PointFocus/UI/SettingsView.swift:52-60, 164
- **What:** `launchBinding.get` returns `launch.isEnabled`, a computed property reading `SMAppService.mainApp.status`. The service is not `@Observable`. SwiftUI's body tracks only `@Observable` reads, so nothing registers a dependency on `SMAppService` status. The Toggle renders the last-evaluated value and won't re-render when login-item status changes externally (System Settings) or on success-pending-approval. Additionally `set` uses `try?` and reconciles from `launch.isEnabled`; on the approval-required failure the throw is swallowed and the toggle silently snaps back.
- **Why it matters:** The control can display a value that disagrees with the actual login-item state (stale after external change), and a failed/approval-pending registration produces a toggle that flips back with no explanation.
- **Suggested fix:** Make the login-item status observable (an `@Observable` mirror refreshed when the popover appears) so the binding's get tracks it; surface `launch.set` failures (catch typed `LaunchAtLoginError`) instead of `try?`.
- **Verification:** Change "Launch at login" in System Settings → Login Items, reopen the popover — the toggle does not update. Or trigger `set` while approval is required and observe a silent revert.

### F-correctness-003: Hosted SettingsView is rebuilt once with callbacks but never re-evaluated on parent state — relies solely on @Observable propagation
- **Severity:** low
- **Confidence:** 55
- **Files:** Sources/PointFocus/UI/MenuBarController.swift:44-54
- **What:** `hostingController.rootView` is assigned exactly once and never updated. Live updates depend entirely on SwiftUI's `@Observable` tracking of `store`/`perms` reads inside `SettingsView.body` (which works). The exception is any value from a non-`@Observable` collaborator (F-correctness-002, `launch.isEnabled`), which cannot be picked up because the root view is captured once and the source isn't observable.
- **Why it matters:** Reinforces F-correctness-002: there is no fallback re-render path, so the stale launch toggle never self-corrects from the AppKit side either.
- **Suggested fix:** No change for observable inputs; addressing F-correctness-002 resolves the gap.
- **Verification:** Confirm `hostingController.rootView` is assigned only once and nowhere in `togglePopover`.

## Out of scope
- `SettingsView` swallowing `LaunchAtLoginError` via `try?` — robustness/error-handling lens (reliability).
- `PermissionsService` 1Hz polling and `OnboardingWindowController` 1s `Task.sleep` watch loop — performance/lifecycle lens.
- `displayNameForBundleID`/`iconForBundleID` synchronous `NSWorkspace` disk lookups inside `body` on every render — performance lens.
- Picker overlay only covering `NSScreen.main`/probe frame; Esc-to-cancel only exit — UX lens, intentional.
