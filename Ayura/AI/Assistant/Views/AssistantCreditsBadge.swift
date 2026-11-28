import SwiftUI
import UIKit

/// The AI credit balance, shown in the assistant and on the plan screen.
struct AssistantCreditsBadge: View {
    let credits: Int?

    var body: some View {
        Label {
            if let credits {
                Text("\(credits) credits")
            } else {
                Text("Credits")
            }
        } icon: {
            Image(systemName: "sparkles")
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
        .accessibilityElement(children: .combine)
    }
}

/// Prepares a chosen photo for sending: a JPEG of at most 2048 px on the long
/// side, so a document stays readable and the upload stays small. No location
/// or other metadata is kept.
enum AssistantPhoto {
    static func jpeg(from data: Data, maxSide: CGFloat = 2048) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        for quality in [0.75, 0.6, 0.45] {
            if let jpeg = rendered.jpegData(compressionQuality: quality), jpeg.count < 5_500_000 { return jpeg }
        }
        return nil
    }
}
