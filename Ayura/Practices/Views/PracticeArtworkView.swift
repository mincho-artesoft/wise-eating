import SwiftUI
import UIKit

enum PracticeArtworkResolver {
    private static let supportedCatalogNumbers = 810_000...810_059

    static func assetName(for practice: Practice) -> String? {
        if let sceneName = practice.sceneImageName,
           !sceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sceneName
        }

        guard supportedCatalogNumbers.contains(practice.catalogNumber) else {
            return nil
        }
        return "practice-\(practice.slug)"
    }
}

extension Practice {
    var artworkAssetName: String? {
        PracticeArtworkResolver.assetName(for: self)
    }
}

struct PracticeArtworkView: View {
    let practice: Practice

    var body: some View {
        Group {
            if let assetName = practice.artworkAssetName,
               let image = UIImage(named: assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(red: 0.035, green: 0.075, blue: 0.06)
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Artwork for \(practice.title)")
    }

    private var fallbackSymbol: String {
        switch practice.kind {
        case "meditation": "brain.head.profile"
        case "visualisation": "eye"
        case "pranayama": "wind"
        case "relaxation": "moon.zzz"
        case "kriya": "sparkles"
        default: "circle.hexagongrid"
        }
    }
}
