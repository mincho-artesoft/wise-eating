import ActivityKit
import Combine
import EventKit
import Foundation

@MainActor
final class NextEventLiveActivityManager: ObservableObject {
    static let shared = NextEventLiveActivityManager()

    @Published private(set) var isRunning = false

    private let calendarViewModel = CalendarViewModel.shared
    private let horizonDays = 3
    private let maximumEventCount = 16

    private init() {
        refreshStatus()
    }

    func refreshStatus() {
        isRunning = Self.activeActivities.isEmpty == false
    }

    func toggle(for profile: Profile) async throws {
        refreshStatus()

        if isRunning {
            await stop()
        } else {
            try await start(for: profile)
        }
    }

    func start(for profile: Profile) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw NextEventLiveActivityError.disabledBySystem
        }

        let events = await upcomingEvents(for: profile)
        await endAllActivities()

        let attributes = NextEventActivityAttributes(
            profileID: profile.id.uuidString,
            profileName: profile.name
        )
        let state = NextEventActivityAttributes.ContentState(
            events: events,
            generatedAt: Date()
        )
        let content = ActivityContent(
            state: state,
            staleDate: events.first?.startDate,
            relevanceScore: events.isEmpty ? 0 : 100
        )

        _ = try Activity<NextEventActivityAttributes>.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        isRunning = true
    }

    func refreshIfRunning(for profile: Profile) async {
        let activities = Self.activeActivities
        guard activities.isEmpty == false else {
            refreshStatus()
            return
        }

        // Activity attributes cannot change. A Live Activity started for another
        // profile keeps following that profile until the user stops it.
        guard activities.contains(where: { $0.attributes.profileID == profile.id.uuidString }) else {
            refreshStatus()
            return
        }

        let events = await upcomingEvents(for: profile)
        let state = NextEventActivityAttributes.ContentState(
            events: events,
            generatedAt: Date()
        )
        let content = ActivityContent(
            state: state,
            staleDate: events.first?.startDate,
            relevanceScore: events.isEmpty ? 0 : 100
        )

        await Self.updateActivities(for: profile.id.uuidString, with: content)
        refreshStatus()
    }

    func stop() async {
        await endAllActivities()
        refreshStatus()
    }

    private func upcomingEvents(for profile: Profile) async -> [NextEventItem] {
        let now = Date()
        let calendar = Calendar.current
        var events: [NextEventItem] = []

        if let rangeEnd = calendar.date(byAdding: .year, value: 1, to: now) {
            let scheduledEvents = await calendarViewModel.fetchEvents(
                forProfile: profile,
                startDate: now,
                endDate: rangeEnd
            )
            let mealTemplateNames = Set(profile.meals.map(\.name))
            let trainingTemplateNames = Set(profile.trainings.map(\.name))

            for event in scheduledEvents where event.startDate > now {
                let title = event.title ?? "Scheduled activity"
                let decodedPayload = event.notes.flatMap(OptimizedInvisibleCoder.decode(from:))

                if let decodedPayload,
                   decodedPayload.trimmingCharacters(in: .whitespaces).starts(with: "{")
                    || decodedPayload.starts(with: PracticeCalendarEvent.marker) {
                    continue
                }

                let isWorkout = decodedPayload?.starts(with: "#TRAINING#") == true
                    || trainingTemplateNames.contains(title)
                let isMeal = mealTemplateNames.contains(title)
                    || (decodedPayload != nil && isWorkout == false)

                guard isWorkout || isMeal else { continue }
                let kind: NextEventItem.Kind = isWorkout ? .workout : .meal
                events.append(
                    NextEventItem(
                        id: "\(kind.rawValue)-\(event.eventIdentifier ?? title)-\(event.startDate.timeIntervalSince1970)",
                        kind: kind,
                        title: Self.compactTitle(title),
                        startDate: event.startDate,
                        endDate: event.endDate
                    )
                )
            }
        }

        if let practice = NotificationManager.shared.storedPracticeReminder(for: profile.id) {
            let time = calendar.dateComponents([.hour, .minute, .second], from: practice.lastStartedAt)
            if let firstOccurrence = calendar.nextDate(
                after: now,
                matching: time,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            ) {
                for dayOffset in 0..<horizonDays {
                    guard let startDate = calendar.date(
                        byAdding: .day,
                        value: dayOffset,
                        to: firstOccurrence
                    ) else {
                        continue
                    }
                    events.append(
                        NextEventItem(
                            id: "practice-\(profile.id.uuidString)-\(startDate.timeIntervalSince1970)",
                            kind: .practice,
                            title: Self.compactTitle(practice.title),
                            startDate: startDate,
                            endDate: nil
                        )
                    )
                }
            }
        }

        var seen = Set<String>()
        return events
            .sorted { $0.startDate < $1.startDate }
            .filter { seen.insert($0.id).inserted }
            .prefix(maximumEventCount)
            .map { $0 }
    }

    private func endAllActivities() async {
        let finalState = NextEventActivityAttributes.ContentState(
            events: [],
            generatedAt: Date()
        )
        let finalContent = ActivityContent(
            state: finalState,
            staleDate: nil,
            relevanceScore: 0
        )

        await Self.endActivities(with: finalContent)
    }

    nonisolated private static func updateActivities(
        for profileID: String,
        with content: ActivityContent<NextEventActivityAttributes.ContentState>
    ) async {
        for activity in Activity<NextEventActivityAttributes>.activities
        where activity.attributes.profileID == profileID {
            await activity.update(content)
        }
    }

    nonisolated private static func endActivities(
        with content: ActivityContent<NextEventActivityAttributes.ContentState>
    ) async {
        for activity in Activity<NextEventActivityAttributes>.activities {
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }

    private static var activeActivities: [Activity<NextEventActivityAttributes>] {
        Activity<NextEventActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    private static func compactTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Scheduled activity" : trimmed
        return String(fallback.prefix(48))
    }
}

private enum NextEventLiveActivityError: LocalizedError {
    case disabledBySystem

    var errorDescription: String? {
        switch self {
        case .disabledBySystem:
            return "Live Activities are disabled. Enable them in Settings > Apps > Ayurveda & Asana Yoga > Live Activities."
        }
    }
}
