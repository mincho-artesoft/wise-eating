import SwiftUI
import EventKitUI
import EventKit
import SwiftData

public struct ShoppingTwoWayPinnedSingleDayMultiCalendarWrapper: UIViewControllerRepresentable {
    
    // --- ПРОМЯНА 1: Премахваме @Environment. Ще го вземем от `context` по-долу. ---
    // @Environment(\.modelContext) private var modelContext
    
    // MARK: - Bindings & Properties
    @Binding var fromDate: Date
    @Binding var events: [EventDescriptor]
    
    let profile: Profile
    
    var goalProgressProvider: ((Date) -> Double?)?
    let eventStore: EKEventStore
        
    // MARK: - Callbacks
    public var onDayLabelTap: ((Date) -> Void)?
    public var onPresentShoppingList: ((EKEvent) -> Void)?
    public var onShowListsTap: (() -> Void)?
    public var onEventDeleted: ((EventDescriptor) -> Void)?
    public var onEventDuplicated: ((EventDescriptor) -> Void)?
    public var onEmptyLongPress: ((Date, EKCalendar?) -> Void)?
    public var onEventDragEnded: ((EventDescriptor, Date, Bool) -> Void)?
    public var onEventDragResizeEnded: ((EventDescriptor, Date) -> Void)?
    public var onAddNewEvent: (() -> Void)?
    public var onCalendarsSelectionChanged: (() -> Void)?
    
    // MARK: - UIViewControllerRepresentable Lifecycle
    
    public func makeUIViewController(context: Context) -> UIViewController {
        // --- ПРОМЯНА 2: Подаваме modelContext на координатора оттук. ---
        // Това е правилният момент, защото environment-ът е гарантирано наличен в `context`.
        context.coordinator.modelContext = context.environment.modelContext

        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        
        let container = ShoppingTwoWayPinnedSingleDayMultiCalendarContainerView(profile: profile)
        
        context.coordinator.containerView = container
        
        container.goalProgressProvider = self.goalProgressProvider
        
        let (_, regular) = splitAllDay(events)
        container.weekView.regularLayoutAttributes = regular.map { EventLayoutAttributes($0) }
        
        container.fromDate = fromDate
        
        container.onRangeChange = { newFrom, newTo in
            fromDate = newFrom
        }
        
        container.onEventTap = { descriptor in
            if let multi = descriptor as? EKMultiDayWrapper {
                self.onPresentShoppingList?(multi.realEvent)
            }
        }
        container.onEmptyLongPress = { date, calendar in
            context.coordinator.createNewEventAndPresent(date: date, in: vc, preselectedCalendar: calendar)
        }
        container.onEventDragEnded = { descriptor, newDate, isAllDay in
            context.coordinator.handleEventDragOrResize(descriptor: descriptor, newDate: newDate, isResize: false, isAllDay: isAllDay)
        }
        container.onEventDragResizeEnded = { descriptor, newDate in
            context.coordinator.handleEventDragOrResize(descriptor: descriptor, newDate: newDate, isResize: true, isAllDay: false)
        }
        container.onShowListsTap = onShowListsTap
        container.onEventDeleted = { descriptor in
            context.coordinator.handleEventDeletion(descriptor: descriptor)
        }
        container.onEventDuplicated = { _ in
            context.coordinator.reloadCurrentRange()
        }
        container.onAddNewEvent = {
            context.coordinator.createNewEventAndPresent(date: Date(), in: vc)
        }
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
                .first(where: { $0 is ShoppingTwoWayPinnedSingleDayMultiCalendarContainerView })
                as? ShoppingTwoWayPinnedSingleDayMultiCalendarContainerView else {
            return
        }
        
        container.goalProgressProvider = self.goalProgressProvider
        container.fromDate = fromDate
        
        let (_, regular) = splitAllDay(events)
        container.weekView.regularLayoutAttributes = regular.map { EventLayoutAttributes($0) }
        
        container.setNeedsLayout()
        container.layoutIfNeeded()
    }
    
    // MARK: - Coordinator
    
    public func makeCoordinator() -> Coordinator {
        // --- ПРОМЯНА 3: Създаваме координатора без modelContext. ---
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, @preconcurrency EKEventEditViewDelegate, @preconcurrency EKEventViewDelegate {
        var parent: ShoppingTwoWayPinnedSingleDayMultiCalendarWrapper
        
        // --- ПРОМЯНА 4: modelContext става optional var, за да може да се зададе по-късно. ---
        var modelContext: ModelContext?
        
        weak var containerView: ShoppingTwoWayPinnedSingleDayMultiCalendarContainerView?
        
        // --- ПРОМЯНА 5: Обновяваме инициализатора. ---
        init(_ parent: ShoppingTwoWayPinnedSingleDayMultiCalendarWrapper) {
            self.parent = parent
        }
        
        @MainActor
        public func handleEventDeletion(descriptor: EventDescriptor) {
            // --- ПРОМЯНА 6: Добавяме guard за безопасен достъп до modelContext. ---
            guard let modelContext = self.modelContext else {
                print("COORDINATOR: Грешка - ModelContext не е наличен при изтриване.")
                self.reloadCurrentRange()
                return
            }

            print("COORDINATOR: Обработка на изтриване на събитие...")

            guard let multi = descriptor as? EKMultiDayWrapper,
                  let eventIdentifier = multi.realEvent.eventIdentifier else {
                print("COORDINATOR: Не може да се вземе идентификатор от дескриптора. Само презареждам.")
                self.reloadCurrentRange()
                return
            }
            
            print("COORDINATOR: Събитието за изтриване има идентификатор: \(eventIdentifier)")

            let fetchDescriptor = FetchDescriptor<ShoppingListModel>(
                predicate: #Predicate { $0.calendarEventID == eventIdentifier }
            )

            do {
                let matchingLists = try modelContext.fetch(fetchDescriptor)
                
                if let listToDelete = matchingLists.first {
                    print("COORDINATOR: Намерен е съответстващ ShoppingListModel с име '\(listToDelete.name)'. Изтривам го.")
                    modelContext.delete(listToDelete)
                    
                    if modelContext.hasChanges {
                        try modelContext.save()
                        print("COORDINATOR: SwiftData контекстът е запазен.")
                    }
                    
                    print("COORDINATOR: Изпращане на нотификация .shoppingListDidChange.")
                    NotificationCenter.default.post(name: .shoppingListDidChange, object: nil)
                    
                } else {
                    print("COORDINATOR: Не е намерен съответстващ ShoppingListModel за това събитие.")
                }
            } catch {
                print("COORDINATOR: Грешка при търсене или изтриване на ShoppingListModel: \(error)")
            }

            print("COORDINATOR: Презареждане на календара.")
            self.reloadCurrentRange()
        }
        
        @MainActor public func reloadCurrentRange() {
            let cal = Calendar.current
            let fromOnly = cal.startOfDay(for: parent.fromDate)
            
            print("🛍️ [COORD-RELOAD] Зареждане за ден: \(fromOnly.formatted(date: .long, time: .omitted))")

            guard let actualEnd = cal.date(byAdding: .day, value: 1, to: fromOnly),
                  let fetchStart = cal.date(byAdding: .day, value: -1, to: fromOnly) else {
                updateUI(with: [])
                return
            }
            
            let shoppingCalendarID: String?
            if parent.profile.hasSeparateStorage {
                shoppingCalendarID = parent.profile.shoppingListCalendarID
            } else {
                shoppingCalendarID = UserDefaults.standard.string(forKey: CalendarViewModel.shared.sharedShoppingListCalendarIDKey)
            }

            var targetCalendar: EKCalendar? = nil
            if let id = shoppingCalendarID {
                targetCalendar = parent.eventStore.calendar(withIdentifier: id)
            }
            
            guard let calendarToFetch = targetCalendar else {
                print("🛍️ [COORD-RELOAD] ❗️ Няма календар за пазаруване.")
                updateUI(with: [])
                return
            }
            
            print("🛍️ [COORD-RELOAD] Извличане от календар: '\(calendarToFetch.title)'")
            
            let predicate = parent.eventStore.predicateForEvents(
                withStart: fetchStart,
                end: actualEnd,
                calendars: [calendarToFetch]
            )
            
            let found = parent.eventStore.events(matching: predicate)
            print("🛍️ [COORD-RELOAD] 🔍 Намерени са \(found.count) събития.")
            
            var descriptors: [EventDescriptor] = []

            for ekEvent in found {
                guard ekEvent.endDate > fromOnly && ekEvent.startDate < actualEnd else {
                    continue
                }

                let startDay = cal.startOfDay(for: ekEvent.startDate)
                let endDay   = cal.startOfDay(for: ekEvent.endDate ?? ekEvent.startDate)
                
                if startDay != endDay || ekEvent.isAllDay {
                    let parts = splitEventByDays(ekEvent,
                                                 startRange: fromOnly,
                                                 endRange: actualEnd)
                    descriptors.append(contentsOf: parts)
                } else {
                    descriptors.append(EKMultiDayWrapper(realEvent: ekEvent))
                }
            }
            
            print("🛍️ [COORD-RELOAD] ✅ Общо дескриптори за UI: \(descriptors.count)")
            updateUI(with: descriptors)
        }

        @MainActor private func updateUI(with descriptors: [EventDescriptor]) {
            parent.events = descriptors
            
            let (_, regular) = splitAllDay(descriptors)
            containerView?.weekView.regularLayoutAttributes = regular.map { EventLayoutAttributes($0) }
            
            containerView?.setNeedsLayout()
            containerView?.layoutIfNeeded()
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
        
        private func splitAllDay(_ evts: [EventDescriptor]) -> ([EventDescriptor], [EventDescriptor]) {
            var allDay: [EventDescriptor] = []
            var regular: [EventDescriptor] = []
            for e in evts {
                e.isAllDay ? allDay.append(e) : regular.append(e)
            }
            return (allDay, regular)
        }
        
        @MainActor public func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            controller.dismiss(animated: true) { self.reloadCurrentRange() }
        }
        
        @MainActor public func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            // --- ПРОМЯНА 7: Добавяме guard тук. ---
            guard let modelContext = self.modelContext else {
                print("COORDINATOR: Грешка - ModelContext не е наличен при edit.")
                controller.dismiss(animated: true) { self.reloadCurrentRange() }
                return
            }
            if action == .saved, let savedEvent = controller.event {
                if let notes = savedEvent.notes, OptimizedInvisibleCoder.decode(from: notes) != nil {
                    CalendarViewModel.shared.updateShoppingList(from: savedEvent, context: modelContext)
                } else {
                    CalendarViewModel.shared.createShoppingListFromEvent(event: savedEvent, profile: parent.profile, context: modelContext)
                }
                NotificationCenter.default.post(name: .shoppingListDidChange, object: nil)
            }
            controller.dismiss(animated: true) { self.reloadCurrentRange() }
        }

        @MainActor public func presentSystemEditor(_ ekEvent: EKEvent, in parentVC: UIViewController) {
            let editVC = EKEventEditViewController()
            editVC.eventStore = parent.eventStore
            editVC.event = ekEvent
            editVC.editViewDelegate = self
            parentVC.present(editVC, animated: true)
        }
        
        @MainActor public func createNewEventAndPresent(date: Date, in parentVC: UIViewController, preselectedCalendar: EKCalendar? = nil) {
            let newEvent = EKEvent(eventStore: parent.eventStore)
            newEvent.title = NSLocalizedString("New Shopping List", comment: "")
            newEvent.startDate = date
            newEvent.endDate   = date.addingTimeInterval(7200)
            if let calendar = preselectedCalendar { newEvent.calendar = calendar }
            else {
                let shoppingCalendarID: String?
                if parent.profile.hasSeparateStorage { shoppingCalendarID = parent.profile.shoppingListCalendarID }
                else { shoppingCalendarID = UserDefaults.standard.string(forKey: CalendarViewModel.shared.sharedShoppingListCalendarIDKey) }
                if let id = shoppingCalendarID, let cal = parent.eventStore.calendar(withIdentifier: id) { newEvent.calendar = cal }
                else { newEvent.calendar = parent.eventStore.defaultCalendarForNewEvents }
            }
            presentSystemEditor(newEvent, in: parentVC)
        }
        
        @MainActor public func handleEventDragOrResize(descriptor: EventDescriptor, newDate: Date, isResize: Bool, isAllDay: Bool) {
            if let multi = descriptor as? EKMultiDayWrapper {
                let ev = multi.realEvent
                if ev.hasRecurrenceRules { askUserForRecurring(event: ev, newDate: newDate, isResize: isResize) }
                else {
                    if !isResize { applyDragChanges(ev, newStartDate: newDate, span: .thisEvent, isAllDay: isAllDay) }
                    else { applyResizeChanges(ev, descriptor: multi, forcedNewDate: newDate, span: .thisEvent) }
                }
            }
        }
        
        @MainActor public func askUserForRecurring(event: EKEvent, newDate: Date, isResize: Bool) {
             let alert = UIAlertController(title: NSLocalizedString("Recurring Event", comment: ""), message: NSLocalizedString("This event is part of a series. Update which events?", comment: ""), preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: NSLocalizedString("This Event Only", comment: ""), style: .default, handler: { _ in if !isResize { self.applyDragChanges(event, newStartDate: newDate, span: .thisEvent, isAllDay: false) } else { self.applyResizeChanges(event, descriptor: nil, forcedNewDate: newDate, span: .thisEvent) } }))
            alert.addAction(UIAlertAction(title: NSLocalizedString("All Future Events", comment: ""), style: .default, handler: { _ in if !isResize { self.applyDragChanges(event, newStartDate: newDate, span: .futureEvents, isAllDay: false) } else { self.applyResizeChanges(event, descriptor: nil, forcedNewDate: newDate, span: .futureEvents) } }))
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: { _ in self.reloadCurrentRange() }))
            if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene, let window = windowScene.windows.first(where: { $0.isKeyWindow }), let root = window.rootViewController {
                alert.popoverPresentationController?.sourceView = root.view
                root.present(alert, animated: true)
            }
        }
        
        @MainActor public func applyDragChanges(_ event: EKEvent, newStartDate: Date, span: EKSpan, isAllDay: Bool) {
            // --- ПРОМЯНА 8: Добавяме guard тук. ---
            guard let modelContext = self.modelContext else {
                print("COORDINATOR: Грешка - ModelContext не е наличен при drag.")
                reloadCurrentRange()
                return
            }
             guard let oldStart = event.startDate, let oldEnd = event.endDate else { return }
            let duration = oldEnd.timeIntervalSince(oldStart)
            event.startDate = newStartDate
            event.endDate   = newStartDate.addingTimeInterval(duration)
            do {
                try parent.eventStore.save(event, span: span, commit: true)
                CalendarViewModel.shared.updateShoppingList(from: event, context: modelContext)
                NotificationCenter.default.post(name: .shoppingListDidChange, object: nil)
            } catch { print("Error saving event or updating model: \(error)") }
            reloadCurrentRange()
        }
        
        @MainActor public func applyResizeChanges(_ event: EKEvent, descriptor: EventDescriptor?, forcedNewDate: Date, span: EKSpan) {
            // --- ПРОМЯНА 9: Добавяме guard тук. ---
            guard let modelContext = self.modelContext else {
                print("COORDINATOR: Грешка - ModelContext не е наличен при resize.")
                reloadCurrentRange()
                return
            }
             if let multi = descriptor as? EKMultiDayWrapper {
                let originalInterval = multi.dateInterval
                let distanceToStart = forcedNewDate.timeIntervalSince(originalInterval.start)
                let distanceToEnd   = originalInterval.end.timeIntervalSince(forcedNewDate)
                if distanceToStart < distanceToEnd { if forcedNewDate < event.endDate { event.startDate = forcedNewDate } }
                else { if forcedNewDate > event.startDate { event.endDate = forcedNewDate } }
            }
            do {
                try parent.eventStore.save(event, span: span, commit: true)
                CalendarViewModel.shared.updateShoppingList(from: event, context: modelContext)
                NotificationCenter.default.post(name: .shoppingListDidChange, object: nil)
            } catch { print("Error saving event: \(error)") }
            reloadCurrentRange()
        }
        
        @MainActor public func presentSystemDetails(_ ekEvent: EKEvent, in parentVC: UIViewController) {
            let eventVC = EKEventViewController()
            eventVC.event = ekEvent
            eventVC.delegate = self
            eventVC.allowsEditing = true
            eventVC.allowsCalendarPreview = true
            let navVC = UINavigationController(rootViewController: eventVC)
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
