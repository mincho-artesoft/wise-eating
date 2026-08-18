import SwiftUI
import EventKitUI
import EventKit

public struct TwoWayPinnedSingleDayMultiCalendarWrapper: UIViewControllerRepresentable {
    
    // MARK: - Bindings & Properties
    @Binding var fromDate: Date
    @Binding var events: [EventDescriptor]
    @Binding var searchText: String
    
    // --- ПРОМЯНА: Добавено е property за профила ---
    let profile: Profile
    let usesHealthKit: Bool
    
    var goalProgressProvider: ((Date) -> Double?)?
        
    let eventStore: EKEventStore
        
    // MARK: - Callbacks
    public var onDayLabelTap: ((Date) -> Void)?
    public var onEventTap: ((EventDescriptor) -> Void)?
    public var onEventDeleted: ((EventDescriptor) -> Void)?
    public var onEventDuplicated: ((EventDescriptor) -> Void)?
    public var onEmptyLongPress: ((Date, EKCalendar?) -> Void)?
    public var onEventDragEnded: ((EventDescriptor, Date, Bool) -> Void)?
    public var onEventDragResizeEnded: ((EventDescriptor, Date) -> Void)?
    public var onAddNewEvent: (() -> Void)?
    public var onCalendarsSelectionChanged: (() -> Void)?
    
    // +++ НАЧАЛО НА ПРОМЯНАТА: Добавяме новия callback +++
    public var onNodesButtonTapped: (() -> Void)?
    public var onSystemEventPresentationChanged: ((Bool) -> Void)?
    // +++ КРАЙ НА ПРОМЯНАТА +++
    
    // MARK: - UIViewControllerRepresentable Lifecycle
    
    public func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        
        let container = TwoWayPinnedSingleDayMultiCalendarContainerView(
            profile: self.profile,
            usesHealthKit: usesHealthKit
        )
        
        // --- НАЧАЛО НА ПРОМЯНАТА (1/5): Задаваме референция и callback ---
        context.coordinator.containerView = container
        
        // Задаваме първоначалната стойност на филтъра от координатора
        container.currentFilter = context.coordinator.currentFilter

        // Уведомяваме координатора, когато потребителят смени филтъра
        container.onFilterChanged = { newFilter in
            context.coordinator.filterDidChange(to: newFilter)
        }
        // --- КРАЙ НА ПРОМЯНАТА (1/5) ---
        
        // +++ НАЧАЛО НА ПРОМЯНАТА: Свързваме callback-а на контейнера с този на wrapper-а +++
        container.onNodesButtonTapped = self.onNodesButtonTapped
        // +++ КРАЙ НА ПРОМЯНАТА +++
        
        container.goalProgressProvider = self.goalProgressProvider
        
        let (_, regular) = splitAllDay(events)
        container.weekView.regularLayoutAttributes  = regular.map { EventLayoutAttributes($0) }
        
        container.fromDate = fromDate
        
        container.onRangeChange = { newFrom, newTo in
            fromDate = newFrom
            context.coordinator.reloadCurrentRange()
        }
        
        container.onEventTap = { descriptor in
            if let multi = descriptor as? EKMultiDayWrapper {
                context.coordinator.presentSystemDetails(multi.ekEvent, in: vc)
            }
        }

        container.onEventMenuPresentationChanged = { isPresented in
            self.onSystemEventPresentationChanged?(isPresented)
        }
        
        container.onEmptyLongPress = { date, calendar in
            context.coordinator.createNewEventAndPresent(date: date, in: vc, preselectedCalendar: calendar)
        }
        
        container.onEventDragEnded = { descriptor, newDate, isAllDay in
            context.coordinator.handleEventDragOrResize(
                descriptor: descriptor,
                newDate: newDate,
                isResize: false,
                isAllDay: isAllDay
            )
        }
        
        container.onEventDragResizeEnded = { descriptor, newDate in
            context.coordinator.handleEventDragOrResize(
                descriptor: descriptor,
                newDate: newDate,
                isResize: true,
                isAllDay: false
            )
        }
        
        container.onEventDeleted = { descriptor in
            context.coordinator.reloadCurrentRange()
        }
        
        container.onEventDuplicated = { descriptor in
            context.coordinator.reloadCurrentRange()
        }
        
        container.onAddNewEvent = {
            context.coordinator.createNewEventAndPresent(date: Date(), in: vc)
        }
        
        // Този callback остава, за да може да презареждаме при смяна на видимостта на календарите
        container.onCalendarsSelectionChanged = {
            context.coordinator.reloadCurrentRange()
        }
        
        vc.view.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: vc.view.topAnchor),
            container.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
        ])
        
        return vc
    }
    
    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let container = uiViewController.view.subviews
                .first(where: { $0 is TwoWayPinnedSingleDayMultiCalendarContainerView })
                as? TwoWayPinnedSingleDayMultiCalendarContainerView else {
            return
        }

        context.coordinator.parent = self
        if context.coordinator.lastAppliedSearchText != searchText {
            context.coordinator.lastAppliedSearchText = searchText
            let coordinator = context.coordinator
            DispatchQueue.main.async {
                coordinator.reloadCurrentRange()
            }
        }
        
        // --- НАЧАЛО НА ПРОМЯНАТА (2/5): Синхронизираме състоянието ---
        // Уверяваме се, че UI-то на контейнера винаги отразява състоянието от координатора.
        if container.currentFilter != context.coordinator.currentFilter {
            container.currentFilter = context.coordinator.currentFilter
        }
        // --- КРАЙ НА ПРОМЯНАТА (2/5) ---
        
        container.updateProfile(self.profile, usesHealthKit: usesHealthKit)
        container.goalProgressProvider = self.goalProgressProvider
        container.fromDate = fromDate
        
        let (_, regular) = splitAllDay(events)
        container.weekView.regularLayoutAttributes  = regular.map { EventLayoutAttributes($0) }
        
        container.setNeedsLayout()
        container.layoutIfNeeded()
    }
    
    // MARK: - Coordinator
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    public class Coordinator: NSObject, @preconcurrency EKEventEditViewDelegate, @preconcurrency EKEventViewDelegate {
        var parent: TwoWayPinnedSingleDayMultiCalendarWrapper
        weak var containerView: TwoWayPinnedSingleDayMultiCalendarContainerView?
        var lastAppliedSearchText: String
        
        // --- НАЧАЛО НА ПРОМЯНАТА (3/5): Координаторът управлява състоянието ---
        var currentFilter: CalendarFilterType = .all
        // --- КРАЙ НА ПРОМЯНАТА (3/5) ---

        init(_ parent: TwoWayPinnedSingleDayMultiCalendarWrapper) {
            self.parent = parent
            self.lastAppliedSearchText = parent.searchText
            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleMealTimeChange),
                name: .mealTimeDidChange,
                object: nil
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(triggerReload),
                name: .forceCalendarReload,
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self, name: .mealTimeDidChange, object: nil)
            NotificationCenter.default.removeObserver(self, name: .forceCalendarReload, object: nil)
        }
        
        @objc private func triggerReload() {
            print("🗓️ Coordinator received forceCalendarReload notification. Reloading calendar range.")
            self.reloadCurrentRange()
        }
        
        @objc private func handleMealTimeChange() {
            print("🗓️ Coordinator received mealTimeDidChange. Reloading calendar range.")
            self.reloadCurrentRange()
        }
        
        public func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            controller.dismiss(animated: true) { [weak self] in
                Task { @MainActor in
                    self?.reloadCurrentRange()
                    self?.parent.onSystemEventPresentationChanged?(false)
                }
            }
        }
        
        public func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            // --- НАЧАЛО НА ПРОМЯНАТА: Разграничаваме изпращането на нотификации ---
            if action == .saved, let savedEvent = controller.event {
                let mealTemplateNames = Set(parent.profile.meals.map { $0.name })
                let trainingTemplateNames = Set(parent.profile.trainings.map { $0.name })

                let payload = EditNutritionPayload(
                    calendarID: savedEvent.calendar.calendarIdentifier,
                    date: savedEvent.startDate,
                    mealName: savedEvent.title ?? ""
                )

                if isTrainingEvent(savedEvent, mealTemplates: mealTemplateNames, trainingTemplates: trainingTemplateNames) {
                    NotificationCenter.default.post(name: .newTrainingCreated, object: payload)
                } else if isMealEvent(savedEvent, mealTemplates: mealTemplateNames, trainingTemplates: trainingTemplateNames) {
                    NotificationCenter.default.post(name: .newMealCreated, object: payload)
                }
            }
            // --- КРАЙ НА ПРОМЯНАТА ---

            controller.dismiss(animated: true) { [weak self] in
                Task { @MainActor in
                    self?.reloadCurrentRange()
                    self?.parent.onSystemEventPresentationChanged?(false)
                }
            }
        }
        
        // --- НАЧАЛО НА ПРОМЯНАТА (4/5): Нов метод за управление на филтъра ---
        func filterDidChange(to newFilter: CalendarFilterType) {
            if self.currentFilter != newFilter {
                self.currentFilter = newFilter
                self.reloadCurrentRange()
            }
        }
        // --- КРАЙ НА ПРОМЯНАТА (4/5) ---
        
        private func isMealEvent(_ event: EKEvent, mealTemplates: Set<String>, trainingTemplates: Set<String>) -> Bool {
            if self.isTrainingEvent(event, mealTemplates: mealTemplates, trainingTemplates: trainingTemplates) { return false }
            if PracticeCalendarEvent.isPractice(event) { return false }
            let title = event.title ?? ""
            if mealTemplates.contains(title) { return true }
            if let notes = event.notes, let decoded = OptimizedInvisibleCoder.decode(from: notes) {
                if decoded.trimmingCharacters(in: .whitespaces).starts(with: "{") { return false }
                return true
            }
            return false
        }
        
        private func isTrainingEvent(_ event: EKEvent, mealTemplates: Set<String>, trainingTemplates: Set<String>) -> Bool {
            let title = event.title ?? ""
            if let notes = event.notes, let decoded = OptimizedInvisibleCoder.decode(from: notes) {
                if decoded.starts(with: "#TRAINING#") { return true }
            }
            if trainingTemplates.contains(title) { return true }
            if mealTemplates.contains(title) { return false }
            return false
        }

        private func isPracticeEvent(_ event: EKEvent) -> Bool {
            PracticeCalendarEvent.isPractice(event)
        }
        
        public func reloadCurrentRange(debug: Bool = false) {
            // --- НАЧАЛО НА ПРОМЯНАТА (5/5): Четем филтъра от координатора ---
            let filter = self.currentFilter
            // --- КРАЙ НА ПРОМЯНАТА (5/5) ---
            
            let cal = Calendar.current
            let fromOnly = cal.startOfDay(for: parent.fromDate)
            
            guard let actualEnd = cal.date(byAdding: .day, value: 1, to: fromOnly) else {
                parent.events = []
                return
            }
            
            let visibleIDs = CalendarViewModel.shared.visibleCalendarIDs
            let allowedCalendars = CalendarViewModel.shared.allCalendars.filter {
                visibleIDs.contains($0.calendarIdentifier)
            }
            
            let predicate = parent.eventStore.predicateForEvents(
                withStart: fromOnly,
                end: actualEnd,
                calendars: allowedCalendars.isEmpty ? nil : allowedCalendars
            )
            
            let found = parent.eventStore.events(matching: predicate)
            
            let mealTemplateNames = Set(parent.profile.meals.map { $0.name })
            let trainingTemplateNames = Set(parent.profile.trainings.map { $0.name })

            let categoryFilteredEvents = found.filter { event in
                if filter == .all {
                    if let notes = event.notes, let decoded = OptimizedInvisibleCoder.decode(from: notes), decoded.trimmingCharacters(in: .whitespaces).starts(with: "{") {
                        return false
                    }
                    return true
                }
                
                switch filter {
                case .meal:
                    return self.isMealEvent(event, mealTemplates: mealTemplateNames, trainingTemplates: trainingTemplateNames)
                case .training:
                    return self.isTrainingEvent(event, mealTemplates: mealTemplateNames, trainingTemplates: trainingTemplateNames)
                case .practice:
                    return self.isPracticeEvent(event)
                default:
                    return true
                }
            }

            let query = parent.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let filteredEvents = categoryFilteredEvents.filter { event in
                guard !query.isEmpty else { return true }
                return (event.title ?? "").localizedCaseInsensitiveContains(query)
                    || (event.location ?? "").localizedCaseInsensitiveContains(query)
                    || event.calendar.title.localizedCaseInsensitiveContains(query)
            }
            
            var descriptors: [EventDescriptor] = []
            
            for ekEvent in filteredEvents {
                let startDay = cal.startOfDay(for: ekEvent.startDate)
                let endDay   = cal.startOfDay(for: ekEvent.endDate ?? ekEvent.startDate)
                
                if startDay != endDay {
                    let parts = splitEventByDays(ekEvent,
                                                 startRange: fromOnly,
                                                 endRange: actualEnd)
                    descriptors.append(contentsOf: parts)
                } else {
                    descriptors.append(EKMultiDayWrapper(realEvent: ekEvent))
                }
            }
            
            parent.events = descriptors
        }

        private func splitEventByDays(_ ekEvent: EKEvent, startRange: Date, endRange: Date) -> [EKMultiDayWrapper] {
            var results: [EKMultiDayWrapper] = []
            let cal = Calendar.current
            let realStart = max(ekEvent.startDate, startRange)
            let realEnd   = min(ekEvent.endDate ?? endRange, endRange)
            
            if realStart >= realEnd { return results }
            
            var currentStart = realStart
            while currentStart < realEnd {
                guard let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: currentStart) else { break }
                let pieceEnd = min(endOfDay, realEnd)
                let partial = EKMultiDayWrapper(realEvent: ekEvent, partialStart: currentStart, partialEnd: pieceEnd)
                results.append(partial)
                
                guard let nextDay = cal.date(byAdding: .day, value: 1, to: currentStart),
                      let morning = cal.date(bySettingHour: 0, minute: 0, second: 0, of: nextDay) else { break }
                currentStart = morning
            }
            return results
        }
        
        public func presentSystemEditor(_ ekEvent: EKEvent, in parentVC: UIViewController) {
            let editVC = EKEventEditViewController()
            editVC.eventStore = parent.eventStore
            editVC.event = ekEvent
            editVC.editViewDelegate = self
            parent.onSystemEventPresentationChanged?(true)
            parentVC.present(editVC, animated: true)
        }
        
        private func _createNewMeal(date: Date, in parentVC: UIViewController, preselectedCalendar: EKCalendar? = nil) {
            let newEvent = EKEvent(eventStore: parent.eventStore)
            newEvent.title = NSLocalizedString("New Meal", comment: "")
            newEvent.startDate = date
            newEvent.endDate = date.addingTimeInterval(3600)
            newEvent.notes = OptimizedInvisibleCoder.encode(from: "")
            newEvent.calendar = preselectedCalendar ?? parent.eventStore.defaultCalendarForNewEvents
            presentSystemEditor(newEvent, in: parentVC)
        }

        private func _createNewTraining(date: Date, in parentVC: UIViewController, preselectedCalendar: EKCalendar? = nil) {
            let newEvent = EKEvent(eventStore: parent.eventStore)
            newEvent.title = NSLocalizedString("New Training", comment: "")
            newEvent.startDate = date
            newEvent.endDate = date.addingTimeInterval(3600)
            newEvent.notes = OptimizedInvisibleCoder.encode(from: "#TRAINING#")
            newEvent.calendar = preselectedCalendar ?? parent.eventStore.defaultCalendarForNewEvents
            presentSystemEditor(newEvent, in: parentVC)
        }
        
        public func createNewEventAndPresent(date: Date, in parentVC: UIViewController, preselectedCalendar: EKCalendar? = nil) {
            switch self.currentFilter {
            case .all:
                let alert = UIAlertController(
                    title: NSLocalizedString("Create New Event", comment: "Alert title for creating a new event"),
                    message: NSLocalizedString("What would you like to create?", comment: "Alert message for event type selection"),
                    preferredStyle: .actionSheet
                )

                alert.addAction(UIAlertAction(title: NSLocalizedString("New Meal", comment: "Action to create a new meal"), style: .default) { [weak self] _ in
                    self?._createNewMeal(date: date, in: parentVC, preselectedCalendar: preselectedCalendar)
                })

                alert.addAction(UIAlertAction(title: NSLocalizedString("New Training", comment: "Action to create a new training"), style: .default) { [weak self] _ in
                    self?._createNewTraining(date: date, in: parentVC, preselectedCalendar: preselectedCalendar)
                })

                alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel action"), style: .cancel))

                if let popoverController = alert.popoverPresentationController {
                    popoverController.sourceView = parentVC.view
                    popoverController.sourceRect = CGRect(x: parentVC.view.bounds.midX, y: parentVC.view.bounds.midY, width: 0, height: 0)
                    popoverController.permittedArrowDirections = []
                }
                parentVC.present(alert, animated: true)

            case .meal:
                _createNewMeal(date: date, in: parentVC, preselectedCalendar: preselectedCalendar)

            case .training:
                _createNewTraining(date: date, in: parentVC, preselectedCalendar: preselectedCalendar)

            case .practice:
                let alert = UIAlertController(
                    title: NSLocalizedString("Practices", comment: "Practice calendar event title"),
                    message: NSLocalizedString(
                        "Practice events are added automatically when you use a practice.",
                        comment: "Practice calendar event guidance"
                    ),
                    preferredStyle: .alert
                )
                alert.addAction(
                    UIAlertAction(
                        title: NSLocalizedString("OK", comment: "Confirmation action"),
                        style: .default
                    )
                )
                parentVC.present(alert, animated: true)
            }
        }
        
        public func handleEventDragOrResize(descriptor: EventDescriptor, newDate: Date, isResize: Bool, isAllDay: Bool) {
            if let multi = descriptor as? EKMultiDayWrapper {
                let ev = multi.realEvent
                guard !PracticeCalendarEvent.isPractice(ev) else { return }
                if ev.hasRecurrenceRules {
                    askUserForRecurring(event: ev, newDate: newDate, isResize: isResize)
                } else {
                    if !isResize {
                        applyDragChanges(ev, newStartDate: newDate, span: .thisEvent, isAllDay: isAllDay)
                    } else {
                        applyResizeChanges(ev, descriptor: multi, forcedNewDate: newDate, span: .thisEvent)
                    }
                }
            }
        }
        
        public func askUserForRecurring(event: EKEvent, newDate: Date, isResize: Bool) {
             let alert = UIAlertController(
                title: NSLocalizedString("Recurring Event", comment: ""),
                message: NSLocalizedString("This event is part of a series. Update which events?", comment: ""),
                preferredStyle: .actionSheet
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("This Event Only", comment: ""), style: .default, handler: { [weak self] _ in
                guard let self = self else { return }
                if !isResize {
                    self.applyDragChanges(event, newStartDate: newDate, span: .thisEvent, isAllDay: false)
                } else {
                    self.applyResizeChanges(event, descriptor: nil, forcedNewDate: newDate, span: .thisEvent)
                }
            }))
            alert.addAction(UIAlertAction(title: NSLocalizedString("All Future Events", comment: ""), style: .default, handler: { [weak self] _ in
                guard let self = self else { return }
                if !isResize {
                    self.applyDragChanges(event, newStartDate: newDate, span: .futureEvents, isAllDay: false)
                } else {
                    self.applyResizeChanges(event, descriptor: nil, forcedNewDate: newDate, span: .futureEvents)
                }
            }))
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: { [weak self] _ in
                self?.reloadCurrentRange()
            }))
            
            if let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }),
               let root = window.rootViewController {
                alert.popoverPresentationController?.sourceView = root.view
                root.present(alert, animated: true)
            }
        }
        
        public func applyDragChanges(_ event: EKEvent, newStartDate: Date, span: EKSpan, isAllDay: Bool) {
             guard let oldStart = event.startDate, let oldEnd = event.endDate else { return }
            if isAllDay {
                event.startDate = newStartDate
                event.endDate   = newStartDate.addingTimeInterval(3600)
            } else {
                let duration = oldEnd.timeIntervalSince(oldStart)
                event.startDate = newStartDate
                event.endDate   = newStartDate.addingTimeInterval(duration)
            }
            do {
                try parent.eventStore.save(event, span: span)
            } catch {
                print("Error saving event: \(error)")
            }
            reloadCurrentRange()
        }
        
        public func applyResizeChanges(_ event: EKEvent, descriptor: EventDescriptor?, forcedNewDate: Date, span: EKSpan) {
             if let multi = descriptor as? EKMultiDayWrapper {
                let originalInterval = multi.dateInterval
                let distanceToStart = forcedNewDate.timeIntervalSince(originalInterval.start)
                let distanceToEnd   = originalInterval.end.timeIntervalSince(forcedNewDate)
                if distanceToStart < distanceToEnd {
                    if forcedNewDate < event.endDate {
                        event.startDate = forcedNewDate
                    }
                } else {
                    if forcedNewDate > event.startDate {
                        event.endDate = forcedNewDate
                    }
                }
            }
            do {
                try parent.eventStore.save(event, span: span)
            } catch {
                print("Error saving event: \(error)")
            }
            reloadCurrentRange()
        }
        
        public func presentSystemDetails(_ ekEvent: EKEvent, in parentVC: UIViewController) {
            let eventVC = EKEventViewController()
            eventVC.event = ekEvent
            eventVC.delegate = self
            eventVC.allowsEditing = true
            eventVC.allowsCalendarPreview = true
            let navVC = UINavigationController(rootViewController: eventVC)
            parent.onSystemEventPresentationChanged?(true)
            parentVC.present(navVC, animated: true)
        }
    }
    
    // MARK: - Private Helpers
    
    private func splitAllDay(_ evts: [EventDescriptor]) -> ([EventDescriptor], [EventDescriptor]) {
        var allDay: [EventDescriptor] = []
        var regular: [EventDescriptor] = []
        for e in evts {
            e.isAllDay ? allDay.append(e) : regular.append(e)
        }
        return (allDay, regular)
    }
}
