# PointFocus — Agent Plan (Wave Execution Strategy)

Input:
- Spec: `specs/point_focus.spec.md`
- Prompt: `specs/point_focus.prompt.md`

## Stack Constraints (from spec — no `.claude/CLAUDE.md` in this repo)

| Constraint            | Value                                                                 |
|-----------------------|-----------------------------------------------------------------------|
| Language              | Swift 6 (strict concurrency)                                          |
| Min OS                | macOS 14 (Sonoma)                                                     |
| UI                    | SwiftUI + AppKit (menu bar, overlay)                                  |
| Build system          | Swift Package Manager executable target                               |
| Binary                | Universal (arm64 + x86_64)                                            |
| Signing               | Ad-hoc (`codesign --force --sign -`). No Developer ID required.       |
| Sandboxing            | **Off** (sandboxed apps cannot install session-level `CGEventTap`)    |
| Dependencies          | **Apple frameworks only** — AppKit, SwiftUI, Observation, ApplicationServices (AX), Carbon (keycodes), IOKit (HID access), ServiceManagement (Launch at Login). **No third-party packages.** |
| Observation model     | `@Observable` macro. Do **not** use `ObservableObject` / `@Published`. |
| Style                 | 4-space indent; no trailing whitespace; one primary type per file; filenames match type names; no comments except non-obvious platform quirks |
| Persistence           | `UserDefaults.standard` — single JSON payload under key `com.avb.pointfocus.v1` |
| Install target        | `~/Applications/PointFocus.app` via `./build.sh`                      |

If you need a dependency not listed above, **stop and report it** instead of installing it.

---

## Dependency Graph

```
Package.swift ─────────┐
                       │
FocusPoint  ──┐        │
Settings ─────┤        │
              │        │
SettingsStore ├────────┼──► EventTapService, FocusRouter  (Track A)
PermissionsService ────┤
CursorWarpService ─────┤    MenuBarController, LaunchAtLoginService  (Track B1)
FocusedWindowProbe ────┤
                       ├──► SettingsWindowController, SettingsView, AppOverrideRow  (Track B2)
                       │
                       ├──► OnboardingWindowController, OnboardingView  (Track C)
                       │
                       └──► PickerCoordinator, PickerOverlayWindow, PickerOverlayView  (Track D)
                                                                        │
           ┌────────────────────────────────────────────────────────────┘
           ▼
main.swift, AppDelegate.swift, Resources/Info.plist, Resources/PointFocus.entitlements, build.sh, README.md   (Wave 2)
```

**Parallel opportunity:** Tracks A / B1 / B2 / C / D each create non-overlapping new files and depend only on Wave 0 outputs. Cross-track coordination is limited to **interface shapes**, all of which are pinned in this plan.

**Revision from prompt.md:** The prompt's Track B was 5 files — over the 3-file ceiling. Split into **B1 (menu bar + launch-at-login)** and **B2 (settings window)**. B1 and B2 do not share any file.

---

## File Ownership Matrix

| File                                                             | W0 | A  | B1 | B2 | C  | D  | W2 |
|------------------------------------------------------------------|----|----|----|----|----|----|----|
| `Package.swift`                                                  | ✨ |    |    |    |    |    |    |
| `Sources/PointFocus/Models/FocusPoint.swift`                     | ✨ |    |    |    |    |    |    |
| `Sources/PointFocus/Models/Settings.swift`                       | ✨ |    |    |    |    |    |    |
| `Sources/PointFocus/Services/SettingsStore.swift`                | ✨ |    |    |    |    |    |    |
| `Sources/PointFocus/Services/PermissionsService.swift`           | ✨ |    |    |    |    |    |    |
| `Sources/PointFocus/Services/CursorWarpService.swift`            | ✨ |    |    |    |    |    |    |
| `Sources/PointFocus/Services/FocusedWindowProbe.swift`           | ✨ |    |    |    |    |    |    |
| `Sources/PointFocus/Services/EventTapService.swift`              |    | ✨ |    |    |    |    |    |
| `Sources/PointFocus/Services/FocusRouter.swift`                  |    | ✨ |    |    |    |    |    |
| `Sources/PointFocus/Services/LaunchAtLoginService.swift`         |    |    | ✨ |    |    |    |    |
| `Sources/PointFocus/UI/MenuBarController.swift`                  |    |    | ✨ |    |    |    |    |
| `Sources/PointFocus/UI/SettingsWindowController.swift`           |    |    |    | ✨ |    |    |    |
| `Sources/PointFocus/UI/SettingsView.swift`                       |    |    |    | ✨ |    |    |    |
| `Sources/PointFocus/UI/AppOverrideRow.swift`                     |    |    |    | ✨ |    |    |    |
| `Sources/PointFocus/UI/OnboardingWindowController.swift`         |    |    |    |    | ✨ |    |    |
| `Sources/PointFocus/UI/OnboardingView.swift`                     |    |    |    |    | ✨ |    |    |
| `Sources/PointFocus/UI/Picker/PickerCoordinator.swift`           |    |    |    |    |    | ✨ |    |
| `Sources/PointFocus/UI/Picker/PickerOverlayWindow.swift`         |    |    |    |    |    | ✨ |    |
| `Sources/PointFocus/UI/Picker/PickerOverlayView.swift`           |    |    |    |    |    | ✨ |    |
| `Sources/PointFocus/main.swift`                                  |    |    |    |    |    |    | ✨ |
| `Sources/PointFocus/AppDelegate.swift`                           |    |    |    |    |    |    | ✨ |
| `Resources/Info.plist`                                           |    |    |    |    |    |    | ✨ |
| `Resources/PointFocus.entitlements`                              |    |    |    |    |    |    | ✨ |
| `build.sh`                                                       |    |    |    |    |    |    | ✨ |
| `README.md`                                                      |    |    |    |    |    |    | ✨ |

**Validation (Step 3.5):**

1. ✅ No file appears in more than one Wave 1 column.
2. ✅ No file is ✨ in both Wave 0 and any Wave 1 track.
3. ✅ No Wave 2 file overlaps earlier waves — all ✨-new in W2.
4. ✅ No Wave 1 track exceeds 3 files (A=2, B1=2, B2=3, C=2, D=3).

---

## Inter-Wave Contracts

### Wave 0 → Wave 1 (what Wave 0 must deliver)

```swift
// Models/FocusPoint.swift
struct FocusPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    init(x: Double, y: Double)     // clamps both to [0,1]
    static let center: FocusPoint  // (0.5, 0.5)
}

// Models/Settings.swift
struct Settings: Codable, Equatable, Sendable {
    var enabled: Bool              // default true
    var launchAtLogin: Bool        // default false
    var globalPoint: FocusPoint    // default .center
    var overrides: [String: FocusPoint]  // default [:]
    static let `default`: Settings
}

// Services/SettingsStore.swift
@Observable @MainActor
final class SettingsStore {
    private(set) var settings: Settings
    init(defaults: UserDefaults = .standard)
    func update(_ mutate: (inout Settings) -> Void)     // debounced ≥200ms persist
    func focusPoint(for bundleID: String) -> FocusPoint // override ?? global
}

// Services/PermissionsService.swift
enum PermissionState: Sendable { case granted, denied, unknown }

@Observable @MainActor
final class PermissionsService {
    private(set) var accessibility: PermissionState
    private(set) var inputMonitoring: PermissionState
    func refreshNow()
    func startPolling()     // 1s cadence
    func stopPolling()
}

// Services/CursorWarpService.swift
@MainActor
enum CursorWarpService {
    static func warp(to axTopLeftPoint: CGPoint)   // clamps to nearest display
}

// Services/FocusedWindowProbe.swift
@MainActor
enum FocusedWindowProbe {
    struct Result: Sendable { let bundleID: String; let frame: CGRect }  // AX top-left frame
    static func current() -> Result?
}
```

### Wave 1 → Wave 2 (each track must deliver these exact public signatures — Wave 2 wires them)

```swift
// Track A
@MainActor final class EventTapService {
    enum Event: Sendable { case cmdTabReleased }
    init()
    var events: AsyncStream<Event> { get }
    func start() throws
    func stop()
}
@MainActor final class FocusRouter {
    init(store: SettingsStore, events: EventTapService, perms: PermissionsService)
    func start()
}

// Track B1
@MainActor final class LaunchAtLoginService {
    var isEnabled: Bool { get }
    func set(_ on: Bool) throws
}
@MainActor final class MenuBarController: NSObject {
    init(store: SettingsStore,
         perms: PermissionsService,
         onShowSettings:   @escaping () -> Void,
         onShowOnboarding: @escaping () -> Void,
         onQuit:           @escaping () -> Void)
}

// Track B2
@MainActor final class SettingsWindowController {
    static let shared: SettingsWindowController
    func show(store: SettingsStore,
              perms: PermissionsService,
              picker: PickerCoordinator,
              launch: LaunchAtLoginService)
}
// SettingsView and AppOverrideRow are internal SwiftUI views used only by SettingsWindowController.

// Track C
@MainActor final class OnboardingWindowController {
    static let shared: OnboardingWindowController
    func show(perms: PermissionsService)
}
// OnboardingView is internal SwiftUI view.

// Track D
@MainActor final class PickerCoordinator {
    init(store: SettingsStore)
    func pickGlobal() async -> Bool
    func pick(bundleID: String) async -> Bool
}
// PickerOverlayWindow and PickerOverlayView are internal AppKit types.
```

All cross-track references point **only** at the signatures above — every track can compile independently as long as these are respected.

---

## Wave 0 — Foundation (single session, sequential)

### Prompt

```
Read specs/point_focus.spec.md and
specs/point_focus.prompt.md fully.

Stack constraints:
- Swift 6, macOS 14+, SwiftPM executable target, universal (arm64+x86_64)
- Apple frameworks only. No third-party packages. Stop and report if you think you need one.
- @Observable macro (not ObservableObject). @MainActor most types.
- 4-space indent. No comments except non-obvious platform quirks. One primary type per file.

Create foundation files in this order:

1. Package.swift
   - swift-tools-version: 6.0
   - platforms: .macOS(.v14)
   - executable target "PointFocus" at Sources/PointFocus
   - no dependencies

2. Sources/PointFocus/Models/FocusPoint.swift
   - struct FocusPoint: Codable, Equatable, Sendable
   - var x, y: Double
   - init(x:y:) clamps to [0,1]
   - static let center = FocusPoint(x: 0.5, y: 0.5)

3. Sources/PointFocus/Models/Settings.swift
   - struct Settings: Codable, Equatable, Sendable
   - fields: enabled, launchAtLogin, globalPoint, overrides
   - defaults as in spec FR-073; static let `default` = Settings()

4. Sources/PointFocus/Services/SettingsStore.swift
   - @Observable @MainActor final class
   - key "com.avb.pointfocus.v1", JSONEncoder/JSONDecoder
   - update(_:) debounces persistence ≥200ms via DispatchWorkItem
   - focusPoint(for:) returns overrides[bundleID] ?? globalPoint
   - on decode failure fall back to Settings.default

5. Sources/PointFocus/Services/PermissionsService.swift
   - @Observable @MainActor final class
   - AXIsProcessTrustedWithOptions(nil) for accessibility; IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) for inputMonitoring
   - startPolling() schedules a Timer.scheduledTimer on main RunLoop at 1s, storing it; stopPolling() invalidates it.

6. Sources/PointFocus/Services/CursorWarpService.swift
   - enum (namespace). static func warp(to axTopLeftPoint: CGPoint)
   - convert AX top-left to Quartz coords using CGDisplayPixelsHigh(CGMainDisplayID())
   - clamp to nearest NSScreen.frame
   - CGWarpMouseCursorPosition + CGAssociateMouseAndMouseCursorPosition(1)

7. Sources/PointFocus/Services/FocusedWindowProbe.swift
   - enum namespace. struct Result { bundleID: String; frame: CGRect }
   - static func current() -> Result? using AXUIElementCreateSystemWide + kAXFocusedApplicationAttribute + kAXFocusedWindowAttribute + kAXPositionAttribute + kAXSizeAttribute + AXUIElementGetPid + NSRunningApplication

Files you create: the seven files above.
Files you modify: NONE (no existing Swift files yet).
Files you do NOT touch: anything else.

Verify:
  cd  && swift build 2>&1 | tail -20
  Expected: "Build complete!" with 0 errors. Warnings acceptable.
  (Expect unresolved-symbol errors only if you accidentally referenced Wave 1 types — if so, remove the reference.)
```

### Exit gate

- `swift build` exits 0.
- `git status` shows exactly the 7 new files staged/unstaged; no deletions; no modifications to pre-existing files.

### Commit

```
feat(foundation): add models and core services for PointFocus
```

---

## Wave 1 — Parallel Build (agent teams — 5 concurrent teammates)

Because tracks share only the Wave 0 surface and the contracted interfaces above, they can run fully in parallel. Teammates may message peers if they discover an interface ambiguity not covered by the contracts.

### Orchestrator prompt (main session)

```
Read specs/point_focus.spec.md,
specs/point_focus.prompt.md, and
plans/point_focus_agent_plan.md fully.

Stack constraints: same as Wave 0.

Confirm Wave 0 is committed and `swift build` passes before spawning teammates.

Spawn 5 teammates (agent teams, in parallel):

- name "track-a-events"  → Track A (event pipeline). Own only:
    Sources/PointFocus/Services/EventTapService.swift
    Sources/PointFocus/Services/FocusRouter.swift

- name "track-b1-menu"   → Track B1 (menu bar + launch-at-login). Own only:
    Sources/PointFocus/Services/LaunchAtLoginService.swift
    Sources/PointFocus/UI/MenuBarController.swift

- name "track-b2-settings" → Track B2 (settings window). Own only:
    Sources/PointFocus/UI/SettingsWindowController.swift
    Sources/PointFocus/UI/SettingsView.swift
    Sources/PointFocus/UI/AppOverrideRow.swift

- name "track-c-onboarding" → Track C (permission onboarding). Own only:
    Sources/PointFocus/UI/OnboardingWindowController.swift
    Sources/PointFocus/UI/OnboardingView.swift

- name "track-d-picker"  → Track D (per-app point picker). Own only:
    Sources/PointFocus/UI/Picker/PickerCoordinator.swift
    Sources/PointFocus/UI/Picker/PickerOverlayWindow.swift
    Sources/PointFocus/UI/Picker/PickerOverlayView.swift

Rules for every teammate:
- Read the shared interface contracts in plans/point_focus_agent_plan.md before writing code.
- Create ONLY files in your FILES OWNED list. Do not modify any other file.
- Do not add third-party packages.
- Simplicity: write the minimum code that satisfies the spec. No speculative configurability.
- If you think a peer track's interface is under-specified, send a SendMessage to that teammate
  (e.g. track-b2-settings → track-d-picker asking about PickerCoordinator.pick(bundleID:) return semantics)
  rather than guessing.
- Each teammate runs `swift build` in the repo root before reporting done. The build may have
  unresolved-symbol errors for Wave-2-only types like AppDelegate — those are expected if a teammate
  doesn't reference them. But no errors may originate in your own files.

Wait for all 5 teammates to complete, then run `swift build` once more in the main session and
confirm: Wave 1 + Wave 0 together still compile.
```

### Per-teammate prompts

#### Track A — `track-a-events`

```
Read specs/point_focus.spec.md, specs/point_focus.prompt.md, plans/point_focus_agent_plan.md.

Stack constraints: Swift 6, macOS 14+, Apple frameworks only, @Observable, 4-space indent.

Create exactly these two files:

1. Sources/PointFocus/Services/EventTapService.swift
   - @MainActor final class EventTapService
   - enum Event: Sendable { case cmdTabReleased }
   - var events: AsyncStream<Event>  (lazily created on first access; store continuation)
   - func start() throws — installs CGEventTap(.cgSessionEventTap, .headInsertEventTap, .listenOnly,
     eventsOfInterest: keyDown|flagsChanged, callback: cCallback, userInfo: Unmanaged.passUnretained(self).toOpaque())
   - C callback: on keyDown keycode 48 while .maskCommand set → self.tabPending = true.
     On flagsChanged where .maskCommand transitions from set to cleared and tabPending → emit .cmdTabReleased and tabPending = false.
     Bridge back to Swift main via DispatchQueue.main.async.
   - func stop() — invalidate tap and runloop source.
   - Store CFMachPort? for the tap and CFRunLoopSource? and add to .commonModes.

2. Sources/PointFocus/Services/FocusRouter.swift
   - @MainActor final class FocusRouter
   - init(store: SettingsStore, events: EventTapService, perms: PermissionsService)
   - func start() — spawns Task { for await _ in events.events { handle() } }
   - handle():
       guard store.settings.enabled else { return }
       guard perms.accessibility == .granted && perms.inputMonitoring == .granted else { return }
       guard let r = FocusedWindowProbe.current() else { return }
       let rp = store.focusPoint(for: r.bundleID)
       let target = CGPoint(x: r.frame.minX + r.frame.width * rp.x,
                            y: r.frame.minY + r.frame.height * rp.y)
       CursorWarpService.warp(to: target)

Files you create: the two files above.
Files you modify: NONE.

Verify: `swift build` in the repo root exits 0 (ignoring unresolved AppDelegate symbols — those don't exist yet and you don't reference them).
```

#### Track B1 — `track-b1-menu`

```
Read specs/point_focus.spec.md, specs/point_focus.prompt.md, plans/point_focus_agent_plan.md.

Stack: Swift 6, macOS 14+, AppKit + ServiceManagement, @Observable, 4-space.

Create exactly these two files:

1. Sources/PointFocus/Services/LaunchAtLoginService.swift
   - @MainActor final class
   - import ServiceManagement
   - var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
   - func set(_ on: Bool) throws — calls SMAppService.mainApp.register() / .unregister()

2. Sources/PointFocus/UI/MenuBarController.swift
   - @MainActor final class MenuBarController: NSObject
   - init(store: SettingsStore, perms: PermissionsService,
          onShowSettings, onShowOnboarding, onQuit: @escaping () -> Void)
   - Owns NSStatusItem with variableLength length.
   - Sets button.image based on state:
       * scope.slash  if !store.settings.enabled
       * exclamationmark.triangle  if perms.accessibility != .granted || perms.inputMonitoring != .granted
       * scope  otherwise
   - button.action = #selector(onClick(_:))   (left-click)
   - button.sendAction(on: [.leftMouseUp, .rightMouseUp])
   - onClick: if event.type == .rightMouseUp OR .option modifier held → showMenu(); else toggle store.settings.enabled.
   - showMenu() builds an NSMenu with items: "Enabled" (state-check toggles enabled),
     "Settings…" → onShowSettings,
     "Launch at Login" (state-check toggles via LaunchAtLoginService *but* this controller does NOT own LaunchAtLoginService — accept a LaunchAtLoginService instance as a 6th init param),
     separator, "Fix Permissions…" (visible only if permissions missing) → onShowOnboarding,
     separator, "Quit PointFocus" → onQuit.
   - Observe store + perms with withObservationTracking to refresh button.image when state changes.

   NOTE: Add `launch: LaunchAtLoginService` as a 6th init param. Track B1 owns both types so this is in-track; message track-b2-settings if it needs to know.

Files you create: the two files above.
Files you modify: NONE.

Verify: `swift build` exits 0 in the repo root.
```

#### Track B2 — `track-b2-settings`

```
Read specs/point_focus.spec.md, specs/point_focus.prompt.md, plans/point_focus_agent_plan.md.

Stack: Swift 6, macOS 14+, SwiftUI + AppKit, @Observable, 4-space.

Create exactly these three files:

1. Sources/PointFocus/UI/SettingsWindowController.swift
   - @MainActor final class SettingsWindowController
   - static let shared = SettingsWindowController()
   - func show(store: SettingsStore, perms: PermissionsService,
               picker: PickerCoordinator, launch: LaunchAtLoginService)
     — lazily create a single NSWindow hosting an NSHostingView(rootView: SettingsView(...)),
       title "PointFocus", size ~520×640, .titled|.closable|.miniaturizable, .center().
     — if already shown, bring to front + makeKey.
     — NSApp.activate(ignoringOtherApps: true)

2. Sources/PointFocus/UI/SettingsView.swift
   - struct SettingsView: View
   - @Bindable var store: SettingsStore
   - let perms: PermissionsService
   - let picker: PickerCoordinator
   - let launch: LaunchAtLoginService
   - Sections:
     * Status: Toggle "Enabled" bound to store.settings.enabled via binding that calls store.update
       + permissions row showing green/red chips, "Fix permissions…" button opens OnboardingWindowController.shared.show(perms:)
     * Global default: two TextFields with NumberFormatter (0.00–1.00) + Steppers + "Pick on screen…" button → Task { await picker.pickGlobal() }
     * Overrides: ForEach(store.settings.overrides.sorted(by: {$0.key < $1.key})) → AppOverrideRow
       + "Add app…" button opens NSOpenPanel scoped to /Applications filtering .application types
     * Launch at login: Toggle bound via a Binding that reads launch.isEnabled and writes via launch.set
     * Quit button at bottom calls NSApp.terminate(nil)

3. Sources/PointFocus/UI/AppOverrideRow.swift
   - struct AppOverrideRow: View
   - let bundleID: String
   - let point: FocusPoint
   - var onRepick: () -> Void
   - var onRemove: () -> Void
   - HStack: icon (via NSWorkspace.shared.icon(forFile: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path ?? ""))
            VStack(alignment:.leading) { app display name; bundleID in caption }
            Spacer()
            Text("x: \(x,2dp)  y: \(y,2dp)")
            Button("Re-pick") { onRepick() }
            Button("Remove", role: .destructive) { onRemove() }

Files you create: the three files above.
Files you modify: NONE.

Coordination: You consume `PickerCoordinator` (Track D) and `LaunchAtLoginService` (Track B1) by the exact signatures in plans/point_focus_agent_plan.md. If you see an ambiguity, SendMessage the owning teammate.

Verify: `swift build` exits 0 in the repo root.
```

#### Track C — `track-c-onboarding`

```
Read specs/point_focus.spec.md, specs/point_focus.prompt.md, plans/point_focus_agent_plan.md.

Stack: Swift 6, macOS 14+, SwiftUI + AppKit.

Create exactly these two files:

1. Sources/PointFocus/UI/OnboardingView.swift
   - struct OnboardingView: View
   - let perms: PermissionsService  (observation consumed via withObservationTracking or @Bindable if @Observable)
   - Title "Welcome to PointFocus"
   - Two rows, each showing:
       * Label (Accessibility / Input Monitoring)
       * Chip: green "Granted" or red "Not granted"
       * Button "Open System Settings" → opens the URL:
           Accessibility:       x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility
           Input Monitoring:    x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent
         via NSWorkspace.shared.open(url)
   - Footer text explaining that PointFocus will auto-dismiss once both are granted.

2. Sources/PointFocus/UI/OnboardingWindowController.swift
   - @MainActor final class OnboardingWindowController
   - static let shared = OnboardingWindowController()
   - func show(perms: PermissionsService)
     — lazily create NSWindow hosting OnboardingView(perms:), ~480×360, .titled|.closable.
     — if both permissions are already granted when shown, still allow showing (user clicked Fix Permissions).
     — start an observation loop: Task { @MainActor in while shown { try await Task.sleep(nanoseconds: 1_000_000_000); if perms.accessibility == .granted && perms.inputMonitoring == .granted { close() } } }
     — close() hides the window and marks shown = false.

Files you create: the two files above.
Files you modify: NONE.

Verify: `swift build` exits 0 in the repo root.
```

#### Track D — `track-d-picker`

```
Read specs/point_focus.spec.md, specs/point_focus.prompt.md, plans/point_focus_agent_plan.md.

Stack: Swift 6, macOS 14+, SwiftUI + AppKit.

Create exactly these three files:

1. Sources/PointFocus/UI/Picker/PickerCoordinator.swift
   - @MainActor final class PickerCoordinator
   - init(store: SettingsStore)
   - func pickGlobal() async -> Bool  — uses the screen with the key window as a virtual target; overlay covers the active screen's visibleFrame; computed relative point is stored to store.settings.globalPoint.
   - func pick(bundleID: String) async -> Bool
     Steps per spec FR-050 .. FR-057:
       (a) look up NSRunningApplication; if nil, NSWorkspace.shared.openApplication(at:configuration:) and poll up to 5s for focused-window availability.
       (b) app.activate(options: [.activateAllWindows])
       (c) poll FocusedWindowProbe.current() up to 2s until r.bundleID == bundleID, else return false.
       (d) create PickerOverlayWindow(frame: r.frame), show orderFrontRegardless + makeKey.
       (e) await the overlay's completion via withCheckedContinuation; overlay's view exposes onPick / onCancel closures.
       (f) if non-nil click point, compute FocusPoint(x: p.x / r.frame.width, y: p.y / r.frame.height) — top-left origin, convert if needed — and call store.update { $0.overrides[bundleID] = fp }.
       (g) return true on save, false on cancel.
     Also observe NSWorkspace.didTerminateApplication; if the picked bundleID terminates during the picker, close the overlay and return false.

2. Sources/PointFocus/UI/Picker/PickerOverlayWindow.swift
   - final class PickerOverlayWindow: NSWindow
   - override var canBecomeKey: Bool { true }
   - init(frame: CGRect):
       super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
       isOpaque = false; backgroundColor = .clear; level = .statusBar
       ignoresMouseEvents = false; acceptsMouseMovedEvents = true; hasShadow = false
       let v = PickerOverlayView(frame: CGRect(origin: .zero, size: frame.size))
       contentView = v
       setFrame(frame, display: true)  // AX frame is top-left; NSWindow uses bottom-left — convert: y = primaryMaxY - frame.maxY
   - Expose the content view's onPick / onCancel publishers by re-exposing them.

3. Sources/PointFocus/UI/Picker/PickerOverlayView.swift
   - final class PickerOverlayView: NSView
   - var onPick: ((NSPoint) -> Void)?
   - var onCancel: (() -> Void)?
   - var cursorPoint: NSPoint = .zero
   - override var acceptsFirstResponder: Bool { true }
   - init(frame:): super.init + add tracking area (bounds, [.mouseMoved, .activeAlways, .inVisibleRect])
   - override func draw(_ r: NSRect):
       NSColor.controlAccentColor.withAlphaComponent(0.18).setFill(); bounds.fill()
       NSColor.controlAccentColor.setStroke()
       let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)); border.lineWidth = 2; border.stroke()
       let h = NSBezierPath(); h.move(to: NSPoint(x: 0, y: cursorPoint.y)); h.line(to: NSPoint(x: bounds.width, y: cursorPoint.y)); h.lineWidth = 1; h.stroke()
       let v = NSBezierPath(); v.move(to: NSPoint(x: cursorPoint.x, y: 0)); v.line(to: NSPoint(x: cursorPoint.x, y: bounds.height)); v.lineWidth = 1; v.stroke()
       let rx = cursorPoint.x / bounds.width
       let ry = 1 - cursorPoint.y / bounds.height   // flip to top-left relative
       let hud = String(format: "x: %.2f  y: %.2f", rx, ry)
       draw hud as NSString with attrs: .systemFont(size: 12), white on black rounded-rect background, at cursorPoint offset (16,16), clamp inside bounds.
   - override func mouseMoved(_ e:): cursorPoint = convert(e.locationInWindow, from: nil); setNeedsDisplay(bounds)
   - override func mouseDown(_ e:):
       let p = convert(e.locationInWindow, from: nil)
       // convert to top-left relative click point expressed in source frame size:
       onPick?(NSPoint(x: p.x, y: bounds.height - p.y))
   - override func keyDown(_ e:): if e.keyCode == 53 { onCancel?() } else { super.keyDown(e) }

Files you create: the three files above.
Files you modify: NONE.

Verify: `swift build` exits 0 in the repo root.
```

### Wave 1 exit gate (orchestrator-enforced)

- All 5 teammates report done.
- `swift build` in repo root exits 0.
- `git status` shows exactly the 12 new Wave-1 files created, no files outside any track's ownership list touched.
- `rg -n 'func applicationDidFinishLaunching' Sources/` returns no match (Wave 2 hasn't run yet).

### Commit

```
feat(tracks): implement event pipeline, menu bar, settings, onboarding, and picker
```

---

## Wave 2 — Integration (single session, sequential)

### Prompt

```
Read specs/point_focus.spec.md, specs/point_focus.prompt.md, plans/point_focus_agent_plan.md.

Stack constraints: Swift 6, macOS 14+, Apple frameworks only. No third-party packages.

Create exactly these files, in order:

1. Sources/PointFocus/AppDelegate.swift
   - @MainActor final class AppDelegate: NSObject, NSApplicationDelegate
   - Owns: store, perms, events, launch, picker (lazy), router (lazy), menuBar
   - applicationDidFinishLaunching:
       perms.refreshNow(); perms.startPolling()
       if either permission != .granted { OnboardingWindowController.shared.show(perms: perms) }
       try? events.start()
       router.start()
       menuBar = MenuBarController(store: store, perms: perms, launch: launch,
         onShowSettings: { [unowned self] in SettingsWindowController.shared.show(store: store, perms: perms, picker: picker, launch: launch) },
         onShowOnboarding: { OnboardingWindowController.shared.show(perms: perms) },
         onQuit: { NSApp.terminate(nil) })

2. Sources/PointFocus/main.swift
   - import Cocoa
   - let delegate = AppDelegate()
   - NSApplication.shared.delegate = delegate
   - NSApplication.shared.setActivationPolicy(.accessory)
   - NSApplication.shared.run()

3. Resources/Info.plist
   - CFBundleIdentifier: com.avb.pointfocus
   - CFBundleName / DisplayName: PointFocus
   - CFBundleShortVersionString: 1.0.0
   - CFBundleVersion: 1
   - LSMinimumSystemVersion: 14.0
   - LSUIElement: true
   - NSAccessibilityUsageDescription: "PointFocus reads the focused app's window frame to place the cursor."
   - NSPrincipalClass: NSApplication

4. Resources/PointFocus.entitlements
   - Empty dict plist (no sandbox, no app groups).

5. build.sh (executable)
   - Outline in specs/point_focus.prompt.md → build for release universal, bundle into build/PointFocus.app, ad-hoc sign, replace ~/Applications/PointFocus.app.
   - set -euo pipefail
   - chmod +x at end via its own creation context is unnecessary; remind user to chmod once.

6. README.md
   - Title, brief description
   - Requirements (macOS 14+)
   - Build: `./build.sh`
   - First-run permissions (Accessibility + Input Monitoring)
   - Usage: Cmd+Tab, menu bar toggle, settings point picker
   - Uninstall: `rm -rf ~/Applications/PointFocus.app; defaults delete com.avb.pointfocus.v1`

Files you create: the six files above.
Files you modify: NONE.

Verify, in sequence:
  (a) chmod +x build.sh
  (b) ./build.sh
      Expected: "Installed to $HOME/Applications/PointFocus.app" at end, exit 0.
  (c) test -e "$HOME/Applications/PointFocus.app/Contents/MacOS/PointFocus"
  (d) /usr/libexec/PlistBuddy -c "Print :LSUIElement" "$HOME/Applications/PointFocus.app/Contents/Info.plist"
      Expected: "true"
  (e) codesign -dv "$HOME/Applications/PointFocus.app" 2>&1 | grep -q "Signature=adhoc"
```

### Exit gate

- `./build.sh` exits 0.
- `~/Applications/PointFocus.app` exists.
- `Info.plist` has `LSUIElement=true`.
- `codesign -dv` reports `Signature=adhoc`.
- Manual smoke (operator, not teammate): launch the app, grant permissions, Cmd+Tab — cursor warps.

### Commit

```
feat(app): wire PointFocus entrypoint, bundle, and install script
```

---

## Execution Plan

### Wave 0: Foundation
Paste the Wave 0 prompt into a single session.
Verify: `swift build` exits 0.
Commit: `feat(foundation): add models and core services for PointFocus`

### Wave 1: Parallel Build
Paste the Wave 1 orchestrator prompt; 5 teammates run concurrently using each track's per-teammate prompt.
Verify: `swift build` exits 0.
Commit: `feat(tracks): implement event pipeline, menu bar, settings, onboarding, and picker`

### Wave 2: Integration
Paste the Wave 2 prompt into a single session.
Verify: `./build.sh` succeeds; `~/Applications/PointFocus.app` installed; `LSUIElement=true`; ad-hoc signed.
Commit: `feat(app): wire PointFocus entrypoint, bundle, and install script`

### After execution
Run `/review-gauntlet` scoped to the files changed since base commit `8f9246f`.
