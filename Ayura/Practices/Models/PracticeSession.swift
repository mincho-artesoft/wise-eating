import EventKit
import Foundation
import SwiftData

@Model
public final class PracticeSession: Identifiable {
    @Attribute(.unique) public var id: UUID
    var practiceID: UUID
    var practiceCatalogNumber: Int
    var practiceTitle: String
    var practiceKind: String
    var artworkAssetName: String?
    var startedAt: Date
    var endedAt: Date
    var plannedDurationSeconds: Int
    var completed: Bool
    var calendarEventID: String?
    var profile: Profile?

    init(
        id: UUID = UUID(),
        practice: Practice,
        profile: Profile,
        startedAt: Date,
        endedAt: Date,
        plannedDurationSeconds: Int,
        completed: Bool
    ) {
        self.id = id
        self.practiceID = practice.id
        self.practiceCatalogNumber = practice.catalogNumber
        self.practiceTitle = practice.title
        self.practiceKind = practice.kind
        self.artworkAssetName = practice.artworkAssetName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedDurationSeconds = plannedDurationSeconds
        self.completed = completed
        self.profile = profile
    }

    var actualDuration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}

enum PracticeCalendarEvent {
    static let marker = "#PRACTICE#"

    static func invisiblePayload(for session: PracticeSession) -> String? {
        OptimizedInvisibleCoder.encode(
            from: [
                marker,
                session.id.uuidString,
                session.practiceID.uuidString,
                String(session.practiceCatalogNumber),
                session.completed ? "completed" : "ended",
            ].joined(separator: "|")
        )
    }

    static func isPractice(_ event: EKEvent) -> Bool {
        guard let notes = event.notes,
              let decoded = OptimizedInvisibleCoder.decode(from: notes) else {
            return false
        }
        return decoded.starts(with: marker)
    }
}
