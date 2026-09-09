import SwiftUI

/// Keeps the native switch thumb distinct from its track, even when a screen
/// uses the theme's white foreground as its tint.
struct ThemedSwitchToggleStyle: ToggleStyle {
    @ObservedObject private var effectManager = EffectManager.shared

    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(.green)
            .environment(\.colorScheme, effectManager.appColorScheme)
    }
}
