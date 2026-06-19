# Dx Findings

## Summary
PointFocus's backend is small and generally clean, but it carries polish debts: undocumented magic numbers (Tab keycode `48`, the `0.3`s probe deadline and `20ms` poll interval), two copy-paste blocks begging to be extracted, a never-used log category (`PFLog.warp`) and an information-free `Event` enum, plus README drift on the signing mechanism.

## Findings

### F-dx-001: `PFLog.warp` category defined but never used; warp/tap paths are nearly silent
- **Severity:** medium
- **Confidence:** 95
- **Files:** Sources/PointFocus/Services/PFLog.swift:7, Sources/PointFocus/Services/FocusRouter.swift:53-82, Sources/PointFocus/Services/CursorWarpService.swift:6-10
- **What:** `PFLog` declares three categories (`tap`, `router`, `warp`) but only two call sites exist (`PFLog.tap` once, `PFLog.router` once). `PFLog.warp` has zero usages, and the entire warp pipeline emits no logs. `handle()` silently returns when disabled, when permissions aren't granted, and when no focused window resolves (lines 54, 55, 74).
- **Why it matters:** The most common user-visible bug ("Cmd+Tab didn't move my cursor") is undiagnosable from logs — you can't tell whether the tap never fired, the probe returned nil, the app was disabled, or the warp ran and clamped off-target. The unused category implies observability that doesn't exist.
- **Suggested fix:** Add a debug log at the resolved-target site in `handle()` (bundleID + computed point) and on the "no focused window" early-return, using `PFLog.warp`; optionally log in `CursorWarpService.warp` when `clampToDisplays` actually moves the point. (If a category is still unused after, remove it.)
- **Verification:** `grep -rn "PFLog.warp" Sources/ Tests/` returns nothing today; should match the new call site(s) after.

### F-dx-002: Triplicated dispatch/assumeIsolated/Unmanaged block in `eventTapCallback`
- **Severity:** medium
- **Confidence:** 90
- **Files:** Sources/PointFocus/Services/EventTapService.swift:111-140
- **What:** The three `switch` arms each repeat the identical 5-line incantation (`DispatchQueue.main.async { MainActor.assumeIsolated { guard let raw = ...; let service = Unmanaged<...>.fromOpaque(raw).takeUnretainedValue(); service.<call>() } }`); only the final method call differs.
- **Why it matters:** Three copies of pointer-revival + actor-hop is a maintenance hazard — any threading-model change must be made in three places. Composes with F-types-003 (fix the isolation pattern once in the helper).
- **Suggested fix:** Extract a single local helper, e.g. `func onMain(_ body: @escaping (EventTapService) -> Void)` that performs the round-trip once; each arm becomes `onMain { $0.handleFlagsChanged(cmdDown: cmdDown) }`.
- **Verification:** `grep -c "MainActor.assumeIsolated" Sources/PointFocus/Services/EventTapService.swift` is 3 today; should drop to 1 (or 0 if refactored per F-types-003).

### F-dx-003: Magic keycode `48` for Tab is undocumented in code
- **Severity:** medium
- **Confidence:** 88
- **Files:** Sources/PointFocus/Services/EventTapService.swift:97
- **What:** `handleKeyDown` checks `if keycode == 48 && cmdIsDown`. The literal `48` is the Tab virtual keycode but there's no named constant or comment. The spec names it but it's only discoverable by cross-referencing.
- **Why it matters:** A bare `48` in a keyboard handler is a classic "what is this number" foot-gun.
- **Suggested fix:** `private static let tabKeyCode: Int64 = 48 // kVK_Tab` and compare against it. (Escape-cancel from F-correctness-001 should get the same treatment, e.g. `escapeKeyCode = 53`.)
- **Verification:** `grep -n "48" Sources/PointFocus/Services/EventTapService.swift` shows the literal only in the constant after the fix.

### F-dx-004: Unnamed timing magic numbers in the focus-probe poll loop
- **Severity:** medium
- **Confidence:** 85
- **Files:** Sources/PointFocus/Services/FocusRouter.swift:64, 67
- **What:** `handle()` uses `addingTimeInterval(0.3)` for the probe deadline and `Task.sleep(nanoseconds: 20_000_000)` (20ms) for the poll interval — bare literals. `SettingsStore` already names `debounceSeconds`, so the codebase has a precedent the router doesn't follow.
- **Why it matters:** These are the app's core timing knobs (how long to wait for activation, how often to re-probe); inline literals make them hard to find and tune, and disconnected from the explanatory comment.
- **Suggested fix:** Hoist to named static constants, e.g. `private static let probeDeadline: TimeInterval = 0.3` and `private static let probePollInterval: UInt64 = 20_000_000 // 20ms`.
- **Verification:** `grep -n "0.3\|20_000_000" Sources/PointFocus/Services/FocusRouter.swift` shows them only at the constant definitions.

### F-dx-005: `EventTapService.Event` enum is information-free; consumer discards the value
- **Severity:** medium
- **Confidence:** 80
- **Files:** Sources/PointFocus/Services/EventTapService.swift:6-8, 17, 92, Sources/PointFocus/Services/FocusRouter.swift:22
- **What:** `Event` is a single-case enum (`case cmdTabReleased`) streamed via `AsyncStream<Event>`. The only consumer iterates with `for await _ in stream` — it discards the payload and reacts to any emission. The enum carries no information beyond "something happened," yet pays the ceremony of a named type and `Sendable` conformance.
- **Why it matters:** API friction / over-abstraction; reads as vestigial scaffolding.
- **Suggested fix:** Either collapse to `AsyncStream<Void>` (simplest, matches usage), or leave a `// TODO:` noting intended future cases so the single-case enum reads as intentional. (NOTE: changing the type also edits the FocusRouter consumer line — keep both in the same track.)
- **Verification:** `grep -rn "switch.*event\|case .cmdTabReleased" Sources/` confirms no `switch` over `Event` exists.

### F-dx-006: Unused `proxy` parameter in C event-tap callback (DEFERRED — below floor)
- **Severity:** low
- **Confidence:** 92
- **Files:** Sources/PointFocus/Services/EventTapService.swift:104
- **What:** `eventTapCallback` declares `proxy: CGEventTapProxy` but never reads it (partly mandated by the C signature).
- **Why it matters:** Minor; invites a reader to hunt for where `proxy` matters when it doesn't.
- **Suggested fix:** Rename to `_ proxy: CGEventTapProxy` to signal "required by the C signature, intentionally unused."
- **Verification:** `grep -n "proxy" Sources/PointFocus/Services/EventTapService.swift` shows it only in the signature.

### F-dx-007: README "ad-hoc signed" claim contradicts build.sh and the README's own tech-stack section (OUT OF FIX SCOPE — README not in target set)
- **Severity:** medium
- **Confidence:** 90
- **Files:** README.md:37 (drift vs build.sh:12-70 and README.md:21)
- **What:** README line 37 says the app is installed "(ad-hoc signed, universal binary)". build.sh no longer ad-hoc signs — it generates and uses a stable self-signed cert (`CERT_NAME="PointFocus Local Sign"`), and README's own line 21 correctly describes "self-signed local code-signing cert … so the CDHash stays stable." Line 37 is stale and internally contradicts line 21.
- **Why it matters:** Doc/behavior drift on the exact mechanism that makes TCC grants persist — a user reading line 37 would believe rebuilds re-trigger permission prompts, the opposite of what now happens.
- **Suggested fix:** Update README.md:37 to match line 21. README is outside the resolved target set; offered as an optional one-line addendum at the approval checkpoint.
- **Verification:** `grep -n "ad-hoc\|self-signed" README.md`.

## Out of scope
- `storageKey` literal duplicated in `SettingsStoreTests.swift:54` (`private` prevents reuse). Nit.
- Triplicated window-resolution helpers (`focusedWindow`/`mainWindow`/`firstWindow`): each has a genuinely different shape; extraction payoff marginal. Nit.
- `+1`/`-1` clamp insets, `1.0`s perms poll interval: mildly magic but locally obvious. Nits.
- Other lenses (not DX): debounce-loses-write-on-quit (reliability), silent `try?`/early returns (reliability/correctness), `as!` force-casts (types).
