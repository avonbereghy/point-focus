# Ux-polish Findings

## Summary
The PointFocus UI is clean but leans heavily on silent no-ops: failures in launch-at-login and the on-screen picker produce zero user-facing feedback, and the click-to-pick overlay ships with no instructions or cancel hint. Permission-denied states are reasonably surfaced in the menu but several action controls remain fully enabled (and silently ineffective) while permissions are missing.

## Findings

### F-ux-polish-001: Launch-at-login failure is swallowed; toggle silently snaps back with no explanation
- **Severity:** high
- **Confidence:** 92
- **Files:** Sources/PointFocus/UI/SettingsView.swift:52-60
- **What:** `launchBinding` setter calls `try? launch.set(newValue)` then re-reads `launch.isEnabled`. `LaunchAtLoginService.set(_:)` throws a typed `LaunchAtLoginError` (with the raw `SMAppService` error) expressly so a caller can detect the common case where the user must approve the item in System Settings → Login Items. `try?` discards it; on failure `isEnabled` stays `false` and the Toggle flips back to off with no alert, hint, or link.
- **Why it matters:** A user toggles "Launch at login" on, the switch flips back off, and there is no indication why or what to do — and the most common failure (pending approval) is exactly what the service was designed to communicate.
- **Suggested fix:** Catch the error and present feedback — minimally an `NSAlert` (or inline text) "Approve PointFocus in System Settings → General → Login Items," with a button opening `x-apple.systempreferences:com.apple.LoginItems-Settings.extension`. Do not use `try?`.
- **Verification:** With approval pending, click the toggle on; confirm it reverts with no explanation today; after the fix confirm an actionable alert/hint appears.

### F-ux-polish-002: Click-to-pick overlay has no on-screen instructions or cancel (Esc) hint
- **Severity:** high
- **Confidence:** 90
- **Files:** Sources/PointFocus/UI/Picker/PickerOverlayView.swift:29-66, 79-85
- **What:** The full-screen overlay shows a tinted fill, crosshair, and live coordinate readout — but no text telling the user what to do. No "Click to set the focus point" prompt and no "Press Esc to cancel" hint, even though Esc cancellation is implemented (`keyCode == 53`). The launching popover has already dismissed, so the overlay appears abruptly with no framing context.
- **Why it matters:** A novice faces a tinted full-screen overlay with only floating numbers and no guidance; they may not realize a click commits, and can't discover Esc cancels.
- **Suggested fix:** Draw a centered/corner instruction banner, e.g. "Click anywhere to set the focus point · Esc to cancel", reusing the existing attributed-string/background-pill pattern.
- **Verification:** Trigger the picker; confirm only coordinates/crosshair today; after the fix confirm an instruction + Esc hint is visible.

### F-ux-polish-003: Picker failures return false and are completely discarded — no feedback when an app won't launch, the probe times out, or the app quits
- **Severity:** high
- **Confidence:** 88
- **Files:** Sources/PointFocus/UI/SettingsView.swift:115-118, 144-148, 196-197; Sources/PointFocus/UI/Picker/PickerCoordinator.swift:27-53
- **What:** Every caller invokes the picker as `Task { _ = await picker.pick(...) }`, discarding the `Bool`. `pick(bundleID:)` returns `false` on real failure paths: the app can't be launched, the probe never matches within 5s, the app terminates mid-pick, or the user presses Esc. In all of these the popover has already dismissed, so the user is left at their desktop with nothing added and no message — indistinguishable from a successful cancel.
- **Why it matters:** A user picks "Add app…", selects a slow/uncooperative app, waits up to 5s, then nothing — no overlay, no error, no new row. The feature appears broken with no diagnostic.
- **Suggested fix:** Distinguish user-cancel from genuine failure (richer return than `Bool`), and on genuine failure show a brief `NSAlert`/notification ("Couldn't capture <app>'s window — make sure it's open and try again").
- **Verification:** Add an app that is quit/slow to launch (or force the probe to time out); confirm no feedback today; after the fix confirm a failure message.

### F-ux-polish-004: Action controls are not gated when required permissions are missing — they silently no-op
- **Severity:** medium
- **Confidence:** 78
- **Files:** Sources/PointFocus/UI/SettingsView.swift:85-122, 124-160
- **What:** When Accessibility/Input Monitoring are not granted, the menu shows red chips and a "Fix permissions…" button (good). But the functional controls remain fully enabled: the "Enable cursor warp on Cmd+Tab" toggle, "Pick on screen…", "Add app…", and per-app "Re-pick". With Accessibility denied, `FocusedWindowProbe.current()` can't read frames so `pick` times out and the core feature does nothing — yet the UI presents these as working.
- **Why it matters:** A user without permissions can flip "Enable" on, add apps, and try to pick points, all of which silently fail — the controls imply the feature works when it cannot.
- **Suggested fix:** When `perms.accessibility != .granted || perms.inputMonitoring != .granted`, disable the pick/add/enable controls (or show an inline gated note).
- **Verification:** Revoke Accessibility (tccutil), open the popover; confirm controls still active today; after the fix confirm they are disabled/gated.

### F-ux-polish-005: Onboarding window auto-dismisses with no completion confirmation
- **Severity:** medium
- **Confidence:** 80
- **Files:** Sources/PointFocus/UI/OnboardingWindowController.swift:50-61, Sources/PointFocus/UI/OnboardingView.swift:28-30
- **What:** The onboarding window watches permissions on a 1s poll and, the moment both are granted, calls `window?.orderOut(nil)` — it just vanishes. The only forewarning is a caption "This window will close automatically once both are granted." No success state (chips green + "You're all set" message) before it disappears.
- **Why it matters:** Completing setup is the key success moment and the app gives no positive confirmation. An abrupt disappearance reads as a glitch rather than success; users get no "what happens next" cue (the app lives only in the menu bar).
- **Suggested fix:** On both-granted, briefly show a success state (chips green + "All set — find PointFocus in your menu bar") for ~1s before ordering the window out, or replace auto-dismiss with a "Done" confirmation.
- **Verification:** Grant both permissions with the window open; confirm it vanishes with no message today; after the fix confirm a confirmation before/instead of the close.

### F-ux-polish-006: Onboarding window content height mismatch leaves dead/clipped space
- **Severity:** medium
- **Confidence:** 65
- **Files:** Sources/PointFocus/UI/OnboardingWindowController.swift:13-22, Sources/PointFocus/UI/OnboardingView.swift:33
- **What:** The window is created with a fixed `contentRect` of 460×360 hosting an `NSHostingView`, while `OnboardingView` fixes only its width and lets height be intrinsic. The hosting view is set as `contentView` with no Auto Layout pinning to the SwiftUI fitting size, so the rendered content height and the hard-coded 360 are unlikely to match — empty space below or clipped content. The window is non-resizable, so the user cannot correct it. (Merges with correctness F-correctness-001.)
- **Why it matters:** A first-run window with obvious empty padding or slightly clipped controls reads as unpolished at the first impression.
- **Suggested fix:** Size the window to the hosting view's fitting size (or pin the hosting view's edges) rather than hard-coding 360.
- **Verification:** Open the onboarding window; visually compare content extent vs window bounds.

### F-ux-polish-007: Custom permission/override rows expose no hover/focus or accessibility affordances; chip color is the sole status signal
- **Severity:** medium
- **Confidence:** 62
- **Files:** Sources/PointFocus/UI/SettingsView.swift:174-185, Sources/PointFocus/UI/AppOverrideRow.swift:23-28, Sources/PointFocus/UI/OnboardingView.swift:72-89
- **What:** Permission status is conveyed by a colored dot/capsule plus text. The settings chip pairs the dot with text (fine), but the onboarding capsules rely on hue with no shape/icon differentiation, and the destructive trash button in `AppOverrideRow` is an unlabeled `Image(systemName: "trash")` with no `accessibilityLabel` and no confirmation. (Overlaps a11y F-a11y-003 / F-a11y-004.)
- **Why it matters:** Color-only status is an affordance gap for color-blind users; an unlabeled icon-only destructive button with no confirmation is both an accessibility gap and a minor foot-gun.
- **Suggested fix:** Add an SF Symbol alongside the colored chips so status isn't hue-only; give the trash button `accessibilityLabel("Remove override")` (optionally a lightweight confirm).
- **Verification:** Inspect chips under a color-blindness simulation; run VoiceOver over the override delete button.

## Out of scope
- `pickGlobal()` captures only `NSScreen.main`'s frame; multi-monitor global focus point derived from one display (correctness/multi-monitor lens).
- The `Box`/continuation lifecycle and the terminate observer in `runOverlay` — concurrency/reliability.
- `MenuBarController` rebuilds the SwiftUI root view twice during init — code-structure lens.
