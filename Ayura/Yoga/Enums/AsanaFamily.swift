import Foundation

public enum AsanaFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    public var id: String { rawValue }

    case armBalance = "Arm Balance"
    case backbend = "Backbend"
    case bandhaAndMudra = "Bandha & Mudra"
    case core = "Core"
    case forwardBend = "Forward Bend"
    case hipOpener = "Hip Opener"
    case inversion = "Inversion"
    case kriya = "Kriya"
    case meditation = "Meditation"
    case pranayama = "Pranayama"
    case prone = "Prone"
    case restorative = "Restorative"
    case seated = "Seated"
    case standing = "Standing"
    case standingBalance = "Standing Balance"
    case supine = "Supine"
    case suryaNamaskar = "Surya Namaskar"
    case twist = "Twist"

    public var displayName: String {
        switch self {
        case .armBalance: String(localized: "Arm Balance")
        case .backbend: String(localized: "Backbend")
        case .bandhaAndMudra: String(localized: "Bandha & Mudra")
        case .core: String(localized: "Core")
        case .forwardBend: String(localized: "Forward Bend")
        case .hipOpener: String(localized: "Hip Opener")
        case .inversion: String(localized: "Inversion")
        case .kriya: String(localized: "Kriya")
        case .meditation: String(localized: "Meditation")
        case .pranayama: String(localized: "Pranayama")
        case .prone: String(localized: "Prone")
        case .restorative: String(localized: "Restorative")
        case .seated: String(localized: "Seated")
        case .standing: String(localized: "Standing")
        case .standingBalance: String(localized: "Standing Balance")
        case .supine: String(localized: "Supine")
        case .suryaNamaskar: String(localized: "Surya Namaskar")
        case .twist: String(localized: "Twist")
        }
    }
}
