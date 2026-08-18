import ActivityKit
import SwiftUI
import WidgetKit

@main
struct AyuraLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextEventLiveActivityWidget()
    }
}

struct NextEventLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NextEventActivityAttributes.self) { context in
            TimelineView(AdaptiveCountdownSchedule(events: context.state.events)) { timeline in
                NextEventLockScreenView(
                    event: nextEvent(in: context.state.events, at: timeline.date),
                    date: timeline.date
                )
            }
            .activityBackgroundTint(Color(red: 0.06, green: 0.08, blue: 0.07))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TimelineView(AdaptiveCountdownSchedule(events: context.state.events)) { timeline in
                        EventSymbol(
                            event: nextEvent(in: context.state.events, at: timeline.date),
                            size: 24
                        )
                        .padding(.leading, 8)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    TimelineView(AdaptiveCountdownSchedule(events: context.state.events)) { timeline in
                        let event = nextEvent(in: context.state.events, at: timeline.date)
                        VStack(spacing: 2) {
                            Text(event?.kind.label ?? "Live schedule")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.62))
                            Text(event?.title ?? "Waiting for next activity")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 4)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    TimelineView(AdaptiveCountdownSchedule(events: context.state.events)) { timeline in
                        let event = nextEvent(in: context.state.events, at: timeline.date)

                        HStack(spacing: 6) {
                            if let event {
                                RemainingTimeText(event: event, date: timeline.date)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(event.kind.color)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .layoutPriority(1)

                                Spacer(minLength: 12)

                                Image(systemName: "clock")
                                Text(event.startDate, style: .time)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .layoutPriority(1)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                TimelineView(AdaptiveCountdownSchedule(events: context.state.events)) { timeline in
                    EventSymbol(
                        event: nextEvent(in: context.state.events, at: timeline.date),
                        size: 15
                    )
                }
            } compactTrailing: {
                TimelineView(AdaptiveCountdownSchedule(events: context.state.events)) { timeline in
                    if let event = nextEvent(in: context.state.events, at: timeline.date) {
                        RemainingTimeText(event: event, date: timeline.date)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(event.kind.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Image(systemName: "clock")
                    }
                }
            } minimal: {
                TimelineView(AdaptiveCountdownSchedule(events: context.state.events)) { timeline in
                    EventSymbol(
                        event: nextEvent(in: context.state.events, at: timeline.date),
                        size: 13
                    )
                }
            }
            .keylineTint(.orange)
            .contentMargins(.horizontal, 16, for: .expanded)
        }
    }

    private func nextEvent(in events: [NextEventItem], at date: Date) -> NextEventItem? {
        events.first { $0.startDate > date }
    }
}

private struct AdaptiveCountdownSchedule: TimelineSchedule {
    let events: [NextEventItem]

    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(
            events: events.sorted { $0.startDate < $1.startDate },
            nextDate: startDate
        )
    }

    struct Entries: Sequence, IteratorProtocol {
        let events: [NextEventItem]
        var nextDate: Date

        mutating func next() -> Date? {
            let date = nextDate
            let upcomingEvent = events.first { $0.startDate > date }

            if let upcomingEvent {
                let remaining = upcomingEvent.startDate.timeIntervalSince(date)

                if remaining <= 120 {
                    nextDate = date.addingTimeInterval(1)
                } else {
                    // Keep the normal 30-second cadence, but always render once
                    // exactly when the countdown enters its final two minutes.
                    nextDate = date.addingTimeInterval(Swift.min(30, remaining - 120))
                }
            } else {
                nextDate = date.addingTimeInterval(30)
            }

            return date
        }
    }
}

private struct NextEventLockScreenView: View {
    let event: NextEventItem?
    let date: Date

    var body: some View {
        HStack(spacing: 14) {
            EventSymbol(event: event, size: 25)
                .frame(width: 42, height: 42)
                .background((event?.kind.color ?? .secondary).opacity(0.18), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(event?.kind.label ?? "Live schedule")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))

                Text(event?.title ?? "Waiting for next activity")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(1)

                HStack(spacing: 8) {
                    if let event {
                        RemainingTimeText(event: event, date: date)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(event.kind.color)
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Image(systemName: "clock")
                            .foregroundStyle(.white.opacity(0.62))
                        Text(event.startDate, style: .time)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                    } else {
                        Spacer()
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct RemainingTimeText: View {
    let event: NextEventItem
    let date: Date

    @ViewBuilder
    var body: some View {
        let remaining = event.startDate.timeIntervalSince(date)

        if remaining > 0, remaining <= 120 {
            Text(
                timerInterval: date...event.startDate,
                countsDown: true,
                showsHours: false
            )
        } else {
            Text(shortRemainingTime(until: event.startDate, from: date))
        }
    }
}

private func shortRemainingTime(until startDate: Date, from date: Date) -> String {
    let totalSeconds = max(0, Int(startDate.timeIntervalSince(date)))
    let days = totalSeconds / 86_400
    let hours = (totalSeconds % 86_400) / 3_600
    let minutes = (totalSeconds % 3_600) / 60

    if days > 0 {
        return "\(days)d \(hours)h"
    }
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    if minutes > 0 {
        return "\(minutes)m"
    }
    return "\(totalSeconds)s"
}

private struct EventSymbol: View {
    let event: NextEventItem?
    let size: CGFloat

    var body: some View {
        Image(systemName: event?.kind.symbolName ?? "clock")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(event?.kind.color ?? .orange)
    }
}

private extension NextEventItem.Kind {
    var label: String {
        switch self {
        case .meal: "Next meal"
        case .workout: "Next workout"
        case .practice: "Next practice"
        }
    }

    var symbolName: String {
        switch self {
        case .meal: "fork.knife"
        case .workout: "figure.yoga"
        case .practice: "figure.mind.and.body"
        }
    }

    var color: Color {
        switch self {
        case .meal: .orange
        case .workout: .mint
        case .practice: .purple
        }
    }
}
