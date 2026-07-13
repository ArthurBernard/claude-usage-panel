import Foundation
import ServiceManagement

// "Start at login" via the modern ServiceManagement API (macOS 13+). Unlike the
// old LaunchAgent-plist approach, SMAppService.mainApp registers *this* app
// bundle as a login item that the user can also see and toggle in
// System Settings ▸ General ▸ Login Items. Works best when the bundle is
// installed in /Applications and signed (ad-hoc is enough for personal use);
// install.sh does both.
enum LoginItem {
    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register / unregister the login item. Idempotent and never throws to the
    /// caller — a failure (e.g. unsigned bundle, or a pending user approval) is
    /// logged so the UI toggle can just reflect `isEnabled` afterwards.
    static func setEnabled(_ on: Bool) {
        do {
            let service = SMAppService.mainApp
            if on {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            let verb = on ? "register" : "unregister"
            NSLog("[ClaudeUsagePanel] login item \(verb) failed: \(error)")
        }
    }
}
