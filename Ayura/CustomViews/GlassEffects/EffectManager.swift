import SwiftUI
import Combine // UIImage е от UIKit, не от Combine, но Combine може да се използва за други неща
import UIKit // Добавяме UIKit за UIImage

@MainActor
final class EffectManager: ObservableObject {
    static let shared = EffectManager()
    
    @Published var snapshot: UIImage? = nil
    @Published var contentSnapshot: UIImage? = nil 
    @Published var currentGlobalAccentColor: Color = .black

    @Published var isLightRowTextColor: Bool = false

    /// The app appearance is derived from the foreground selected for the
    /// active in-app theme, never from the device light/dark setting.
    var appColorScheme: ColorScheme {
        isLightRowTextColor ? .dark : .light
    }

    var appInterfaceStyle: UIUserInterfaceStyle {
        isLightRowTextColor ? .dark : .light
    }

    /// A surface color that contrasts with the active themed foreground.
    var contrastingSurfaceColor: Color {
        isLightRowTextColor ? .black : .white
    }
    
    private let configKey = "glassEffectConfiguration"
    
    @Published var config: BlurConfiguration {
        didSet {
            saveConfiguration()
        }
    }
    
    private init() {
        self.config = EffectManager.loadConfiguration()
    }
    
    private static func loadConfiguration() -> BlurConfiguration {
        guard let data = UserDefaults.standard.data(forKey: "glassEffectConfiguration"), // Използваме константата configKey
              let decoded = try? JSONDecoder().decode(BlurConfiguration.self, from: data) else {
            return BlurConfiguration()
        }
        return decoded
    }
    
    private func saveConfiguration() {
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: configKey)
        }
    }
    
    func resetToDefaults() {
        withAnimation {
            config = BlurConfiguration()
        }
    }
}
