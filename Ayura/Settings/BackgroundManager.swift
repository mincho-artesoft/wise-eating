// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/AyurvedaAsanaYoga/AyurvedaAsanaYoga/Settings/BackgroundManager.swift ====
import SwiftUI
import Combine

@MainActor
final class BackgroundManager: ObservableObject {
    static let shared = BackgroundManager()

    private let isImageActiveKey = "isBackgroundImageActive_v1"
    private let selectedImageIndexKey = "selectedImageIndex_v1"
    private let selectedBuiltInBackgroundNameKey = "selectedBuiltInBackgroundName_v1"
    // Ключ за проследяване дали сме минали първоначалната настройка на background-а.
    private let hasSetDefaultSequoiaKey = "hasSetDefaultSequoia_v1"
    
    private let recentImagesLimit = 2
    private let filePrefix = "recent_background_"

    // Достъп до вграденото изображение
    let morningBreathImage: UIImage? = UIImage(named: "Morning Breath")
    let nightBreathImage: UIImage? = UIImage(named: "Night Breath")
    let sequoiaImage: UIImage? = UIImage(named: "sequoia")

    var builtInBackgrounds: [(name: String, image: UIImage)] {
        [
            (name: "Morning Breath", image: morningBreathImage),
            (name: "Night Breath", image: nightBreathImage),
            (name: "Sequoia", image: sequoiaImage)
        ].compactMap { option in
            guard let image = option.image else { return nil }
            return (option.name, image)
        }
    }

    @Published var selectedImage: UIImage? {
        didSet {
            let isImageSelected = selectedImage != nil
            UserDefaults.standard.set(isImageSelected, forKey: isImageActiveKey)

            // Запазваме built-in background по име, а потребителски image - по recent индекс.
            if isImageSelected, let image = selectedImage {
                if let builtInName = builtInBackgroundName(for: image) {
                    UserDefaults.standard.set(builtInName, forKey: selectedBuiltInBackgroundNameKey)
                    UserDefaults.standard.removeObject(forKey: selectedImageIndexKey)
                } else if let index = recentImages.firstIndex(of: image) {
                    UserDefaults.standard.set(index, forKey: selectedImageIndexKey)
                    UserDefaults.standard.removeObject(forKey: selectedBuiltInBackgroundNameKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: selectedImageIndexKey)
                    UserDefaults.standard.removeObject(forKey: selectedBuiltInBackgroundNameKey)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: selectedImageIndexKey)
                UserDefaults.standard.removeObject(forKey: selectedBuiltInBackgroundNameKey)
            }
            
            NotificationCenter.default.post(name: .backGroundChanged, object: nil)
        }
    }
    
    @Published var recentImages: [UIImage] = []
    
    var canAddMoreRecentImages: Bool {
        recentImages.count < recentImagesLimit
    }

    private init() {
        loadRecentImages()
        
        // --- ЛОГИКА ЗА ПЪРВО СТАРТИРАНЕ ---
        let hasSetDefault = UserDefaults.standard.bool(forKey: hasSetDefaultSequoiaKey)
        let wasImageActive = UserDefaults.standard.bool(forKey: isImageActiveKey)
        let selectedBuiltInBackgroundName = UserDefaults.standard.string(forKey: selectedBuiltInBackgroundNameKey)
        
        if !hasSetDefault {
            // Първо стартиране на приложението (или на тази версия):
            // Задаваме Morning Breath като избран background по подразбиране.
            if let morningBreathImage {
                self.selectedImage = morningBreathImage
                UserDefaults.standard.set(true, forKey: isImageActiveKey)
                UserDefaults.standard.set("Morning Breath", forKey: selectedBuiltInBackgroundNameKey)
                UserDefaults.standard.removeObject(forKey: selectedImageIndexKey)
                print("First Launch: Setting 'Morning Breath' as default background.")
            } else {
                self.selectedImage = nil
                UserDefaults.standard.set(false, forKey: isImageActiveKey)
                UserDefaults.standard.removeObject(forKey: selectedImageIndexKey)
                UserDefaults.standard.removeObject(forKey: selectedBuiltInBackgroundNameKey)
                print("First Launch: Morning Breath background is missing.")
            }

            // Маркираме, че сме го направили, за да не презаписваме избора на потребителя в бъдеще.
            UserDefaults.standard.set(true, forKey: hasSetDefaultSequoiaKey)
            
        } else if wasImageActive {
            // Стандартна логика за възстановяване
            let selectedIndex = UserDefaults.standard.integer(forKey: selectedImageIndexKey)
            
            if let selectedBuiltInBackgroundName,
               let builtInBackground = builtInBackgrounds.first(where: { $0.name == selectedBuiltInBackgroundName }) {
                self.selectedImage = builtInBackground.image
            } else if recentImages.indices.contains(selectedIndex) {
                self.selectedImage = recentImages[selectedIndex]
            } else {
                // Legacy fallback за стари инсталации, в които built-in изборът не е пазен по име.
                self.selectedImage = sequoiaImage ?? recentImages.first
            }
        } else {
            self.selectedImage = nil
        }
    }
    
    // Legacy helper за избор на Sequoia (без да я мести в Recent).
    func selectSequoia() {
        if let img = sequoiaImage {
            self.selectedImage = img
        }
    }
    
    func selectBuiltInBackground(_ image: UIImage) {
        self.selectedImage = image
    }

    func selectImage(_ image: UIImage) {
        if let index = recentImages.firstIndex(of: image) {
            recentImages.remove(at: index)
        }
        recentImages.insert(image, at: 0)
        self.selectedImage = image
        saveRecentImages()
    }
    
    // ... (Останалата част от файла addImageToRecents, deleteRecentImage и т.н. остава същата) ...
    
    func addImageToRecents(_ image: UIImage) {
        if let index = recentImages.firstIndex(of: image) {
            recentImages.remove(at: index)
        }
        
        recentImages.insert(image, at: 0)
        
        if recentImages.count > recentImagesLimit {
            recentImages.removeLast()
        }
        
        selectedImage = image
        saveRecentImages()
    }
    
    func deleteRecentImage(_ imageToDelete: UIImage) {
        recentImages.removeAll { $0 == imageToDelete }

        if selectedImage == imageToDelete {
            // Ако изтрием текущата, връщаме се към Sequoia ако я има, или първата налична
            selectedImage = sequoiaImage ?? recentImages.first
        }
        
        saveRecentImages()
    }

    func replaceRecentImage(oldImage: UIImage, with newImage: UIImage) {
        if let index = recentImages.firstIndex(of: oldImage) {
            recentImages[index] = newImage
            
            if selectedImage == oldImage {
                selectedImage = newImage
            }
            
            saveRecentImages()
            print("Изображението е заменено успешно.")
        } else {
            print("Не може да се намери изображение за замяна. Добавяне като ново.")
            addImageToRecents(newImage)
        }
    }
    
    func removeBackgroundImage() {
        selectedImage = nil
    }
    
    private func saveRecentImages() {
        clearAllRecentImageFiles()
        for (index, image) in recentImages.enumerated() {
            let fileURL = getDocumentsDirectory().appendingPathComponent("\(filePrefix)\(index).png")
            if let data = image.pngData() {
                try? data.write(to: fileURL)
            }
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func clearAllRecentImageFiles() {
        let fileManager = FileManager.default
        let documentsDirectory = getDocumentsDirectory()
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                if fileURL.lastPathComponent.hasPrefix(filePrefix) {
                    try fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            print("Error while deleting recent image files: \(error)")
        }
    }
    
    private func loadRecentImages() {
        recentImages.removeAll()
        for i in 0..<recentImagesLimit {
            let fileURL = getDocumentsDirectory().appendingPathComponent("\(filePrefix)\(i).png")
            if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
                recentImages.append(image)
            }
        }
    }

    private func builtInBackgroundName(for image: UIImage) -> String? {
        builtInBackgrounds.first(where: { $0.image == image })?.name
    }
}
