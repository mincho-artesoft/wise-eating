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
}
