import Foundation
import AppIntents

public struct DetectedObjectEntity: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String      // The raw content of the barcode
    public var category: String?  // e.g., "QR · URL", "Barcode · GTIN"
    public var confidence: Double
    public var explanation: String // A user-friendly explanation
    public var thumbnailKey: String?
}
