// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/Settings/BackgroundManager.swift ====
import SwiftUI
import Combine

@MainActor
final class BackgroundManager: ObservableObject {
    static let shared = BackgroundManager()

    private let isImageActiveKey = "isBackgroundImageActive_v1"
    private let selectedImageIndexKey = "selectedImageIndex_v1"
    // Ключ за проследяване дали сме задали Sequoia при първия старт
    private let hasSetDefaultSequoiaKey = "hasSetDefaultSequoia_v1"
    
    private let recentImagesLimit = 2
    private let filePrefix = "recent_background_"

    // Достъп до вграденото изображение
    let sequoiaImage: UIImage? = UIImage(named: "sequoia")

    @Published var selectedImage: UIImage? {
        didSet {
            let isImageSelected = selectedImage != nil
            UserDefaults.standard.set(isImageSelected, forKey: isImageActiveKey)

            // Запазваме индекса САМО ако изображението е от списъка с "Recent".
            // Ако е Sequoia (което не е в recentImages), не пипаме индекса или го махаме.
            if isImageSelected, let image = selectedImage, let index = recentImages.firstIndex(of: image) {
                UserDefaults.standard.set(index, forKey: selectedImageIndexKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectedImageIndexKey)
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
        
        if !hasSetDefault {
            // Първо стартиране на приложението (или на тази версия):
            // Задаваме Sequoia като избрана по подразбиране.
            if let sequoia = sequoiaImage {
                self.selectedImage = sequoia
                print("First Launch: Setting 'Sequoia' as default background.")
            }
            // Маркираме, че сме го направили, за да не презаписваме избора на потребителя в бъдеще.
            UserDefaults.standard.set(true, forKey: hasSetDefaultSequoiaKey)
            
        } else if wasImageActive {
            // Стандартна логика за възстановяване
            let selectedIndex = UserDefaults.standard.integer(forKey: selectedImageIndexKey)
            
            if recentImages.indices.contains(selectedIndex) {
                self.selectedImage = recentImages[selectedIndex]
            } else {
                // Ако е било активно изображение, но не е в recent (значи е Sequoia),
                // или индексът е счупен -> възстановяваме Sequoia ако е възможно
                self.selectedImage = sequoiaImage ?? recentImages.first
            }
        } else {
            self.selectedImage = nil
        }
    }
    
    // Метод за избор на Sequoia (без да я мести в Recent)
    func selectSequoia() {
        if let img = sequoiaImage {
            self.selectedImage = img
        }
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
}
