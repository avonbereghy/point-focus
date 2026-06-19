import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService {
    /// Typed failure surface for login-item changes. `underlying` is the raw
    /// `SMAppService` error (an `NSError` in `SMAppServiceErrorDomain`), kept so
    /// a caller can inspect the specific cause — e.g. that the user must approve
    /// the item in System Settings → General → Login Items — instead of
    /// string-matching `localizedDescription`.
    enum LaunchAtLoginError: Error {
        case registrationFailed(enabling: Bool, underlying: any Error)
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func set(_ on: Bool) throws(LaunchAtLoginError) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw .registrationFailed(enabling: on, underlying: error)
        }
    }
}
