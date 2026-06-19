import AppKit
import CoreGraphics

@MainActor
final class EventTapService {
    enum TapError: Error {
        case failedToCreateTap
    }

    // Virtual keycodes we care about (Carbon `kVK_*`).
    private static let tabKeyCode: Int64 = 48     // kVK_Tab
    private static let escapeKeyCode: Int64 = 53  // kVK_Escape

    // If the system disables the tap (timeout / user input) and re-enabling
    // doesn't take immediately, retry a bounded number of times before giving up.
    private static let reenableRetryDelay: TimeInterval = 0.5
    private static let maxReenableAttempts = 5

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let continuation: AsyncStream<Void>.Continuation

    /// Emits once each time a Cmd+Tab gesture completes (Cmd released while a
    /// Tab press was pending). Carries no payload — it is a pure edge signal.
    let events: AsyncStream<Void>

    private var cmdIsDown: Bool = false
    private var tabPending: Bool = false

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        self.events = stream
        self.continuation = continuation
    }

    func start() throws {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Try .cghidEventTap first (lowest level, events arrive before any
        // session-level interceptors like Karabiner). Fall back to session
        // tap if HID isn't available.
        let tap: CFMachPort? = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        )
        guard let tap else {
            PFLog.tap.error("CGEvent.tapCreate returned nil for both HID and session taps")
            throw TapError.failedToCreateTap
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        tap = nil
        continuation.finish()
    }

    fileprivate func reenableTap(attempt: Int = 0) {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        // tapEnable is best-effort; confirm it actually took. If the main run
        // loop was stalled the enable can silently fail, leaving the tap dead.
        guard !CGEvent.tapIsEnabled(tap: tap) else { return }

        guard attempt < Self.maxReenableAttempts else {
            PFLog.tap.error("event tap stuck disabled after \(Self.maxReenableAttempts) attempts")
            return
        }
        PFLog.tap.error("event tap failed to re-enable (attempt \(attempt + 1)); retrying")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reenableRetryDelay) { [weak self] in
            self?.reenableTap(attempt: attempt + 1)
        }
    }

    fileprivate func handleFlagsChanged(cmdDown: Bool) {
        let wasDown = cmdIsDown
        cmdIsDown = cmdDown
        if wasDown && !cmdDown && tabPending {
            tabPending = false
            continuation.yield(())
        }
    }

    fileprivate func handleKeyDown(keycode: Int64) {
        switch keycode {
        case Self.tabKeyCode where cmdIsDown:
            tabPending = true
        case Self.escapeKeyCode:
            // Esc cancels an in-progress switch (the OS app switcher behaves the
            // same way), so a pending gesture must not fire on the later Cmd up.
            tabPending = false
        default:
            break
        }
    }
}

private func eventTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let bits = UInt(bitPattern: userInfo)

    switch type {
    case .flagsChanged:
        let cmdDown = event.flags.contains(.maskCommand)
        dispatchToMain(bits) { $0.handleFlagsChanged(cmdDown: cmdDown) }
    case .keyDown:
        // Invariant: this keycode is read solely to detect Tab/Escape and must
        // never be logged, persisted, or transmitted. The tap sees every
        // keystroke system-wide — keeping this read-and-discard is what stops
        // it from being a keylogger.
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        dispatchToMain(bits) { $0.handleKeyDown(keycode: keycode) }
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        dispatchToMain(bits) { $0.reenableTap() }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

/// Revives the `EventTapService` from the tap's refcon and runs `body` on the
/// main actor. We hop via `DispatchQueue.main.async` (not an unstructured
/// `Task`) on purpose: the main queue preserves strict FIFO ordering, which the
/// Cmd/Tab state machine depends on — a reordered `flagsChanged` vs `keyDown`
/// would misfire. `MainActor.assumeIsolated` is sound here because the main
/// dispatch queue runs on the main actor's executor.
private func dispatchToMain(_ bits: UInt, _ body: @escaping @MainActor (EventTapService) -> Void) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            guard let raw = UnsafeMutableRawPointer(bitPattern: bits) else { return }
            let service = Unmanaged<EventTapService>.fromOpaque(raw).takeUnretainedValue()
            body(service)
        }
    }
}
