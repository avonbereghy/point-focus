# Reliability Findings

## Summary
PointFocus is generally careful about resource lifecycle (the event tap is torn down symmetrically, the permission timer is invalidated), but there are real gaps: every Cmd+Tab spawns an uncancelled detached probe Task (overlapping warps under rapid switching), the event tap has no recovery path if `tapCreate` returns nil while permission is already granted, there is no watchdog confirming the tap is live, and a settings change made within ~200ms of quit is silently lost.

## Findings

### F-reliability-001: Overlapping probe Tasks on rapid Cmd+Tab — no cancellation or debounce
- **Severity:** medium
- **Confidence:** 85
- **Files:** Sources/PointFocus/Services/FocusRouter.swift:53-82
- **What:** `handle()` runs once per `.cmdTabReleased` and unconditionally spawns a fresh detached `Task` that busy-polls up to 0.3s then warps. The per-event probe Tasks are fire-and-forget — never stored or cancelled (the `task` property only tracks the long-lived stream loop). Several Cmd+Tabs within 300ms run concurrent probes; an earlier (stale) Task can win the race and warp after a later switch settled.
- **Why it matters:** Under fast switching the cursor can jump to a stale/incorrect window or jump twice; also wastes CPU on parallel polling loops.
- **Suggested fix:** Store the probe task in a property; cancel the prior one before starting a new one; check `Task.isCancelled` at the top of each loop iteration so a superseded probe aborts before warping.
- **Verification:** `grep -n "Task {" Sources/PointFocus/Services/FocusRouter.swift` — confirm the per-event Task is assigned to a stored property with a `cancel()` preceding it. Manual: rapid Cmd+Tab across 3+ apps, cursor lands only in final window.

### F-reliability-002: No recovery if `tapCreate` returns nil while Input Monitoring is already granted
- **Severity:** medium
- **Confidence:** 75
- **Files:** Sources/PointFocus/Services/FocusRouter.swift:29-51, Sources/PointFocus/Services/EventTapService.swift:40-58
- **What:** `tryStartTap()` only retries via `observePermissions()`'s `onChange`, which fires only when a permission value CHANGES. If Input Monitoring is already `.granted` at launch but `CGEvent.tapCreate` transiently returns nil, `tapStarted` stays false, the catch logs once, and no observed property changes again → the app silently never installs a tap until restarted.
- **Why it matters:** App appears running (menu icon, permissions green) but Cmd+Tab does nothing, with no retry and no user-visible signal.
- **Suggested fix:** On a failed/absent tap, schedule a bounded retry on a short timer independent of permission-change observation (a few attempts), or have the existing 1s permissions poll re-invoke `tryStartTap()` when `!tapStarted && inputMonitoring == .granted`.
- **Verification:** `grep -n "tapStarted" Sources/PointFocus/Services/FocusRouter.swift` — confirm a retry path not solely dependent on `withObservationTracking` onChange.

### F-reliability-003: No watchdog confirming the event tap stays enabled after re-enable
- **Severity:** medium
- **Confidence:** 70
- **Files:** Sources/PointFocus/Services/EventTapService.swift:81-85, 130-137
- **What:** On `tapDisabledByTimeout`/`tapDisabledByUserInput` the callback calls `reenableTap()` → `CGEvent.tapEnable(enable:true)` with no verification (no `CGEvent.tapIsEnabled` check) and no escalation if re-enable fails. If the main run loop is stalled long enough that re-enable doesn't take, the tap goes permanently dead with no further attempt.
- **Why it matters:** A tap that fails to re-enable leaves Cmd+Tab detection permanently broken for the session, with no recovery and only the one-time disable log.
- **Suggested fix:** After `tapEnable(enable:true)`, verify with `CGEvent.tapIsEnabled(tap:)`; if still disabled, log and retry on a short timer.
- **Verification:** `grep -n "tapIsEnabled\|tapEnable" Sources/PointFocus/Services/EventTapService.swift` — confirm a post-enable verification exists.

### F-reliability-004: Debounced settings write is lost if the app quits within the debounce window
- **Severity:** medium
- **Confidence:** 88
- **Files:** Sources/PointFocus/Services/SettingsStore.swift:32-43, Sources/PointFocus/AppDelegate.swift:37-40
- **What:** `update(_:)` schedules the UserDefaults write via `asyncAfter(.now()+0.2)`. `SettingsStore` exposes no flush API, and `applicationWillTerminate` only calls `events.stop()` and `perms.stopPolling()`. A setting changed then quit within ~200ms loses the pending `DispatchWorkItem`.
- **Why it matters:** Last-moment settings changes silently revert across restarts — the classic debounce-on-quit data-loss bug.
- **Suggested fix:** Add `SettingsStore.flush()` that cancels `pendingWrite` and writes synchronously; call it from `applicationWillTerminate`.
- **Verification:** `grep -n "pendingWrite\|flush\|applicationWillTerminate" Sources/PointFocus/Services/SettingsStore.swift Sources/PointFocus/AppDelegate.swift`. Test: `update` then `flush()` then re-instantiate without sleeping, assert persistence.

### F-reliability-005: FocusRouter has no teardown; its stream-consumer Task is never cancelled (DEFERRED — below floor)
- **Severity:** low
- **Confidence:** 80
- **Files:** Sources/PointFocus/Services/FocusRouter.swift:18-27
- **What:** `start()` launches a long-lived consumer `Task` but the class exposes no `stop()`. At terminate `events.stop()` calls `continuation.finish()`, ending the loop, so no leak at process exit — but the asymmetry is fragile. Tightly related to F-reliability-001's probe-task cancellation.
- **Why it matters:** No leak today (process dies); fragile if the router is ever recreated or the tap stopped without finishing the continuation.
- **Suggested fix:** Cancelling the probe task internally (F-reliability-001) already adds the cancellation surface; a full `stop()` wired into AppDelegate is deferred to avoid cross-track edits to AppDelegate.
- **Verification:** Covered by F-reliability-001 changes.

### F-reliability-006: build.sh — universal-binary not verified with lipo (DEFERRED — below floor)
- **Severity:** low
- **Confidence:** 60
- **Files:** build.sh:72-95
- **What:** `set -euo pipefail` is present and binary existence is checked, but the script signs/installs whatever is at the hardcoded universal-binary path without a `lipo` arch assertion.
- **Why it matters:** A single-arch product could be signed/installed as if universal, failing later on the other arch. Low likelihood given explicit `--arch` flags.
- **Suggested fix:** Assert `lipo -archs "${BIN_PATH}"` contains both `arm64` and `x86_64` before signing.
- **Verification:** `grep -n "lipo\|BIN_PATH" build.sh`.

## Out of scope
- FocusedWindowProbe CF memory accounting is correct (ARC-managed `CFTypeRef?` out-params, no missing `CFRelease`). The `as!` casts are a types/correctness concern, not a leak.
- `Unmanaged.passUnretained(self)` cannot outlive its `AppDelegate` owner (`stop()` invalidates the tap first). Below floor.
- `MainActor.assumeIsolated` inside `DispatchQueue.main.async` is correct; `cmdIsDown`/`tabPending` mutated only on main. (Type-soundness nuance deferred to types lens.)
- `try?` on JSON decode→`.default` is intentional and tested.
