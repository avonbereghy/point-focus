# A11y Findings

## Summary
The PointFocus UI layer has zero SwiftUI accessibility modifiers and exposes several icon-only and color-only controls that VoiceOver cannot meaningfully describe. The most severe gap is the full-screen click-to-pick overlay, which is a non-focusable, mouse-only AppKit surface with no VoiceOver representation, no keyboard targeting path, and an Escape affordance that is never announced. Permission state is also signaled by colored dots/capsules without a non-color cue, and the menu-bar status button carries no stable accessibility label.

## Findings

### F-a11y-001: Picker overlay is mouse-only and completely inaccessible to VoiceOver and keyboard users
- **Severity:** high
- **Confidence:** 90
- **Files:** Sources/PointFocus/UI/Picker/PickerOverlayView.swift:1-86, Sources/PointFocus/UI/Picker/PickerOverlayWindow.swift:1-32, Sources/PointFocus/UI/Picker/PickerCoordinator.swift:79-100
- **What:** The "Pick on screen…" / "Re-pick" flow opens a borderless full-screen overlay. The only way to choose a point is `mouseMoved`/`mouseDown`. There is no accessibility element, no role/label/value, and no non-pointer path to set a coordinate. VoiceOver sees an empty borderless window with one unlabeled `NSView`.
- **Why it matters:** A VoiceOver or keyboard-only user who activates the picker enters a modal-feeling full-screen window with no announced content, no focusable target, and no discoverable way to complete or cancel the task.
- **Suggested fix:** Make the overlay self-describing and provide a non-pointer exit/commit: `setAccessibilityRole(.group)`, `setAccessibilityLabel("Focus point picker")`, `setAccessibilityHelp("Move the mouse to position the crosshair, then click to set the focus point. Press Escape to cancel.")`; post a high-priority `.announcementRequested` on open. Longer term: arrow-key crosshair nudge + Return to commit for full keyboard operability.
- **Verification:** With VoiceOver on, trigger the picker; confirm an announcement naming the surface + keys; in Accessibility Inspector confirm the content view exposes a non-empty role/label/help.

### F-a11y-002: Picker overlay opening/closing performs no focus management or announcement
- **Severity:** medium
- **Confidence:** 78
- **Files:** Sources/PointFocus/UI/Picker/PickerCoordinator.swift:79-100, Sources/PointFocus/UI/Picker/PickerOverlayView.swift:24-27
- **What:** On open the only focus handling is `window?.makeFirstResponder(self)` on the bare view; no NSAccessibility focus is moved to a described element and no announcement fires. On close (`orderOut`) focus is not returned to the popover/control that launched the picker (the popover was already dismissed), leaving VoiceOver focus orphaned.
- **Why it matters:** A VoiceOver user gets no signal that a new full-screen context appeared, and after the pick their cursor is left in an undefined place rather than back on the launching control.
- **Suggested fix:** On open set the overlay's content view as the a11y-focused element + post `.announcementRequested`; on resume/close re-focus the originating control.
- **Verification:** With VoiceOver, run a full pick cycle and confirm focus lands on a described element on open and returns on close.

### F-a11y-003: Permission chips signal granted/denied with color; the colored dot/capsule is the sole symbol cue
- **Severity:** medium
- **Confidence:** 72
- **Files:** Sources/PointFocus/UI/SettingsView.swift:174-185, Sources/PointFocus/UI/OnboardingView.swift:72-89
- **What:** In SettingsView the chip is a green/red `Circle()` plus `Text("\(label): \(granted ? "Granted" : "Not granted")")`. The text is good but the `Circle` carries no accessibility treatment and the only differentiating glyph is color (identical filled-dot shape for both states). In OnboardingView the `chip(state:)` uses green vs red capsules — again color-coded with no distinct symbol. No `.accessibilityElement(children:)` groupings, so VoiceOver may read the decorative circle and text as separate fragments.
- **Why it matters:** Color-blind / low-vision users get no shape/symbol distinction between granted and denied; VoiceOver hears stray noise from the bare `Circle`.
- **Suggested fix:** Hide the dot (`.accessibilityHidden(true)`) or replace with distinct SF Symbols (`checkmark.circle.fill` vs `xmark.octagon.fill`) so state differs by shape; wrap each chip in `.accessibilityElement(children: .combine)` with `.accessibilityLabel("\(label), \(granted ? "granted" : "not granted")")`.
- **Verification:** Toggle a permission; VoiceOver reads each chip as one element naming permission + state; verify granted/denied differ by shape under a grayscale filter.

### F-a11y-004: Icon-only trash (delete) button on per-app override rows has no accessibility label
- **Severity:** medium
- **Confidence:** 90
- **Files:** Sources/PointFocus/UI/AppOverrideRow.swift:26-28
- **What:** The destructive remove button is `Image(systemName: "trash")` with no text label or `.accessibilityLabel`. SwiftUI may fall back to the symbol's default description ("trash") but that omits which app it removes.
- **Why it matters:** A VoiceOver user hears at best "trash, button" with no indication of which app's override is deleted — a destructive action with no context, easy to trigger on the wrong row.
- **Suggested fix:** Add `.accessibilityLabel("Remove override for \(displayNameForBundleID(bundleID))")` (and consider an `.accessibilityHint`).
- **Verification:** With VoiceOver, navigate to a row's delete button; confirm app-specific label; grep file for `accessibilityLabel`.

### F-a11y-005: "Re-pick" button and override row lack app-context labeling; coordinate text and icon are not grouped
- **Severity:** medium
- **Confidence:** 60
- **Files:** Sources/PointFocus/UI/AppOverrideRow.swift:10-30
- **What:** The row stacks an app icon (decorative, no label), name + bundle ID, a monospaced coordinate `Text`, a generic "Re-pick" button, and the unlabeled trash button. The "Re-pick" text is identical for every row, so VoiceOver exposes multiple buttons named "Re-pick" with no way to tell which app each belongs to. The row is not wrapped as a single a11y element.
- **Why it matters:** With several overrides, a VoiceOver user hears a wall of identical "Re-pick, button" entries and disjoint coordinate readings.
- **Suggested fix:** Give the re-pick button `.accessibilityLabel("Re-pick focus point for \(displayName)")` and/or wrap the row in `.accessibilityElement(children: .combine)` with a composed label; mark the app icon `.accessibilityHidden(true)`.
- **Verification:** With multiple overrides + VoiceOver, confirm each re-pick button announces its app.

### F-a11y-006: Menu-bar status item button exposes no stable accessibility label and uses the SF Symbol name as its description
- **Severity:** medium
- **Confidence:** 68
- **Files:** Sources/PointFocus/UI/MenuBarController.swift:64-107
- **What:** The status item image is `NSImage(systemSymbolName: name, accessibilityDescription: name)` — VoiceOver announces "scope" or "exclamationmark.triangle" rather than "PointFocus" or a state. The button gets no `setAccessibilityLabel`/`setAccessibilityTitle`. The symbol-fail fallback `title` "PF"/"PF!" is also not descriptive. `button.appearsDisabled` is toggled with `enabled` but that disabled state is purely visual, not surfaced as a value.
- **Why it matters:** A VoiceOver user tabbing the menu bar hears a meaningless symbol name instead of the app name and its state (enabled / disabled / permissions missing).
- **Suggested fix:** `button.setAccessibilityLabel("PointFocus")` and reflect state via `setAccessibilityValue(...)` or a richer label ("PointFocus — permissions required") updated inside `refreshIcon()`; give the symbol a human `accessibilityDescription`.
- **Verification:** With VoiceOver on the menu bar, confirm the item announces "PointFocus" + state; toggle enable/permissions to confirm the value updates.

### F-a11y-007: Onboarding/Settings dynamic permission changes are not announced; grant buttons rely on a relabel only
- **Severity:** medium
- **Confidence:** 55
- **Files:** Sources/PointFocus/UI/OnboardingView.swift:36-50, Sources/PointFocus/UI/OnboardingWindowController.swift:50-61, Sources/PointFocus/UI/SettingsView.swift:85-98
- **What:** When a permission flips to granted, the UI updates silently: chip text/color changes, the button relabels "Grant…" → "Granted" and disables, and the onboarding window may auto-close after a 1s poll. No `.announcementRequested` / VoiceOver notification is posted for any change, and the auto-`orderOut` provides no spoken confirmation.
- **Why it matters:** A VoiceOver user who grants a permission and returns gets no audible confirmation that state changed or that the setup window closed itself.
- **Suggested fix:** Post an accessibility announcement when a permission transitions to granted ("Accessibility granted") and when both are granted / the window auto-closes ("Setup complete"). Drive from the existing `perms` observation / `startWatching` loop.
- **Verification:** With VoiceOver, grant a permission; confirm a spoken status update and an announced window auto-close.

## Out of scope
- The 1-second polling loop in `OnboardingWindowController.startWatching` — responsiveness/architecture, not a11y.
- Picker coordinate math / multi-display origin / 5s probe deadline — correctness/UX.
- `NSOpenPanel` in `addApp()` — system-provided panel.
- Overlay crosshair/label contrast — design/contrast lens.
