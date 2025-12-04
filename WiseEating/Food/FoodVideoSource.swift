import AVFoundation
import UIKit

class FoodVideoSource: @unchecked Sendable {
    static let shared = FoodVideoSource()
    
    // Генератори по вариант/размер, напр. "144", "240", "480", "1024"
    private var generators: [String: AVAssetImageGenerator] = [:]
    
    private var frameMap: [String: Int] = [:]
    private var timestamps: [Double] = []
    
    private init() {
        // 1. Зареждане на Timestamp-овете (общи за всички варианти)
        if let url = Bundle.main.url(forResource: "frame_timestamps", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let times = try? JSONDecoder().decode([Double].self, from: data) {
            self.timestamps = times
        }
        
        // 2. Зареждане на Mapping-а (Име -> Индекс) – също общ
        if let url = Bundle.main.url(forResource: "frame_map", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let mapping = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.frameMap = mapping
        }
    }
    
    // Създава или връща наличен генератор за даден вариант
    private func generator(for variant: String) -> AVAssetImageGenerator? {
        if let existing = generators[variant] {
            return existing
        }
        
        // Име на ресурса: food_archive_144.mp4, food_archive_240.mp4, food_archive_480.mp4, ...
        let resourceName = "food_archive_\(variant)"
        
        guard let path = Bundle.main.path(forResource: resourceName, ofType: "mp4") else {
            print("Error: \(resourceName).mp4 missing")
            return nil
        }
        
        let asset = AVAsset(url: URL(fileURLWithPath: path))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        
        // Пробваме да разчетем варианта като размер (px)
        if let side = Double(variant) {
            gen.maximumSize = CGSize(width: side, height: side)
        } else {
            // fallback – ако нещо е странно с варианта
            gen.maximumSize = CGSize(width: 1024, height: 1024)
        }
        
        // Важни настройки за бързина при синхронно четене
        let tolerance = CMTime(value: 1, timescale: 100)
        gen.requestedTimeToleranceBefore = tolerance
        gen.requestedTimeToleranceAfter = tolerance
        
        generators[variant] = gen
        return gen
    }
    
    // Старото API – за обратна съвместимост (дефолт 240)
    func getFrame(named name: String) -> UIImage? {
        return getFrame(named: name, variant: "240")
    }
    
    // Ново API – по вариант
    func getFrame(named name: String, variant: String) -> UIImage? {
        guard let generator = generator(for: variant) else { return nil }
        
        // 1. Търсим индекса по име
        guard let index = frameMap[name] else { return nil }
        
        // 2. Взимаме времето
        guard index < timestamps.count else { return nil }
        let rawSeconds = timestamps[index]
        
        // Nudge стратегията (+0.01s), за да не хванем предишния кадър
        let time = CMTime(seconds: rawSeconds + 0.01, preferredTimescale: 60000)
        
        // 3. Вадим картинката СИНХРОННО (copyCGImage)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("Failed to extract image for \(name) [variant \(variant)]: \(error)")
            return nil
        }
    }
}
