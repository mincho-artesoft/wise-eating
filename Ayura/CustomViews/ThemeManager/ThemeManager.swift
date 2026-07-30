import SwiftUI
import UIKit // Необходимо е за достъп до UITraitCollection

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    // Ключът, който следи дали приложението е стартирано преди.
    private let hasLaunchedBeforeKey = "hasLaunchedBefore_v1"
    
    @AppStorage("selectedThemeName") private var selectedThemeName: String = ""
    private let customThemesKey = "customThemes_v2"

    @Published var currentTheme: Theme
    @Published var allAvailableThemes: [Theme]
    
    private init() {
        self.currentTheme = Theme.pastelAurora // Временна стойност
        self.allAvailableThemes = [] // Временна стойност
        
        // --- НАЧАЛО НА ПРОМЯНАТА ---
        // Проверяваме дали приложението се стартира за първи път.
        if !UserDefaults.standard.bool(forKey: hasLaunchedBeforeKey) {
            // Разпознаваме системната тема (dark/light).
            let isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
            
            // Задаваме името на темата по подразбиране.
            // @AppStorage ще запише тази стойност автоматично.
            self.selectedThemeName = isDarkMode ? "Galactic Void" : "Frozen Tundra"
            
            // Маркираме, че първоначалната настройка е направена.
            UserDefaults.standard.set(true, forKey: hasLaunchedBeforeKey)
            print("First launch: Setting theme to '\(self.selectedThemeName)' based on system appearance.")
        }
        // --- КРАЙ НА ПРОМЯНАТА ---
        
        // Ако selectedThemeName все още е празно (случва се само преди промяната по-горе),
        // задаваме стойност по подразбиране, за да избегнем проблеми.
        if self.selectedThemeName.isEmpty {
            self.selectedThemeName = "Fresh Meadow"
        }
        
        // Зареждаме и подреждаме всички теми.
        self.updateAvailableThemes()
        
        // Намираме правилната текуща тема.
        if let savedTheme = allAvailableThemes.first(where: { $0.name == self.selectedThemeName }) {
            self.currentTheme = savedTheme
        } else {
            // Ако запазената тема не е намерена, връщаме се към първата налична.
            self.currentTheme = allAvailableThemes.first ?? Theme.defaultThemes.first ?? Theme.pastelAurora
        }
    }
    
    // НОВА ПОМОЩНА ФУНКЦИЯ: Централизира логиката за зареждане и подреждане
    private func updateAvailableThemes() {
        let customThemes = self.loadCustomThemes()
        // ПРОМЯНА В РЕДА: Потребителските теми вече са първи
        self.allAvailableThemes = customThemes + Theme.defaultThemes
    }
    
    func setTheme(to theme: Theme) {
        currentTheme = theme
        selectedThemeName = theme.name
    }
    
    func saveCustomTheme(_ theme: Theme) {
        var customThemes = loadCustomThemes()
        
        if let index = customThemes.firstIndex(where: { $0.id == theme.id }) {
            customThemes[index] = theme
        } else {
            // Когато добавяме нова тема, я слагаме в началото на потребителския списък
            customThemes.insert(theme, at: 0)
        }
        
        do {
            let data = try JSONEncoder().encode(customThemes)
            UserDefaults.standard.set(data, forKey: customThemesKey)
            
            // ПРОМЯНА: Използваме помощната функция, за да обновим списъка
            updateAvailableThemes()
            print("Темата е запазена успешно!")
        } catch {
            print("Грешка при запазване на темата: \(error.localizedDescription)")
        }
    }
    
    func deleteCustomTheme(themeToDelete: Theme) {
        guard !themeToDelete.isDefaultTheme else {
            print("Не може да изтриете тема по подразбиране.")
            return
        }

        var customThemes = loadCustomThemes()
        customThemes.removeAll { $0.id == themeToDelete.id }

        do {
            let data = try JSONEncoder().encode(customThemes)
            UserDefaults.standard.set(data, forKey: customThemesKey)
            
            // ПРОМЯНА: Използваме помощната функция, за да обновим списъка
            updateAvailableThemes()
            print("Темата е изтрита успешно!")
        } catch {
            print("Грешка при изтриване на темата: \(error.localizedDescription)")
        }

        if currentTheme.id == themeToDelete.id {
            // Връщаме се към първата тема по подразбиране, ако изтрием текущата
            setTheme(to: Theme.defaultThemes.first ?? .pastelAurora)
        }
    }
    
    private func loadCustomThemes() -> [Theme] {
        guard let data = UserDefaults.standard.data(forKey: customThemesKey) else {
            return []
        }
        
        do {
            let themes = try JSONDecoder().decode([Theme].self, from: data)
            return themes
        } catch {
            print("Грешка при зареждане на потребителските теми: \(error.localizedDescription)")
            return []
        }
    }
}
