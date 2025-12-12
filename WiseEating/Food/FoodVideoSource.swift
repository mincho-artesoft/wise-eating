import AVFoundation
import UIKit

class FoodVideoSource: @unchecked Sendable {
    static let shared = FoodVideoSource()
    func hasVideo(for foodName: String) -> Bool {
           // Проверяваме дали името съществува в картата (frameMap)
           // Може да се наложи нормализация (lowercased), ако ключовете в json-а са малки букви
           // Тук приемаме, че ключовете съвпадат или са case-sensitive.
           // Ако искате case-insensitive, може да ползвате keys.contains, но е по-бавно.
           // За най-бързо:
           return frameMap[foodName] != nil
       }
    // ✅ 1. Добавяме заключване (Lock) за защита на данните при многонишков достъп
    private let lock = NSLock()
    
    // Генератори по вариант/размер, напр. "144", "240", "480", "1024"
    private var generators: [String: AVAssetImageGenerator] = [:]
    
    private var frameMap: [String: Int] = [:]
    private var timestamps: [Double] = []
    
    // Публичен достъп до списъка с храни
    var availableFoodKeys: [String] {
        return Array(frameMap.keys).sorted()
    }
    
    private init() {
        // 1. Зареждане на Timestamp-овете
        if let url = Bundle.main.url(forResource: "frame_timestamps", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let times = try? JSONDecoder().decode([Double].self, from: data) {
            self.timestamps = times
        } else {
            print("❌ Error: frame_timestamps.json missing or invalid!")
        }
        
        // 2. Зареждане на Mapping-а
        if let url = Bundle.main.url(forResource: "frame_map", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let mapping = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.frameMap = mapping
        } else {
            print("❌ Error: frame_map.json missing or invalid!")
        }
    }
    
    // Създава или връща наличен генератор за даден вариант
    private func generator(for variant: String) -> AVAssetImageGenerator? {
        // ✅ 2. Безопасно четене: Заключваме, проверяваме и отключваме
        lock.lock()
        if let existing = generators[variant] {
            lock.unlock()
            return existing
        }
        lock.unlock()
        
        // Създаването на генератора е тежка операция, правим я БЕЗ заключване,
        // за да не блокираме другите нишки, които четат вече готови генератори.
        
        // Име на ресурса: food_archive_480.mp4
        let resourceName = "food_archive_\(variant)"
        
        guard let path = Bundle.main.path(forResource: resourceName, ofType: "mp4") else {
            print("❌ Error: \(resourceName).mp4 missing from Bundle! Check Target Membership.")
            return nil
        }
        
        let asset = AVAsset(url: URL(fileURLWithPath: path))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        
        if let side = Double(variant) {
            gen.maximumSize = CGSize(width: side, height: side)
        } else {
            gen.maximumSize = CGSize(width: 1024, height: 1024)
        }
        
        let tolerance = CMTime(value: 1, timescale: 100)
        gen.requestedTimeToleranceBefore = tolerance
        gen.requestedTimeToleranceAfter = tolerance
        
        // ✅ 3. Безопасно писане: Заключваме преди запис в речника
        lock.lock()
        defer { lock.unlock() }
        
        // "Double-check locking": Проверяваме дали друга нишка не го е създала, докато сме зареждали
        if let existing = generators[variant] {
            return existing
        }
        
        generators[variant] = gen
        return gen
    }
    
    // Старото API (по подразбиране 240)
    func getFrame(named name: String) -> UIImage? {
        return getFrame(named: name, variant: "240")
    }
    
    // Ново API – по вариант
    func getFrame(named name: String, variant: String) -> UIImage? {
        // 1. Проверка на генератора (видео файла)
        // Този метод вече е thread-safe вътрешно
        guard let generator = generator(for: variant) else {
            // print("❌ No generator for variant: \(variant)") // Може да се коментира, за да не спами логовете
            return nil
        }
        
        // 2. Търсим индекса по име
        guard let index = frameMap[name] else {
            // print("❌ Name '\(name)' not found in frameMap")
            return nil
        }
        
        // 3. Взимаме времето
        guard index < timestamps.count else {
            print("❌ Index \(index) out of bounds for timestamps")
            return nil
        }
        
        let rawSeconds = timestamps[index]
        
        // Nudge стратегията (+0.01s)
        let time = CMTime(seconds: rawSeconds + 0.01, preferredTimescale: 60000)
        
        // 4. Вадим картинката
        // copyCGImage е Thread-Safe функция на Apple, така че тук няма нужда от допълнителен Lock
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("❌ Failed to extract image for \(name): \(error.localizedDescription)")
            return nil
        }
    }
}
