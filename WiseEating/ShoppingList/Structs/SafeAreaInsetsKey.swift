import SwiftUI

@MainActor
struct SafeAreaInsetsKey: @preconcurrency EnvironmentKey {
    static var defaultValue: EdgeInsets {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first { $0.isKeyWindow }?.safeAreaInsets ?? .init())
            .swiftUIInsets
    }
}
