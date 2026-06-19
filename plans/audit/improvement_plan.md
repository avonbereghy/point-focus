# Improvement Plan — PointFocus Backend Quality Sweep

Base commit: `7c9eb62` · Lenses: security, reliability, correctness, types, dx · Severity floor: **medium**

## Lens Coverage
| Lens | Findings | Critical | High | Medium | Low (deferred) |
|------|----------|----------|------|--------|-----|
| security    | 3 | 0 | 0 | 3 | 0 |
| reliability | 6 | 0 | 0 | 4 | 2 |
| correctness | 5 | 0 | 0 | 3 | 2 |
| types       | 4 | 0 | 2 | 2 | 0 |
| dx          | 7 | 0 | 0 | 6 | 1 |
| **Total**   | **25** | **0** | **2** | **18** | **5** |

Findings at/above floor (medium): **20** (2 high + 18 medium). Deferred below floor: **5** (kept in appendix).

## Top Risks (by severity × confidence)
1. **F-types-001** (high×0.88) — `as! AXValue` on AX position/size traps → whole-app crash from a misbehaving focused app, on every Cmd+Tab. `FocusedWindowProbe.swift:44-45`
2. **F-types-002** (high×0.82) — `as! AXUIElement` on app/window attributes traps → same crash surface. `FocusedWindowProbe.swift:18,59,66`
3. **F-reliability-004** (med×0.88) — debounced settings write lost if app quits within 200ms. `SettingsStore.swift` + `AppDelegate.swift`
4. **F-reliability-001** (med×0.85) — overlapping uncancelled probe Tasks on rapid Cmd+Tab → cursor lands in stale window. `FocusRouter.swift:53-82`
5. **F-correctness-002** (med×0.80) — settle loop defeated when initial probe is nil → warps to outgoing app's frame. `FocusRouter.swift:60-74`

## Execution model
Subagent file-writes are blocked in this session (the read-only auditors confirmed it), and parallel agents committing to one shared working tree would race on the git index. So the orchestrator executes the 5 tracks **sequentially in the main session**, editing only each track's assigned files and committing one Conventional Commit per track. The file-ownership matrix still governs which files each commit may touch — it is the contract that keeps each commit surgical and non-overlapping. No Foundation or Integration track is needed (no shared new symbol crosses tracks; `AppDelegate` is touched only by Track 3).

## Track Plan

### Track 1 — Event & Warp Pipeline
- **Files:** `Sources/PointFocus/Services/EventTapService.swift`, `Sources/PointFocus/Services/FocusRouter.swift`, `Sources/PointFocus/Services/CursorWarpService.swift`, `Sources/PointFocus/Services/PFLog.swift`
- **Findings:** F-correctness-001 (Escape cancels warp), F-correctness-002 (settle loop nil baseline), F-reliability-001 (cancel prior probe Task), F-reliability-002 (bounded tap-create retry), F-reliability-003 (verify `tapIsEnabled` after re-enable), F-types-003 (resolve `service` once; hop via `Task { @MainActor }` instead of `assumeIsolated`), F-security-003 (keycode never-log invariant comment), F-dx-001 (warp-path logging via `PFLog.warp`), F-dx-002 (extract single dispatch helper), F-dx-003 (`tabKeyCode`/`escapeKeyCode` constants), F-dx-004 (probe timing constants), F-dx-005 (collapse `Event` enum → `Void` + update consumer). Also resolves deferred F-reliability-005 (probe-task cancellation surface).
- **Why one track:** these files form one connected component — `Event`-type change (F-dx-005) edits both EventTapService and FocusRouter's consumer line; warp logging (F-dx-001) spans FocusRouter + CursorWarpService + PFLog.
- **Verification:** `swift build` (0 warnings on changed files); `grep` checks per finding; `swift test`; manual Cmd+Tab + Cmd+Tab+Esc smoke.

### Track 2 — AX Window Probe Safety
- **Files:** `Sources/PointFocus/Services/FocusedWindowProbe.swift`
- **Findings:** F-types-001 (`as? AXValue` + nil bail), F-types-002 (`as? AXUIElement` at 3 sites), F-correctness-003 (filter minimized/non-focused fallback windows).
- **Verification:** `grep -n 'as! AX' Sources/PointFocus/Services/FocusedWindowProbe.swift` returns nothing; `swift build`; `swift test`.

### Track 3 — Settings Persistence Durability
- **Files:** `Sources/PointFocus/Services/SettingsStore.swift`, `Sources/PointFocus/AppDelegate.swift`
- **Findings:** F-reliability-004 (`SettingsStore.flush()` synchronous write; call from `applicationWillTerminate`).
- **Verification:** new `SettingsStoreTests` case: `update` → `flush()` → re-instantiate without sleeping, assert persisted; `swift test`.

### Track 4 — Launch-at-Login Typed Errors
- **Files:** `Sources/PointFocus/Services/LaunchAtLoginService.swift`
- **Findings:** F-types-004 (`enum LaunchAtLoginError` + Swift 6 typed throws, or documented NSError domain).
- **Verification:** `swift build` clean; the change must not break the (out-of-scope) MenuBar call site — verify it still compiles.

### Track 5 — Build Script Hardening
- **Files:** `build.sh`
- **Findings:** F-security-001 (shorten cert validity to 825 days; document revocation), F-security-002 (single-quote EXIT trap body + `$WORK` guard; move import/trust after the codesign-visibility check or roll back on failure). Also resolves deferred F-reliability-006 (`lipo` arch assertion before signing).
- **Verification:** `bash -n build.sh` (syntax); `grep -n "days 825\|trap '" build.sh`; a clean `./build.sh` still produces a working signed universal `~/Applications/PointFocus.app` (run only with user consent — it touches the keychain).

## File Ownership Matrix
| File | Track 1 | Track 2 | Track 3 | Track 4 | Track 5 |
|------|---------|---------|---------|---------|---------|
| Sources/PointFocus/Services/EventTapService.swift   | ✏️ |    |    |    |    |
| Sources/PointFocus/Services/FocusRouter.swift       | ✏️ |    |    |    |    |
| Sources/PointFocus/Services/CursorWarpService.swift | ✏️ |    |    |    |    |
| Sources/PointFocus/Services/PFLog.swift             | ✏️ |    |    |    |    |
| Sources/PointFocus/Services/FocusedWindowProbe.swift|    | ✏️ |    |    |    |
| Sources/PointFocus/Services/SettingsStore.swift     |    |    | ✏️ |    |    |
| Sources/PointFocus/AppDelegate.swift                |    |    | ✏️ |    |    |
| Sources/PointFocus/Services/LaunchAtLoginService.swift |  |    |    | ✏️ |    |
| build.sh                                            |    |    |    |    | ✏️ |
| Tests/PointFocusTests/SettingsStoreTests.swift      |    |    | ✨/✏️ |  |    |

✏️ = modify existing · ✨ = create/add.

### Matrix validation (3.6)
1. No file appears in more than one track column. ✓
2. No Foundation track, so no foundation-file reuse conflict. ✓
3. `AppDelegate.swift` is edited only by Track 3 (the `flush()` call); Track 1's probe-task cancellation is internal to `FocusRouter` and does not wire into AppDelegate. ✓
4. Largest track (Track 1) = 4 files, ~271 source LOC, est. diff < 200 lines — within the ≤6 files / ≤500 lines budget. ✓

## Inter-Track Contracts
- **None across tracks.** Each track is self-contained. `SettingsStore.flush()` (Track 3) is consumed only within Track 3 (AppDelegate). `LaunchAtLoginError` (Track 4) is consumed only within its file (its UI caller is out of scope and must keep compiling). The `Event` → `Void` change (Track 1, F-dx-005) is contained to Track 1's two files.

## Acknowledged but Deferred (below medium floor, kept for the record)
- **F-reliability-005** (low) — FocusRouter has no `stop()`; process death cleans up today. Partially addressed by Track 1's probe-task cancellation; full AppDelegate-wired teardown deferred to avoid cross-track edits.
- **F-reliability-006** (low) — build.sh lacks a `lipo` universal-arch assertion. Folded into Track 5 (free, same file).
- **F-correctness-004** (low) — nearest-display uses center distance, not edge distance; cosmetic on mixed-size layouts.
- **F-correctness-005** (low) — half-open containment nudges an exact-edge boundary point 1px inward; benign.
- **F-dx-006** (low) — unused `proxy` param; rename to `_ proxy`. Trivial; may be swept in Track 1 since it's the same lines being refactored for F-dx-002.
- **F-dx-007** (medium, out of fix scope) — README.md:37 "ad-hoc signed" is stale vs build.sh's stable self-signed cert. README is outside the resolved target set; offered as an optional one-line doc fix at approval.

Re-run with `severity=low` to pull the deferred items into the fix scope.
