import AVFoundation
import UIKit

class FoodVideoSource: @unchecked Sendable {
    static let shared = FoodVideoSource()

    private enum Archive: Equatable {
        case primary
        case secondary
    }

    private struct FrameResolution {
        let archive: Archive
        let index: Int
    }

    private struct ReuseReference: Decodable {
        let frameKey: String
        let tier: String
    }

    private static let unsafeFrameKeyCharacters = CharacterSet(
        charactersIn: "/\\:*?\"<>|"
    )

    func hasVideo(for foodName: String) -> Bool {
        resolution(for: foodName) != nil
    }

    // ✅ 1. Добавяме заключване (Lock) за защита на данните при многонишков достъп
    private let lock = NSLock()
    
    // Генератори по вариант/размер, напр. "144", "240", "480", "1024"
    private var generators: [String: AVAssetImageGenerator] = [:]
    private var secondaryGenerators: [String: AVAssetImageGenerator] = [:]
    
    private var frameMap: [String: Int] = [:]
    private var reuseMap: [String: ReuseReference] = [:]
    private var frameMap2: [String: Int] = [:]
    private var timestamps: [Double] = []
    private var timestamps2: [Double] = []
    
    // Публичен достъп до списъка с храни
    var availableFoodKeys: [String] {
        let candidates = Set(frameMap.keys)
            .union(reuseMap.keys)
            .union(frameMap2.keys)
        return Set(
            candidates.compactMap { name in
                resolution(for: name) == nil ? nil : frameKey(name)
            }
        ).sorted()
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

        // 3. Reuse-map: dravya name -> an existing frame in archive 1.
        if let url = Bundle.main.url(forResource: "reuse-map", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let mapping = try? JSONDecoder().decode(
               [String: ReuseReference].self,
               from: data
           ) {
            self.reuseMap = mapping
        }

        // 4. Archive 2 is optional until the first accepted imagery batch ships.
        if let url = Bundle.main.url(forResource: "frame_map2", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let mapping = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.frameMap2 = mapping
        }

        if let url = Bundle.main.url(
            forResource: "frame_timestamps2",
            withExtension: "json"
        ),
           let data = try? Data(contentsOf: url),
           let times = try? JSONDecoder().decode([Double].self, from: data) {
            self.timestamps2 = times
        }
    }
    
    // Създава или връща наличен генератор за даден вариант
    private func generator(
        for variant: String,
        archive: Archive
    ) -> AVAssetImageGenerator? {
        // ✅ 2. Безопасно четене: Заключваме, проверяваме и отключваме
        lock.lock()
        let cachedGenerator = archive == .primary
            ? generators[variant]
            : secondaryGenerators[variant]
        if let cachedGenerator {
            lock.unlock()
            return cachedGenerator
        }
        lock.unlock()
        
        // Създаването на генератора е тежка операция, правим я БЕЗ заключване,
        // за да не блокираме другите нишки, които четат вече готови генератори.
        
        // Име на ресурса: food_archive_480.mp4 / food_archive2_480.mp4
        let resourceName = archive == .primary
            ? "food_archive_\(variant)"
            : "food_archive2_\(variant)"
        
        guard let videoURL = BundledLargeAssetLoader.url(
            forResource: resourceName,
            withExtension: "mp4"
        ) else {
            print("❌ Error: \(resourceName).mp4 missing from Bundle! Check Target Membership.")
            return nil
        }
        
        let asset = AVAsset(url: videoURL)
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
        let existing = archive == .primary
            ? generators[variant]
            : secondaryGenerators[variant]
        if let existing {
            return existing
        }
        
        if archive == .primary {
            generators[variant] = gen
        } else {
            secondaryGenerators[variant] = gen
        }
        return gen
    }
    
    // Старото API (по подразбиране 240)
    func getFrame(named name: String) -> UIImage? {
        return getFrame(named: name, variant: "240")
    }
    
    // Ново API – по вариант
    func getFrame(named name: String, variant: String) -> UIImage? {
        // 1. Търсим архива и индекса по име.
        guard let resolution = resolution(for: name) else {
            // print("❌ Name '\(name)' not found in frameMap")
            return nil
        }

        // 2. Проверка на генератора (видео файла).
        // Този метод вече е thread-safe вътрешно.
        guard let generator = generator(
            for: variant,
            archive: resolution.archive
        ) else {
            // print("❌ No generator for variant: \(variant)") // Може да се коментира, за да не спами логовете
            return nil
        }

        let frameTimestamps = resolution.archive == .primary
            ? timestamps
            : timestamps2
        
        // 3. Взимаме времето
        guard resolution.index < frameTimestamps.count else {
            print("❌ Index \(resolution.index) out of bounds for timestamps")
            return nil
        }
        
        let rawSeconds = frameTimestamps[resolution.index]
        
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

    private func resolution(for name: String) -> FrameResolution? {
        // Tier order is load-bearing: archive 1 -> reuse into archive 1 -> archive 2.
        if let index = frameIndex(for: name, in: frameMap) {
            return FrameResolution(archive: .primary, index: index)
        }

        if let reference = reuseReference(for: name),
           let index = frameIndex(for: reference.frameKey, in: frameMap) {
            return FrameResolution(archive: .primary, index: index)
        }

        if let index = frameIndex(for: name, in: frameMap2) {
            return FrameResolution(archive: .secondary, index: index)
        }

        return nil
    }

    private func frameIndex(
        for name: String,
        in mapping: [String: Int]
    ) -> Int? {
        if let rawIndex = mapping[name] {
            return rawIndex
        }
        return mapping[frameKey(name)]
    }

    private func reuseReference(for name: String) -> ReuseReference? {
        if let rawReference = reuseMap[name] {
            return rawReference
        }
        return reuseMap[frameKey(name)]
    }

    private func frameKey(_ name: String) -> String {
        String(
            name.unicodeScalars.map { scalar in
                Self.unsafeFrameKeyCharacters.contains(scalar)
                    ? "_"
                    : Character(scalar)
            }
        )
    }
}
