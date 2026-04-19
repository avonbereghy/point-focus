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
    private var continuation: AsyncStream<Event>.Continuation?
    private var stream: AsyncStream<Event>?

    private var cmdIsDown: Bool = false
    private var tabPending: Bool = false

    init() {}

    var events: AsyncStream<Event> {
        if let stream { return stream }
        let (s, c) = AsyncStream.makeStream(of: Event.self)
        self.stream = s
        self.continuation = c
        return s
    }

    func start() throws {
        _ = events

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
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
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
    }

    fileprivate func handleFlagsChanged(cmdDown: Bool) {
        let wasDown = cmdIsDown
        cmdIsDown = cmdDown
        if wasDown && !cmdDown && tabPending {
            tabPending = false
            continuation?.yield(.cmdTabReleased)
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
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
