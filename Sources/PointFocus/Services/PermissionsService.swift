import AppKit
import ApplicationServices
import IOKit.hid
import Observation

enum PermissionState: Sendable {
    case granted, denied, unknown
}

@Observable @MainActor
final class PermissionsService {
    private(set) var accessibility: PermissionState = .unknown
    private(set) var inputMonitoring: PermissionState = .unknown

    @ObservationIgnored private var timer: Timer?

    func refreshNow() {
        accessibility = AXIsProcessTrustedWithOptions(nil) ? .granted : .denied

        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: inputMonitoring = .granted
        case kIOHIDAccessTypeDenied:  inputMonitoring = .denied
        default:                      inputMonitoring = .unknown
        }
    }

    func startPolling() {
        stopPolling()
        refreshNow()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
