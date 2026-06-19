# Frontend Improvement Plan — PointFocus UI layer

Run: frontend-quality-sweep · base commit `c9d1df2` · severity floor **medium**
Stack: Swift 6 + SwiftUI + AppKit (SwiftPM executable). Lenses: reliability, correctness, a11y, ux-polish.

## Lens Coverage
| Lens | Findings | Critical | High | Medium | Low |
|------|----------|----------|------|--------|-----|
| reliability | 4 | 0 | 1 | 3 | 0 |
| correctness | 3 | 0 | 0 | 2 | 1 |
| a11y | 7 | 0 | 1 | 6 | 0 |
| ux-polish | 7 | 0 | 3 | 4 | 0 |
| **Total** | **21** | **0** | **5** | **15** | **1** |

In-scope (medium+): **20**. Below floor (deferred): 1 (F-correctness-003, low).

## Top Risks (severity × confidence)
1. **F-ux-polish-001 / F-reliability-002** (high·0.92) — Launch-at-login failure swallowed by `try?`; toggle silently reverts with no explanation.
2. **F-a11y-001** (high·0.90) — Click-to-pick overlay is mouse-only: no VoiceOver element, no keyboard path, Esc unannounced.
3. **F-ux-polish-002** (high·0.90) — Picker overlay has no on-screen instructions or cancel hint.
4. **F-ux-polish-003** (high·0.88) — Picker failure (`Bool` discarded) gives the user no feedback when an app won't focus.
5. **F-reliability-001** (high·0.88) — Picker overlay window + view leak via a Box↔overlay retain cycle on every pick.

## Deduplication notes
- Launch-at-login: **F-reliability-002 + F-ux-polish-001 + F-correctness-002** merge into one SettingsView fix (catch typed error, surface it, bind toggle to observable store state reconciled from the real service). **F-correctness-003 (low)** becomes moot once the toggle reads observable state.
- Onboarding window size: **F-correctness-001 + F-ux-polish-006** merge (size window to hosting fitting size).
- Permission chips color-only: **F-a11y-003 + F-ux-polish-007** merge (SF Symbol + a11y label) — split by file across Track B (Settings chip / trash) and Track C (Onboarding chips).
- Picker accessibility: **F-a11y-001 + F-a11y-002** merge (describe + announce + focus return + keyboard operability), same files as **F-ux-polish-002** (instructions) → all Track A.

## Track Plan (sequential; file-disjoint, executed by orchestrator)

### Track A — Picker (PickerCoordinator, PickerOverlayView, PickerOverlayWindow)
- **F-reliability-001**: in `Box.resume()`, nil `overlay.onPick`/`overlay.onCancel` after `orderOut` to break the cycle.
- **F-reliability-004**: add an `isPicking` guard on `PickerCoordinator`; early-return if a pick is already live.
- **F-a11y-001 / F-a11y-002**: make `PickerOverlayView` an accessibility element (label + help); post `.announcementRequested` on open; add arrow-key crosshair nudge + Return-to-commit for keyboard operability; initialise crosshair to centre.
- **F-ux-polish-002**: draw an on-screen instruction banner ("Click or press Return to set the focus point · Esc to cancel").
- **Produces (contract for Track B)**: change `pick(bundleID:)`/`pickGlobal()` return from `Bool` to `enum PickerOutcome { case completed, cancelled, failed(String) }`. Existing `_ = await …` call sites still compile (result discarded), so this commit keeps the build green on its own.
- Verification: `swift build`; deinit-trace the overlay across repeated picks; VoiceOver announcement on open.

### Track B — Settings popover (SettingsView, AppOverrideRow)
- **F-reliability-002 / F-ux-polish-001 / F-correctness-002 (+003 moot)**: bind launch toggle `get` to observable `store.settings.launchAtLogin`; `set` does `do/catch launch.set`, reconciles `launchAtLogin = launch.isEnabled`, and on `LaunchAtLoginError` shows an `NSAlert` with a System Settings → Login Items deep link; add `.onAppear` reconcile so external changes show on popover open.
- **F-ux-polish-003**: consume `PickerOutcome`; on `.failed(reason)` show an `NSAlert`; stay silent on `.cancelled`.
- **F-ux-polish-004**: gate Enable toggle / Pick / Add / Re-pick behind `perms.accessibility == .granted && perms.inputMonitoring == .granted` (disable + concise note).
- **F-a11y-003 / F-ux-polish-007 (settings chip)**: replace color-only dot with an SF Symbol (`checkmark.circle.fill` / `exclamationmark.triangle.fill`) + `.accessibilityElement(children: .combine)` label.
- **F-a11y-004**: `.accessibilityLabel("Remove override for \(displayName)")` on the trash button.
- **F-a11y-005**: `.accessibilityLabel("Re-pick focus point for \(displayName)")` on Re-pick; hide the app icon from AT.
- Verification: `swift build`; VoiceOver over chips/row/delete; trigger a launch-at-login failure and a picker failure.

### Track C — Onboarding (OnboardingView, OnboardingWindowController)
- **F-correctness-001 / F-ux-polish-006**: build the hosting view and size the window to its `fittingSize` (one source of truth) instead of the hard-coded 460×360.
- **F-reliability-003**: rebuild the hosting view (`contentView`) on each `show(perms:)` so a fresh `perms` always renders; removes the stale-reuse hazard.
- **F-ux-polish-005**: on both-granted, show a brief success state ("All set — find PointFocus in your menu bar") for ~1s before `orderOut`.
- **F-a11y-007**: post `.announcementRequested` when a permission transitions to granted and when setup completes / the window auto-closes.
- **F-a11y-003 / F-ux-polish-007 (onboarding chips)**: add an SF Symbol to the granted/not-granted capsules so status isn't hue-only; combine a11y label.
- Verification: `swift build`; open onboarding ungranted (no clipping); grant both (success state + announcement before close).

### Track D — Menu bar (MenuBarController)
- **F-a11y-006**: `statusItem.button?.setAccessibilityLabel("PointFocus")` + reflect state via `setAccessibilityValue` ("permissions required" / "disabled" / "active") inside `refreshIcon()`; give the symbol a human `accessibilityDescription`.
- Verification: `swift build`; VoiceOver on the menu bar item; toggle enable/permissions to confirm the value updates.

## File Ownership Matrix
| File | Track A (Picker) | Track B (Settings) | Track C (Onboarding) | Track D (MenuBar) |
|------|:---:|:---:|:---:|:---:|
| UI/Picker/PickerCoordinator.swift | ✏️ | | | |
| UI/Picker/PickerOverlayView.swift | ✏️ | | | |
| UI/Picker/PickerOverlayWindow.swift | ✏️ | | | |
| UI/SettingsView.swift | | ✏️ | | |
| UI/AppOverrideRow.swift | | ✏️ | | |
| UI/OnboardingView.swift | | | ✏️ | |
| UI/OnboardingWindowController.swift | | | ✏️ | |
| UI/MenuBarController.swift | | | | ✏️ |

Every file appears in exactly one track. No Foundation/Integration track needed: the only inter-track contract (`PickerOutcome`) lives in a Track-A file and is consumed by Track B, satisfied by ordering A→B→C→D.

## Inter-Track Contracts
- Track A produces `PickerOutcome` (`completed` / `cancelled` / `failed(reason)`); Track B consumes it in SettingsView call sites to drive failure alerts.

## Acknowledged but Deferred
- **F-correctness-003** (low) — hosted SettingsView root view built once; rendered moot by the Track-B observable-toggle fix, no separate work.
- Out-of-scope items noted by auditors (not fixed): multi-monitor `pickGlobal` single-display capture; `NSWorkspace` disk lookups inside `AppOverrideRow.body`; 1 Hz permission polling cadence. Recorded for a future pass.
