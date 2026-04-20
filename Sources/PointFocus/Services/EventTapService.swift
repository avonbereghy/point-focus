import AppKit
import CoreGraphics

@MainActor
final class EventTapService {
    enum Event: Sendable {
        case cmdTabReleased
    }

    enum TapError: Error {
        case failedToCreateTap
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let continuation: AsyncStream<Event>.Continuation
    let events: AsyncStream<Event>

    private var cmdIsDown: Bool = false
    private var tabPending: Bool = false

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
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
            PFLog.tap.log("CGEvent.tapCreate returned nil for both HID and session taps")
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

    fileprivate func reenableTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    fileprivate func handleFlagsChanged(cmdDown: Bool) {
        let wasDown = cmdIsDown
        cmdIsDown = cmdDown
        if wasDown && !cmdDown && tabPending {
            tabPending = false
            continuation.yield(.cmdTabReleased)
        }
    }

    fileprivate func handleKeyDown(keycode: Int64) {
        if keycode == 48 && cmdIsDown {
            tabPending = true
        }
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let bits = UInt(bitPattern: userInfo)
    switch type {
    case .flagsChanged:
        let cmdDown = event.flags.contains(.maskCommand)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let raw = UnsafeMutableRawPointer(bitPattern: bits) else { return }
                let service = Unmanaged<EventTapService>.fromOpaque(raw).takeUnretainedValue()
                service.handleFlagsChanged(cmdDown: cmdDown)
            }
        }
    case .keyDown:
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let raw = UnsafeMutableRawPointer(bitPattern: bits) else { return }
                let service = Unmanaged<EventTapService>.fromOpaque(raw).takeUnretainedValue()
                service.handleKeyDown(keycode: keycode)
            }
        }
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let raw = UnsafeMutableRawPointer(bitPattern: bits) else { return }
                let service = Unmanaged<EventTapService>.fromOpaque(raw).takeUnretainedValue()
                service.reenableTap()
            }
        }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
