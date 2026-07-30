import SwiftUI
import EventKit
import SwiftData

@Model
public final class Training: Codable, Identifiable, Equatable, @unchecked Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var startTime: Date
    public var endTime: Date
    public var notes: String? = nil
    
    public var calendarEventID: String? = nil
    
    public var reminderMinutes: Int? = nil
    public var notificationID: String? = nil

    public var profile: Profile?

    public init(id: UUID = .init(), name: String, startTime: Date, endTime: Date, notes: String? = nil, reminderMinutes: Int? = nil, notificationID: String? = nil, calendarEventID: String? = nil, profile: Profile? = nil) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
        self.reminderMinutes = reminderMinutes
        self.notificationID = notificationID
        self.calendarEventID = calendarEventID
        self.profile = profile
    }

    public convenience init(from other: Training) {
        self.init(
            id: other.id,
            name: other.name,
            startTime: other.startTime,
            endTime: other.endTime,
            notes: other.notes,
            reminderMinutes: other.reminderMinutes,
            notificationID: other.notificationID,
            calendarEventID: other.calendarEventID,
            profile: other.profile
        )
    }
    
    public convenience init(event ev: EKEvent) {
        let rawNotes = ev.notes ?? ""
        let invisAlphabet: Set<UnicodeScalar> = Set(["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{2061}", "\u{2062}", "\u{2063}", "\u{2064}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}"].flatMap { $0.unicodeScalars })
        let hiddenScalars = rawNotes.unicodeScalars.filter { invisAlphabet.contains($0) }
        let decodedNotes = OptimizedInvisibleCoder.decode(from: String(String.UnicodeScalarView(hiddenScalars)))
        
        let reminderMins: Int?
        if let alarm = ev.alarms?.first, alarm.relativeOffset < 0 {
            reminderMins = Int(abs(alarm.relativeOffset / 60))
        } else {
            reminderMins = nil
        }

        self.init(
            name: ev.title ?? "Training",
            startTime: ev.startDate,
            endTime: ev.endDate,
            notes: decodedNotes,
            reminderMinutes: reminderMins,
            calendarEventID: ev.eventIdentifier
        )
    }
    
    public static func == (lhs: Training, rhs: Training) -> Bool {
        lhs.id == rhs.id &&
        lhs.startTime == rhs.startTime &&
        lhs.endTime   == rhs.endTime
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, startTime, endTime, reminderMinutes, notificationID, calendarEventID, notes
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        reminderMinutes = try container.decodeIfPresent(Int.self, forKey: .reminderMinutes)
        notificationID = try container.decodeIfPresent(String.self, forKey: .notificationID)
        calendarEventID = try container.decodeIfPresent(String.self, forKey: .calendarEventID)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(reminderMinutes, forKey: .reminderMinutes)
        try container.encodeIfPresent(notificationID, forKey: .notificationID)
        try container.encodeIfPresent(calendarEventID, forKey: .calendarEventID)
    }

    public static func defaultTrainings() -> [Training] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let morningStart = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: startOfDay)!
        let morningEnd   = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: startOfDay)!
        let eveningStart = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: startOfDay)!
        let eveningEnd   = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: startOfDay)!
        return [
            Training(name: "Morning Workout", startTime: morningStart, endTime: morningEnd),
            Training(name: "Evening Gym", startTime: eveningStart, endTime: eveningEnd)
        ]
    }

    public func detached(for day: Date) -> Training {
        let cal = Calendar.current
        let hmsStart = cal.dateComponents([.hour, .minute, .second], from: startTime)
        let hmsEnd   = cal.dateComponents([.hour, .minute, .second], from: endTime)
        let dayStart = cal.startOfDay(for: day)
        let newStart = cal.date(bySettingHour: hmsStart.hour!, minute: hmsStart.minute!, second: hmsStart.second!, of: dayStart)!
        let newEnd   = cal.date(bySettingHour: hmsEnd.hour!, minute: hmsEnd.minute!, second: hmsEnd.second!, of: dayStart)!
        
        return Training(
            id: self.id,
            name: name,
            startTime: newStart,
            endTime: newEnd,
            notes: notes,
            reminderMinutes: self.reminderMinutes,
            notificationID: self.notificationID,
            calendarEventID: self.calendarEventID
        )
    }
    
    private func getPayload() -> TrainingPayload? {
        let marker = "#TRAINING#"
        guard var notes = self.notes, notes.starts(with: marker) else { return nil }
        
        notes.removeFirst(marker.count)
        
        guard let data = notes.data(using: .utf8),
              let payload = try? JSONDecoder().decode(TrainingPayload.self, from: data)
        else { return nil }
        return payload
    }

    public func exercises(using ctx: ModelContext) -> [ExerciseItem: Double] {
        if let payload = getPayload() {
            return parseExercises(from: payload.exercises, using: ctx)
        } else if var legacyNotes = self.notes {
            let marker = "#TRAINING#"
            if legacyNotes.starts(with: marker) {
                legacyNotes.removeFirst(marker.count)
            }
            return parseExercises(from: legacyNotes, using: ctx)
        }
        return [:]
    }

    public func detailedLog(using ctx: ModelContext) -> DetailedTrainingLog? {
        return getPayload()?.detailedLog
    }
    
    public func updateNotes(exercises: [ExerciseItem: Double], detailedLog: DetailedTrainingLog?) {
        let exerciseString = exercises
            .map { (exercise, duration) in "\(exercise.id)=\(duration)" }
            .joined(separator: "|")
        
        let payload = TrainingPayload(exercises: exerciseString, detailedLog: detailedLog)
        
        if let data = try? JSONEncoder().encode(payload),
           let jsonString = String(data: data, encoding: .utf8) {
            self.notes = "#TRAINING#" + jsonString
        }
    }

    private func parseExercises(from exerciseString: String, using ctx: ModelContext) -> [ExerciseItem: Double] {
        let exercisesFromNotes = exerciseString.split(separator: "|").compactMap { part -> (ExerciseItem, Double)? in
            let components = part.split(separator: "=", maxSplits: 1).map { String($0) }
            guard components.count == 2 else { return nil }
            guard let exerciseID = Int(components[0]), let duration = Double(components[1]) else { return nil }
            
            var descriptor = FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.id == exerciseID })
            descriptor.fetchLimit = 1
            guard let item = try? ctx.fetch(descriptor).first else { return nil }
            return (item, duration)
        }.reduce(into: [:]) { $0[$1.0] = $1.1 }

        return exercisesFromNotes
    }
}
