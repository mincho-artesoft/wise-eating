import SwiftUI
import Combine // UIImage е от UIKit, не от Combine, но Combine може да се използва за други неща
import UIKit // Добавяме UIKit за UIImage

@MainActor
final class EffectManager: ObservableObject {
    static let shared = EffectManager()
    
    @Published var snapshot: UIImage? = nil
    @Published var contentSnapshot: UIImage? = nil 
    @Published var currentGlobalAccentColor: Color = .primary

    @Published var isLightRowTextColor: Bool = false
    
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
