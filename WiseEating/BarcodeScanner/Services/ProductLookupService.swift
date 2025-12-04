import Foundation
import SwiftData

public actor ProductLookupService {
    public static let shared = ProductLookupService()

    public struct ProductInfo: Sendable {
        public let title: String
    }

    private var cache: [String: ProductInfo] = [:]

    /// Търси информация за продукт по GTIN в локалната SwiftData база данни.
    public func lookup(gtin: String) async -> ProductInfo? {
        // 1. Проверка в кеша на актьора за бърз достъп
        if let cached = cache[gtin] {
            return cached
        }

        // 2. Извикване на ProductDataManager за търсене в базата данни.
        // Тъй като findProductName е async, използваме await.
        guard let productName = await ProductDataManager.shared.findProductName(for: gtin) else {
            // Продуктът не е намерен в локалната база данни
            return nil
        }

        // 3. Създаване на ProductInfo, кеширане и връщане на резултата
        let info = ProductInfo(title: productName)
        cache[gtin] = info
        
        return info
    }

    /// Оригиналният метод за търсене, който използва OpenFoodFacts API. Запазен е за евентуална бъдеща употреба.
    public func lookupFromNetwork(gtin: String) async -> ProductInfo? {
        if let cached = cache[gtin] { return cached }
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(gtin).json") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            // 👇 ПРИНТИРАМЕ ЦЕЛИЯ РЕСПОНС (статус + красиво JSON)
            #if DEBUG
            if let http = response as? HTTPURLResponse {
                print("📦 [OFF] GET \(url.absoluteString)")
                print("📜 [OFF] Status: \(http.statusCode)")
                if !http.allHeaderFields.isEmpty {
                    print("🪪 [OFF] Headers: \(http.allHeaderFields)")
                }
            }
            if let pretty = Self.prettyJSONString(from: data) {
                print("🧾 [OFF] Body (pretty JSON):\n\(pretty)")
            } else if let raw = String(data: data, encoding: .utf8) {
                print("🧾 [OFF] Body (raw):\n\(raw)")
            } else {
                print("🧾 [OFF] Body: <\(data.count) bytes, non-UTF8>")
            }
            #endif

            let resp = try JSONDecoder().decode(OFFResponse.self, from: data)
            guard resp.status == 1, let p = resp.product else { return nil }
            let name = p.product_name ?? "Unknown Product"
            let info = ProductInfo(title: name)
            cache[gtin] = info
            return info
        } catch {
            print("❌ Product lookup error: \(error)")
            return nil
        }
    }

    // MARK: - Helpers

    private static func prettyJSONString(from data: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data, options: []),
            JSONSerialization.isValidJSONObject(obj),
            let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
            let pretty = String(data: prettyData, encoding: .utf8)
        else { return nil }
        return pretty
    }

    private struct OFFResponse: Decodable { let status: Int?; let product: OFFProduct? }
    private struct OFFProduct: Decodable { let product_name: String?; let brands: String? }
}

