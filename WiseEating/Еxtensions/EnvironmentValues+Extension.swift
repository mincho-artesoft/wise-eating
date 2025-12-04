import SwiftUI

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        self[SafeAreaInsetsKey.self]
    }
    
    var backgroundSnapshot: UIImage? {
        get { self[BackgroundSnapshotKey.self] }
        set { self[BackgroundSnapshotKey.self] = newValue }
    }
}

private struct BackgroundSnapshotKey: EnvironmentKey {
    static let defaultValue: UIImage? = nil
}

