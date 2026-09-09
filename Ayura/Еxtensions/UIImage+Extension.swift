import SwiftUI
import UIKit

extension UIImage {
    
    /// Средна яркост на изображението (0 = много тъмно, 1 = много светло)
    private func averageLuminance() -> CGFloat? {
        guard let cgImage = self.cgImage else { return nil }
        
        // Рендърваме цялото изображение в 1x1 пиксел –
        // така автоматично взимаме средния цвят.
        let width = 1
        let height = 1
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        
        guard let context = CGContext(
            data: &pixel,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let r = CGFloat(pixel[0]) / 255.0
        let g = CGFloat(pixel[1]) / 255.0
        let b = CGFloat(pixel[2]) / 255.0
        
        // Стандартна формула за луминация
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance
    }
    
    /// Връща **само** .black или .white според това дали
    /// цялостният фон е по-скоро светъл или тъмен.
    func findGlobalAccentColor(threshold: CGFloat = 0.55) async -> Color {
        let luminance = averageLuminance() ?? 0.5
        // ако фонът е светъл -> черен текст, иначе -> бял текст
        return luminance > threshold ? .black : .white
    }
    
    static func createTransparentImage(with size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            // прозрачен фон по подразбиране
        }
    }
}

extension UIImage.Orientation {
    init(_ exif: CGImagePropertyOrientation) {
        switch exif {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
