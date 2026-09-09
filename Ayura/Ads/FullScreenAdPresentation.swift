import UIKit

/// Serializes all full-screen formats, including ads opened from editor sheets.
@MainActor
enum FullScreenAdPresentation {
    private(set) static var isShowing = false

    static func begin() -> Bool {
        guard !isShowing, UIApplication.shared.applicationState == .active else { return false }
        isShowing = true
        return true
    }

    static func end() {
        isShowing = false
    }
}
