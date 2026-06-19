# Types Findings

## Summary
The backend is small and largely type-clean, but `FocusedWindowProbe` resolves Accessibility (AX) attribute values with five `as!` force-casts on `CFTypeRef` values whose dynamic type is controlled by the TARGET application's AX server, not by PointFocus — a non-Cocoa or misbehaving foreground app can return an unexpected CFType and trap the entire menu-bar process. Secondary items: the `MainActor.assumeIsolated` rests on an asserted (not statically proven) isolation guarantee, and `LaunchAtLoginService.set` rethrows an untyped error.

## Findings

### F-types-001: AX position/size values force-cast (`as! AXValue`) can trap on hostile/malformed AX data
- **Severity:** high
- **Confidence:** 88
- **Files:** Sources/PointFocus/Services/FocusedWindowProbe.swift:44-45
- **What:** After a nil guard, the code does `AXValueGetValue(posVal as! AXValue, .cgPoint, &origin)` and the same for `sizeVal as! AXValue`. The dynamic type of an AX attribute value is determined by the focused application's AX server. A non-Cocoa app (Tauri/winit/Electron — named in this file's own comments as the fallback path's targets) with a broken/adversarial AX implementation can return a different CFType; `as!` does not reinterpret CFTypes — a wrong dynamic type traps fatally.
- **Why it matters:** A single foreground app returning a non-`AXValue` crashes the whole PointFocus process. Reachable from untrusted external input (the focused app), and runs on every Cmd+Tab release.
- **Suggested fix:** `guard let posValue = posVal as? AXValue, let sizeValue = sizeVal as? AXValue else { return nil }` then call `AXValueGetValue(posValue, …)`. Returning nil already means "no warp performed," so the graceful path is free. Optionally also check `AXValueGetType(...)`.
- **Verification:** `grep -n 'as! AXValue' Sources/PointFocus/Services/FocusedWindowProbe.swift` returns nothing after the fix; `swift build` clean.

### F-types-002: AX element force-casts (`as! AXUIElement`) in window/app resolution can trap
- **Severity:** high
- **Confidence:** 82
- **Files:** Sources/PointFocus/Services/FocusedWindowProbe.swift:18, 59, 66
- **What:** Three sites force-cast an unwrapped `CFTypeRef` to `AXUIElement`: line 18 (focused application), line 59 (focused window), line 66 (main window). The returned CFType is supplied by an external app's AX server; an unexpected dynamic type traps. The sibling `firstWindow(for:)` (line 72) already uses the safe conditional cast `ref as? [AXUIElement]` — these three sites are inconsistent with the established safe pattern in the same file.
- **Why it matters:** Same crash surface as F-types-001; a misbehaving focused app can hard-crash the menu-bar utility on Cmd+Tab.
- **Suggested fix:** Use conditional casts mirroring `firstWindow`: line 18 `guard let appElement = appRef as? AXUIElement`; lines 59/66 `guard let element = ref as? AXUIElement else { return nil }`. All three already sit on paths that return nil/skip gracefully.
- **Verification:** `grep -n 'as! AXUIElement' Sources/PointFocus/Services/FocusedWindowProbe.swift` returns nothing after the fix; `swift build` clean.

### F-types-003: `MainActor.assumeIsolated` in the C event-tap callback rests on an asserted, not proven, isolation guarantee
- **Severity:** medium
- **Confidence:** 70
- **Files:** Sources/PointFocus/Services/EventTapService.swift:114-137
- **What:** The C callback runs on a CoreGraphics thread. Each branch does `DispatchQueue.main.async { MainActor.assumeIsolated { ... } }`. The `Unmanaged`/refcon round-trip is type-sound and the `passUnretained`↔`takeUnretainedValue` pairing is correct. The soundness gap is the isolation ASSUMPTION: `MainActor.assumeIsolated` is a runtime assertion that the current executor is the main actor's — it holds because the closure is dispatched onto `DispatchQueue.main`, but that equivalence is convention the type system does not verify, and it's redundant (dispatching to a `@MainActor` method via the main queue is the same thing it asserts).
- **Why it matters:** Currently correct, but encodes a thread/actor-equivalence invariant as a runtime trap rather than a compiler-checked guarantee; a future refactor of the dispatch target silently converts a mismatch into a crash instead of a build error.
- **Suggested fix:** Prefer hopping to the actor directly so isolation is compiler-checked: resolve `service` once via the `Unmanaged` round-trip, then `Task { @MainActor in service.handleX(...) }`. At minimum document why `DispatchQueue.main` ≡ `MainActor` here. (Composes with DX's helper-extraction finding.)
- **Verification:** `swift build` clean; manual Cmd+Tab smoke test; handlers still run on the main actor.

### F-types-004: `LaunchAtLoginService.set` rethrows an opaque, untyped error
- **Severity:** medium
- **Confidence:** 60
- **Files:** Sources/PointFocus/Services/LaunchAtLoginService.swift:10-16
- **What:** `func set(_ on: Bool) throws` forwards whatever `SMAppService.register()`/`unregister()` throws as untyped `any Error`. `SMAppService` raises `NSError`s in `SMAppServiceErrorDomain` whose codes distinguish meaningful conditions (not permitted, requires approval, already registered). The public surface erases that, so a caller cannot type-discriminate the failure.
- **Why it matters:** Callers must swallow the error or string-match `localizedDescription`, both type-unsafe ways to recover information the error already carries.
- **Suggested fix:** Define `enum LaunchAtLoginError: Error` mapping the relevant codes and adopt Swift 6 typed throws (`throws(LaunchAtLoginError)`), or at minimum document that the thrown value is an `NSError` in the `SMAppService` domain.
- **Verification:** `grep -n 'throws' Sources/PointFocus/Services/LaunchAtLoginService.swift`; confirm the call site can branch on the typed error without string matching.

## Out of scope
- `FocusedWindowProbe.swift:72 ref as? [AXUIElement]` is the correct pattern F-001/002 should copy. No finding.
- The `EventTapService` `Unmanaged` round-trip and `passUnretained`↔`takeUnretainedValue` retain pairing are balanced (no UAF); `bits:UInt` carried across the `@Sendable` closure is sound; the `guard let raw` is effectively dead but harmless.
- `handleKeyDown(keycode: Int64)` vs literal `48`: no lossy conversion (magic number is a DX concern).
- All `Sendable` conformances (`Result`, `Event`, `PermissionState`, `FocusPoint`, `Settings`) are over Sendable members. Correct.
- `SettingsStore` `try?` on JSON: intentional fall-back, covered by tests; discarded error carries no actionable type info (reliability/observability concern).
- `AppDelegate` `[unowned self]` and lazy coordinators: lifetime concern; fix would touch out-of-scope UI files.
- `build.sh` has no static typing to audit.
