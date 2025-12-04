import SwiftUI
import EventKit
import SwiftData

@Model
public final class Meal: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var name: String // e.g., "Breakfast"
    public var startTime: Date
    public var endTime: Date
    public var notes: String? = nil
    
    // NEW PROPERTY: To store the creative name from the AI.
    public var descriptiveAIName: String? = nil
    
    public var calendarEventID: String? = nil
    
    // --- Reminder Settings ---
    public var reminderMinutes: Int? = nil
    public var notificationID: String? = nil

    // --- Initializers ---
    public init(id: UUID = .init(), name: String, startTime: Date, endTime: Date, notes: String? = nil, descriptiveAIName: String? = nil, reminderMinutes: Int? = nil, notificationID: String? = nil, calendarEventID: String? = nil) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
        self.descriptiveAIName = descriptiveAIName // Handle new property
        self.reminderMinutes = reminderMinutes
        self.notificationID = notificationID
        self.calendarEventID = calendarEventID
    }

    public convenience init(from other: Meal) {
        self.init(
            id: other.id,
            name: other.name,
            startTime: other.startTime,
            endTime: other.endTime,
            notes: other.notes,
            descriptiveAIName: other.descriptiveAIName, // Handle new property
            reminderMinutes: other.reminderMinutes,
            notificationID: other.notificationID,
            calendarEventID: other.calendarEventID
        )
    }
    
    public convenience init(event ev: EKEvent) {
        let rawNotes = ev.notes ?? ""
        let invisAlphabet: Set<UnicodeScalar> = Set(["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{2061}", "\u{2062}", "\u{2063}", "\u{2064}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}"].flatMap { $0.unicodeScalars })
        let hiddenScalars = rawNotes.unicodeScalars.filter { invisAlphabet.contains($0) }
        var decodedLines: [String] = []
        if let decoded = OptimizedInvisibleCoder.decode(from: String(String.UnicodeScalarView(hiddenScalars))) {
            decodedLines = decoded.split(separator: "|").compactMap { part -> String? in
                let p = part.split(separator: "=", maxSplits: 1)
                guard p.count == 2, let g = Double(p[1]) else { return nil }
                return "\(p[0]) – \(g.clean) g"
            }
        }
        
        // Note: We can't get the descriptiveAIName from a calendar event, so it will be nil, which is correct.
        self.init(
            name: ev.title ?? "Meal",
            startTime: ev.startDate,
            endTime: ev.endDate,
            notes: decodedLines.joined(separator: "\n"),
            calendarEventID: ev.eventIdentifier
        )
    }
    
    // --- Codable & Equatable ---
    public static func == (lhs: Meal, rhs: Meal) -> Bool {
        lhs.id == rhs.id &&
        lhs.startTime == rhs.startTime &&
        lhs.endTime   == rhs.endTime
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, startTime, endTime, reminderMinutes, notificationID, calendarEventID, descriptiveAIName
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        reminderMinutes = try container.decodeIfPresent(Int.self, forKey: .reminderMinutes)
        notificationID = try container.decodeIfPresent(String.self, forKey: .notificationID)
        calendarEventID = try container.decodeIfPresent(String.self, forKey: .calendarEventID)
        descriptiveAIName = try container.decodeIfPresent(String.self, forKey: .descriptiveAIName) // Handle new property
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encodeIfPresent(reminderMinutes, forKey: .reminderMinutes)
        try container.encodeIfPresent(notificationID, forKey: .notificationID)
        try container.encodeIfPresent(calendarEventID, forKey: .calendarEventID)
        try container.encodeIfPresent(descriptiveAIName, forKey: .descriptiveAIName) // Handle new property
    }

    public static func defaultMeals() -> [Meal] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let breakfastStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: startOfDay)!
        let breakfastEnd   = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: startOfDay)!
        let lunchStart     = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: startOfDay)!
        let lunchEnd       = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: startOfDay)!
        let dinnerStart    = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: startOfDay)!
        let dinnerEnd      = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: startOfDay)!
        return [
            Meal(name: "Breakfast", startTime: breakfastStart, endTime: breakfastEnd),
            Meal(name: "Lunch", startTime: lunchStart, endTime: lunchEnd),
            Meal(name: "Dinner", startTime: dinnerStart, endTime: dinnerEnd)
        ]
    }

    public func detached(for day: Date) -> Meal {
        let cal = Calendar.current
        let hmsStart = cal.dateComponents([.hour, .minute, .second], from: startTime)
        let hmsEnd   = cal.dateComponents([.hour, .minute, .second], from: endTime)
        let dayStart = cal.startOfDay(for: day)
        let newStart = cal.date(bySettingHour: hmsStart.hour!, minute: hmsStart.minute!, second: hmsStart.second!, of: dayStart)!
        let newEnd   = cal.date(bySettingHour: hmsEnd.hour!, minute: hmsEnd.minute!, second: hmsEnd.second!, of: dayStart)!
        
        let detachedMeal = Meal(
            id: self.id,
            name: name,
            startTime: newStart,
            endTime: newEnd,
            notes: notes,
            descriptiveAIName: self.descriptiveAIName, // Handle new property
            reminderMinutes: self.reminderMinutes,
            notificationID: self.notificationID,
            calendarEventID: self.calendarEventID
        )
        return detachedMeal
    }

    // Reads only from notes
    public func foods(using ctx: ModelContext) -> [FoodItem: Double] {
        guard let notes = self.notes, !notes.isEmpty else { return [:] }
        
        let foodsFromNotes = notes.split(separator: "\n").compactMap { line -> (FoodItem, Double)? in
            let parts = line.split(separator: "–", maxSplits: 1).map { String($0) }
            guard parts.count == 2 else { return nil }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let gramsString = parts[1].replacingOccurrences(of: "g", with: "").trimmingCharacters(in: .whitespaces)
            guard let grams = GlobalState.double(from: gramsString) else { return nil }
            var descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.name == name })
            descriptor.fetchLimit = 1
            guard let item = try? ctx.fetch(descriptor).first else { return nil }
            return (item, grams)
        }.reduce(into: [:]) { $0[$1.0] = $1.1 }

        return foodsFromNotes
    }
}
