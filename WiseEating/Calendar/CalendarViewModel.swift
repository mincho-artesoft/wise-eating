// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/Calendar/CalendarViewModel.swift ====
// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth/WiseEating/Calendar/CalendarViewModel.swift ====
import SwiftUI
import SwiftData
import EventKit
import Combine

@MainActor
final class CalendarViewModel: ObservableObject {
        
    private var profileMetadataEventDate: Date {
            var components = DateComponents()
            components.year = 1977
            components.month = 9
            components.day = 1
            components.hour = 12
            components.minute = 0
            return Calendar.current.date(from: components)!
        }
    
    private let profileCalendarSuffix = " – Wise Eating"
        private let profileMetadataEventTitle = "DO_NOT_DELETE_Wise Eating_Profile_Data"
    
    // MARK: - EventKit Store & Properties
    var eventStore: EKEventStore = EKEventStore()
    private var recentlyDeletedCalendarIDs = Set<String>()
    let sharedShoppingListCalendarIDKey = "SharedShoppingListCalendarID"
    private let deletedCalendarIDsKey = "WE_DeletedCalendarIDs"
    private let deletedProfileUUIDsKey = "WE_DeletedProfileUUIDs"
    
    private var deletedCalendarIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: deletedCalendarIDsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: deletedCalendarIDsKey) }
    }

    private var deletedProfileUUIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: deletedProfileUUIDsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: deletedProfileUUIDsKey) }
    }
    
    @Published var allCalendars: [EKCalendar] = []
    @Published var eventsByDay: [Date: [EKEvent]] = [:]
    @Published var eventsByID:  [String: EKEvent] = [:]

    @Published var accessGranted = false
    @Published var selectedCalendarIDs: Set<String> = []
    @Published var calendarsDict: [String: (title: String,
                                            color: UIColor,
                                            selected: Bool,
                                            calendar: EKCalendar)] = [:] {
        didSet {
            NotificationCenter.default.post(
                name: .calendarsSelectionChanged,
                object: nil
            )
        }
    }

    @MainActor
    func markProfileAsDeleted(profileUUID: UUID, calendarID: String?) {
        var uuids = deletedProfileUUIDs
        uuids.insert(profileUUID.uuidString)
        deletedProfileUUIDs = uuids

        if let cid = calendarID {
            var cids = deletedCalendarIDs
            cids.insert(cid)
            deletedCalendarIDs = cids
        }
    }
    
    @Published var firstLocalCalendarColor: UIColor?

    static let shared = CalendarViewModel()

    let calendar = Calendar.current
    
    private var cancellables = Set<AnyCancellable>()

    var visibleCalendarIDs: Set<String> {
         let selected = calendarsDict.filter { $0.value.selected }
         
         return selected.isEmpty
             ? Set(calendarsDict.keys)
             : Set(selected.keys)
     }
    
    // MARK: - Init
    init() {
        reloadCalendars()
        if let storedArray = UserDefaults.standard.array(forKey: "SelectedCalendarIDsKey") as? [String], !storedArray.isEmpty {
            self.selectedCalendarIDs = Set(storedArray)
        } else {
            self.selectedCalendarIDs = Set(eventStore.calendars(for: .event).map { $0.calendarIdentifier })
        }

        $selectedCalendarIDs
            .sink { newValue in
                let array = Array(newValue)
                UserDefaults.standard.set(array, forKey: "SelectedCalendarIDsKey")
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEventStoreChanged(_:)),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }
    
    @objc private func handleEventStoreChanged(_ notification: Notification) {
        print("EKEventStore has changed. Reloading calendars...")
        reloadCalendars()
    }

    @MainActor
    func updateSelectedCalendars(for profiles: [Profile]) {
        let desired = Set(profiles.compactMap { $0.calendarID })

        var changed = false
        for key in calendarsDict.keys {
            var entry = calendarsDict[key]!
            let newSel = desired.contains(key)
            if entry.selected != newSel {
                entry.selected = newSel
                calendarsDict[key] = entry
                changed = true
            }
        }
        selectedCalendarIDs = desired

        if changed {
            NotificationCenter.default.post(name: .calendarsSelectionChanged, object: nil)
        }
    }
    
    // MARK: - Calendar Access
    func isCalendarAccessGranted() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            return (status == .fullAccess)
        } else {
            return (status == .authorized)
        }
    }

    func requestCalendarAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                self.accessGranted = granted
                return granted
            } catch {
                print("Error requesting calendar access: \(error.localizedDescription)")
                self.accessGranted = false
                return false
            }
        } else {
            let granted = isCalendarAccessGranted()
            self.accessGranted = granted
            return granted
        }
    }
    
    // MARK: - Load Calendars & Events
    func reloadCalendars() {
        let cals = eventStore.calendars(for: .event)
        self.allCalendars = cals
        syncNonOtherCalendarsDict()

        if let writableSelectedCal = pickFirstWritableSelectedCalendar(),
           let cgColor = writableSelectedCal.cgColor {
            self.firstLocalCalendarColor = UIColor(cgColor: cgColor)
        } else {
            self.firstLocalCalendarColor = nil
        }
    }

    @MainActor
    func pickFirstWritableSelectedCalendar() -> EKCalendar? {
        let selectedIDs = selectedCalendarIDs
        let possibleCalendars = allowedCalendars()
        for cal in possibleCalendars {
            if selectedIDs.contains(cal.calendarIdentifier), cal.allowsContentModifications {
                return cal
            }
        }
        return nil
    }
    
    func allowedCalendars() -> [EKCalendar] {
        allCalendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
    }
    
    func localOrICloudCalendars() -> [EKCalendar] {
       return allCalendars.filter {
           $0.source.sourceType == .local || $0.source.sourceType == .calDAV
       }
    }
    
    func otherCalendars() -> [EKCalendar] {
       return allCalendars.filter {
           $0.source.sourceType != .local && $0.source.sourceType != .calDAV
       }
    }
    
    func syncNonOtherCalendarsDict() {
        let otherSet = Set(otherCalendars())
        let nonOtherCals = allCalendars.filter { !otherSet.contains($0) }
        
        var newDict: [String: (title: String, color: UIColor, selected: Bool, calendar: EKCalendar)] = [:]
        
        for cal in nonOtherCals {
            var uiColor = UIColor.systemGray
            if let cgColor = cal.cgColor {
                uiColor = UIColor(cgColor: cgColor)
            }
            
            let wasSelected = calendarsDict[cal.calendarIdentifier]?.selected ?? true
            
            newDict[cal.calendarIdentifier] = (
                title: cal.title,
                color: uiColor,
                selected: wasSelected,
                calendar: cal
            )
        }
        self.calendarsDict = newDict
    }

    func loadEvents(for month: Date) {
        guard isCalendarAccessGranted() else {
            self.eventsByDay = [:]
            self.eventsByID  = [:]
            return
        }
        
        let fetched = eventStore.fetchEventsByDay(for: month,
                                                  calendar: calendar,
                                                  allowedCalendarIDs: selectedCalendarIDs)
        self.eventsByDay = fetched
        
        var tmp: [String: EKEvent] = [:]
        for evList in fetched.values {
            for ev in evList {
                if let eventId = ev.eventIdentifier {
                    tmp[eventId] = ev
                }
            }
        }
        self.eventsByID = tmp
    }

    func loadEventsForWholeYear(year: Int) {
        guard isCalendarAccessGranted() else {
            self.eventsByDay = [:]
            self.eventsByID  = [:]
            return
        }

        var comp = DateComponents()
        comp.year = year
        comp.month = 1
        comp.day = 1
        guard let startOfYear = calendar.date(from: comp) else { return }

        var compNext = DateComponents()
        compNext.year = year + 1
        compNext.month = 1
        compNext.day = 1
        guard let startOfNextYear = calendar.date(from: compNext) else { return }

        let allowedCals = allowedCalendars()
        let predicate = eventStore.predicateForEvents(
            withStart: startOfYear,
            end: startOfNextYear,
            calendars: allowedCals
        )
        let foundEvents = eventStore.events(matching: predicate)

        var dict: [Date: [EKEvent]] = [:]
        for ev in foundEvents {
            let dayKey = calendar.startOfDay(for: ev.startDate)
            dict[dayKey, default: []].append(ev)
        }
        self.eventsByDay = dict

        var tmp: [String: EKEvent] = [:]
        for evList in dict.values {
            for ev in evList {
                if let eventId = ev.eventIdentifier {
                    tmp[eventId] = ev
                }
            }
        }
        self.eventsByID = tmp
    }
}


extension CalendarViewModel {
    
    func existingCalendar(for profile: Profile) -> EKCalendar? {
            if let cid = profile.calendarID,
               let cal = eventStore.calendar(withIdentifier: cid) {
                return cal
            }
            return nil
        }
       
    @MainActor
    func calendarEX(for profile: Profile) -> EKCalendar? {
           print("▶️ calendarEX(for:) –", profile.name)
           if let cal = existingCalendar(for: profile) {
               print("   ✅ returning existing calendar:", cal.title)
               return cal
           }

           print("   ➕ creating new calendar via createOrUpdateCalendar…")
           return createOrUpdateCalendar(for: profile)
       }

    @discardableResult
       func createEvent(forProfile profile: Profile,
                        startDate: Date,
                        endDate: Date,
                        title: String,
                        invisiblePayload: String?,
                        existingEventID: String? = nil,
                        reminderMinutes: Int? = nil) async -> (Bool, String?) {
           guard let calendar = calendarEX(for: profile) else { return (false, nil) }

           var s = startDate, e = endDate
           if e <= s { e = s.addingTimeInterval(3600) }

           let event: EKEvent = {
               if let id = existingEventID, let ev = eventStore.event(withIdentifier: id) {
                   return ev
               }
               let ev = EKEvent(eventStore: eventStore)
               ev.calendar = calendar
               return ev
           }()

           event.title     = title
           event.startDate = s
           event.endDate   = e
           event.notes = invisiblePayload ?? ""
           event.alarms = nil
           
           if let minutes = reminderMinutes, minutes > 0 {
               let interval = -TimeInterval(minutes * 60)
               let alarm = EKAlarm(relativeOffset: interval)
               event.addAlarm(alarm)
               print("   ⏰ Added alarm for \(minutes) minutes before event.")
           }

           do {
               try eventStore.save(event, span: .thisEvent, commit: true)
               if #available(iOS 17, *) { eventStore.refreshSourcesIfNecessary() } else { eventStore.reset() }
               return (true, event.eventIdentifier)
           } catch {
               print("❗️ createEvent error:", error.localizedDescription)
               return (false, nil)
           }
       }

       func deleteEvent(withIdentifier id: String) async -> Bool {
           print("🗑️ deleteEvent – id:", id)
           guard let ev = eventStore.event(withIdentifier: id) else {
               print("   ⚠️ event not found")
               return false
           }
           do {
               try eventStore.remove(ev, span: .thisEvent, commit: true)
               print("   ✅ deleted")
               return true
           } catch {
               print("   ❗️ delete error:", error.localizedDescription)
               return false
           }
       }
       
       func fetchEvents(forProfile profile: Profile, startDate: Date, endDate: Date) async -> [EKEvent] {
//           print("🔍 fetchEvents (Async, Year-by-Year) for profile: \(profile.name) from \(startDate.formatted()) to \(endDate.formatted())")
           
           guard let calendarForProfile = existingCalendar(for: profile) else {
//               print("   ❌ No calendar found for this profile. Returning empty array.")
               return []
           }
           
           let calendar = Calendar.current
           let startYear = calendar.component(.year, from: startDate)
           let endYear = calendar.component(.year, from: endDate)
           
           var allEvents: [EKEvent] = []
           
           for year in startYear...endYear {
               let yearStartDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
               let yearEndDate = calendar.date(from: DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59))!
               
               let fetchStartForYear = max(startDate, yearStartDate)
               let fetchEndForYear = min(endDate, yearEndDate)
               
               if fetchStartForYear >= fetchEndForYear {
                   continue
               }
               
//               print("   -> Fetching for year \(year)... (range: \(fetchStartForYear.formatted()) to \(fetchEndForYear.formatted()))")

               let predicate = eventStore.predicateForEvents(withStart: fetchStartForYear, end: fetchEndForYear, calendars: [calendarForProfile])
               let yearlyEvents = eventStore.events(matching: predicate)
               allEvents.append(contentsOf: yearlyEvents)
               
//               print("   -> Found \(yearlyEvents.count) events for year \(year). Total so far: \(allEvents.count)")
           }
           
//           print("   ✅ Total events found across all years: \(allEvents.count)")
           return allEvents
       }
}

extension CalendarViewModel {
    
    func event(named name: String,
               onDay date: Date,
               for profile: Profile) async -> EKEvent? {

        print("🔍 event(named:) –", name, "on", date)
        guard let cal = existingCalendar(for: profile) else {
            print("   ❌ no calendar found for this profile")
            return nil
        }

        let dayStart = Calendar.current.startOfDay(for: date)
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        let pred   = eventStore.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: [cal])
        let events = eventStore.events(matching: pred)
        let result = events.first { $0.title == name }

        print(result != nil ? "   ✅ found event" : "   🚫 not found")
        return result
    }
}

extension CalendarViewModel {

    @MainActor
    func deleteCalendar(withID calendarID: String?) async {
        print("🗑️ deleteCalendar – id:", calendarID ?? "nil")
        guard let id = calendarID else {
            print("   ℹ️ no calendarID provided → nothing to delete")
            return
        }

        // Mark calendar as deleted (tombstone) immediately
        var cids = deletedCalendarIDs
        cids.insert(id)
        deletedCalendarIDs = cids

        let maxRetries = 3
        for attempt in 1...maxRetries {
            guard let cal = eventStore.calendar(withIdentifier: id) else {
                print("   ✅ Calendar not found (already gone).")
                // Clean tombstone for this specific calendar ID (safe to remove)
                var c = deletedCalendarIDs; c.remove(id); deletedCalendarIDs = c
                return
            }
            do {
                try eventStore.removeCalendar(cal, commit: true)

                if #available(iOS 17, *) { eventStore.refreshSourcesIfNecessary() } else { eventStore.reset() }

                if eventStore.calendar(withIdentifier: id) == nil {
                    print("   ✅ Calendar deleted.")
                    var c = deletedCalendarIDs; c.remove(id); deletedCalendarIDs = c
                    return
                } else {
                    print("   ⚠️ Calendar still visible after delete, retrying…")
                }
            } catch {
                print("   ❗️ [Attempt \(attempt)] removeCalendar error:", error.localizedDescription)
            }

            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300 ms
            }
        }

        print("   ❌ Unable to confirm deletion of calendar \(id). Tombstone remains to block reconstruction.")
    }

    
    @MainActor
          func meals(forProfile profile: Profile, on day: Date) async -> [Meal] {
              let dayStart = Calendar.current.startOfDay(for: day)
              guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
              
              let events = await fetchEvents(forProfile: profile, startDate: dayStart, endDate: dayEnd)
              
              let mealTemplateNames = Set(profile.meals.map { $0.name })
              let trainingTemplateNames = Set(profile.trainings.map { $0.name })

              return events.filter { event in
                   let title = event.title ?? ""
                   
                   // --- НАЧАЛО НА КОРЕКЦИЯТА ---
                   // Правило 1: Проверяваме payload-а ПЪРВО.
                   if let notes = event.notes, let decoded = OptimizedInvisibleCoder.decode(from: notes) {
                       // Ако е списък за пазаруване (JSON), изключваме.
                       if decoded.trimmingCharacters(in: .whitespaces).starts(with: "{") {
                           return false
                       }
                       // Ако е тренировка (маркер), изключваме.
                       if decoded.starts(with: "#TRAINING#") {
                           return false
                       }
                   }
                   
                   // Правило 2: Ако името съвпада с шаблон за тренировка, изключваме.
                   if trainingTemplateNames.contains(title) {
                       return false
                   }
                  
                   // Правило 3: Ако името съвпада с шаблон за хранене, включваме.
                   if mealTemplateNames.contains(title) {
                       return true
                   }
                   
                   // Правило 4: Ако има payload (който не е за тренировка/пазаруване) - включваме.
                   // Това хваща "New Meal" и преименувани хранения.
                   if let notes = event.notes, OptimizedInvisibleCoder.decode(from: notes) != nil {
                       return true
                   }
                  
                   // Правило 5: Игнорираме всичко останало.
                   return false
                   // --- КРАЙ НА КОРЕКЦИЯТА ---
              }.map { Meal(event: $0) }
          }
       
    @MainActor
       func trainings(forProfile profile: Profile, on day: Date) async -> [Training] {
           let dayStart = Calendar.current.startOfDay(for: day)
           guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

           let events = await fetchEvents(forProfile: profile, startDate: dayStart, endDate: dayEnd)
           
           // --- НАЧАЛО НА КОРЕКЦИЯТА ---
           let mealTemplateNames = Set(profile.meals.map { $0.name })
           let trainingTemplateNames = Set(profile.trainings.map { $0.name })
           
           return events.filter { event in
               let title = event.title ?? ""

               // Правило 1: Проверяваме payload-а ПЪРВО.
               if let notes = event.notes, let decoded = OptimizedInvisibleCoder.decode(from: notes) {
                   // Ако payload-ът започва с маркера за тренировка, ВИНАГИ е тренировка.
                   if decoded.starts(with: "#TRAINING#") {
                       return true
                   }
               }
               
               // Правило 2: ВИНАГИ включи, ако името съвпада с шаблон за тренировка.
               if trainingTemplateNames.contains(title) {
                   return true
               }

               // Правило 3: ВИНАГИ изключи, ако името съвпада с шаблон за хранене.
               if mealTemplateNames.contains(title) {
                   return false
               }
               
               // Всичко останало се игнорира.
               return false
           }.map { Training(event: $0) }
           // --- КРАЙ НА КОРЕКЦИЯТА ---
       }
       
    // НОВ МЕТОД: Добавете този метод за създаване/обновяване на събития за тренировки
    // Оригинална версия
    @discardableResult
    func createOrUpdateTrainingEvent(
        forProfile profile: Profile,
        training: Training,
        exercisesPayload: String?
    ) async -> (Bool, String?) {
        guard let calendar = calendarEX(for: profile) else { return (false, nil) }

        var s = training.startTime, e = training.endTime
        if e <= s { e = s.addingTimeInterval(3600) }

        let event: EKEvent = {
            if let id = training.calendarEventID, let ev = eventStore.event(withIdentifier: id) {
                return ev
            }
            let ev = EKEvent(eventStore: eventStore)
            ev.calendar = calendar
            return ev
        }()

        event.title     = training.name
        event.startDate = s
        event.endDate   = e
        event.notes = exercisesPayload ?? ""
        event.alarms = nil
        
        // --- НАЧАЛО НА ПРОМЯНАТА ---
        // ПРЕМАХНЕТЕ ИЛИ КОМЕНТИРАЙТЕ ЦЕЛИЯ ТОЗИ БЛОК
        /*
        if let minutes = training.reminderMinutes, minutes > 0 {
            let interval = -TimeInterval(minutes * 60)
            let alarm = EKAlarm(relativeOffset: interval)
            event.addAlarm(alarm)
            print("   ⏰ Added alarm for \(minutes) minutes before event.")
        }
        */
        // --- КРАЙ НА ПРОМЯНАТА ---

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            if #available(iOS 17, *) { eventStore.refreshSourcesIfNecessary() } else { eventStore.reset() }
            return (true, event.eventIdentifier)
        } catch {
            print("❗️ createTrainingEvent error:", error.localizedDescription)
            return (false, nil)
        }
    }
}


extension CalendarViewModel {
    
    @discardableResult
    @MainActor
    func createOrUpdateCalendar(for profile: Profile) -> EKCalendar? {
        print("🆕 createOrUpdateCalendar (New Logic) –", profile.name)

        guard accessGranted else {
            print("   ❌ no permissions – abort")
            return nil
        }
        let newTitle = "\(profile.name)\(profileCalendarSuffix)"
        if let id = profile.calendarID, let cal = eventStore.calendar(withIdentifier: id) {
            print("   ✅ Found existing calendar.")
            if cal.title != newTitle {
                cal.title = newTitle
                do {
                    try eventStore.saveCalendar(cal, commit: true)
                    print("   🔄 Updated calendar title to: \(newTitle)")
                } catch {
                    print("   ❗️ Failed to save updated calendar title: \(error)")
                }
            }
            Task {
                await createOrUpdateMetadataEvent(for: profile, in: cal)
            }
            return cal
        }
        
        guard let source = eventStore.sources.first(where: { $0.sourceType == .local }) ?? eventStore.defaultCalendarForNewEvents?.source else {
            print("   ❗️ no local source found")
            return nil
        }

        let calendarColors: [UIColor] = [
            .systemRed, .systemOrange, .systemGreen, .systemTeal, .systemBlue,
            .systemIndigo, .systemPurple, .systemPink, .systemBrown, .systemMint, .systemCyan
        ]
        
        let newCal = EKCalendar(for: .event, eventStore: eventStore)
        newCal.title  = newTitle
        newCal.source = source
        newCal.cgColor = (calendarColors.randomElement() ?? .systemBlue).cgColor

        do {
            try eventStore.saveCalendar(newCal, commit: true)
            profile.calendarID = newCal.calendarIdentifier
            print("   ✅ Created new calendar with id:", newCal.calendarIdentifier)
            
            Task {
                await createOrUpdateMetadataEvent(for: profile, in: newCal)
            }
            
            reloadCalendars()
            return newCal
        } catch {
            print("   ❗️ create calendar error:", error.localizedDescription)
            return nil
        }
    }

    // ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/Calendar/CalendarViewModel.swift ====

        @MainActor
        func reconstructProfilesFromCalendars(
            existingProfileIDs: Set<String>,
            allVitamins: [Vitamin],
            allMinerals: [Mineral],
            context: ModelContext
        ) async {
            print("🔎 Starting profile reconstruction from calendars (Tombstone-aware)…")

            defer { recentlyDeletedCalendarIDs.removeAll() }

            let allCals = eventStore.calendars(for: .event)

            let existingIDs = Set(allCals.map { $0.calendarIdentifier })
            let stale = deletedCalendarIDs.subtracting(existingIDs)
            if !stale.isEmpty {
                var cids = deletedCalendarIDs
                for id in stale { cids.remove(id) }
                deletedCalendarIDs = cids
            }

            let vitaHealthCalsAll = allCals.filter { $0.title.hasSuffix(profileCalendarSuffix) }
            let vitaHealthCals = vitaHealthCalsAll.filter { !deletedCalendarIDs.contains($0.calendarIdentifier) }

            var reconstructedCount = 0

            for calendar in vitaHealthCals {
                guard let (profileUUID, payload) = await reconstructProfileData(from: calendar) else { continue }
                if deletedProfileUUIDs.contains(profileUUID.uuidString) { continue }

                let existingProfileDescriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.id == profileUUID })
                if let existingCount = try? context.fetchCount(existingProfileDescriptor), existingCount > 0 { continue }
                if recentlyDeletedCalendarIDs.contains(calendar.calendarIdentifier) { continue }

                print("   ✅ Decoded profile '\(payload.name)' with UUID \(profileUUID) from metadata event.")

                let vitamins = allVitamins.filter { payload.priorityVitaminIDs.contains($0.id) }
                let minerals = allMinerals.filter { payload.priorityMineralIDs.contains($0.id) }
                
                let dietNames = Set(payload.dietIDs)
                let diets: [Diet]
                if !dietNames.isEmpty {
                    let predicate = #Predicate<Diet> { diet in dietNames.contains(diet.name) }
                    diets = (try? context.fetch(FetchDescriptor<Diet>(predicate: predicate))) ?? []
                } else {
                    diets = []
                }

                for meal in payload.meals where meal.modelContext == nil { context.insert(meal) }

                let newProfile = Profile(
                    name: payload.name, birthday: payload.birthday, gender: payload.gender, weight: payload.weight, height: payload.height,
                    meals: payload.meals, activityLevel: payload.activityLevel, isPregnant: payload.isPregnant, isLactating: payload.isLactating,
                    calendarID: calendar.calendarIdentifier, priorityVitamins: vitamins, priorityMinerals: minerals, diets: diets,
                    allergens: payload.allergens, photoData: nil
                )
                newProfile.id = profileUUID

                context.insert(newProfile)
                reconstructedCount += 1
                
                print("   -> Attempting to restore Nodes for profile '\(newProfile.name)' from calendar '\(calendar.title)'")
                
                // +++ НАЧАЛО НА ПРОМЯНАТА +++
                // Променяме периода на търсене на 1 година назад и 1 месец напред.
                let now = Date()
                let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
                let oneMonthFromNow = Calendar.current.date(byAdding: .month, value: 1, to: now) ?? now
                
                print("   -> Searching for Node events between \(oneYearAgo.formatted()) and \(oneMonthFromNow.formatted())")

                let nodePredicate = eventStore.predicateForEvents(withStart: oneYearAgo, end: oneMonthFromNow, calendars: [calendar])
                // +++ КРАЙ НА ПРОМЯНАТА +++
                
                let allEventsInCalendar = eventStore.events(matching: nodePredicate)
                print("   -> Found \(allEventsInCalendar.count) total events in this calendar within the specified date range.")

                let nodeEvents = allEventsInCalendar.filter {
                    $0.title?.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Node") == .orderedSame
                }
                
                print("   -> Found \(nodeEvents.count) potential Node events after filtering for title 'Node'.")
                var restoredNodeCount = 0

                for event in nodeEvents {
                    guard let eventID = event.eventIdentifier else {
                        print("      - Skipping an event because it has no identifier.")
                        continue
                    }
                    
                    print("      - Processing event: '\(event.title ?? "")' on \(event.startDate.formatted()) with ID: \(eventID)")

                    let profileID = newProfile.persistentModelID
                    let descriptor = FetchDescriptor<Node>(predicate: #Predicate {
                        $0.calendarEventID == eventID && $0.profile?.persistentModelID == profileID
                    })
                    
                    let existingCount = (try? context.fetchCount(descriptor)) ?? 0
                    if existingCount > 0 {
                        print("      - Node with this calendarEventID already exists for this profile. Skipping to avoid duplicate.")
                        continue
                    }

                    let newNode = Node(
                        textContent: event.notes,
                        profile: newProfile,
                        date: event.startDate
                    )
                    newNode.calendarEventID = eventID
                    context.insert(newNode)
                    restoredNodeCount += 1
                }

                if restoredNodeCount > 0 {
                    print("   ✅ Restored \(restoredNodeCount) Node objects for profile '\(newProfile.name)'.")
                }
            }

            if reconstructedCount > 0 {
                do {
                    try context.save()
                    print("   💾 Saved \(reconstructedCount) reconstructed profiles and their nodes to SwiftData.")
                } catch {
                    print("   ❗️❗️❗️ CRITICAL ERROR: Failed to save reconstructed data: \(error.localizedDescription)")
                }
            } else {
                print("   No new profiles to reconstruct.")
            }
        }


    private func reconstructProfile(from calendar: EKCalendar) -> (UUID, ProfilePayload)? {
        let invisibleAlphabetSet: Set<UnicodeScalar> = Set(["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{2061}", "\u{2062}", "\u{2063}", "\u{2064}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}"].flatMap { $0.unicodeScalars })
        
        let invisiblePart = String(calendar.title.unicodeScalars.prefix(while: { invisibleAlphabetSet.contains($0) }))
        guard !invisiblePart.isEmpty else { return nil }
        
        guard let decodedString = OptimizedInvisibleCoder.decode(from: invisiblePart) else { return nil }
        
        let parts = decodedString.components(separatedBy: ":::")
        guard parts.count == 2, let profileUUID = UUID(uuidString: parts[0]) else { return nil }
        
        let jsonString = parts[1]
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        
        do {
            let payload = try JSONDecoder().decode(ProfilePayload.self, from: jsonData)
            return (profileUUID, payload)
        } catch {
            print("   Error decoding ProfilePayload from JSON: \(error)")
            return nil
        }
    }
}

extension CalendarViewModel {
    
    @MainActor
    func createSystemCalendar(name: String, color: UIColor) -> EKCalendar? {
        guard let source = eventStore.sources.first(where: { $0.sourceType == .local }) ?? eventStore.defaultCalendarForNewEvents?.source else {
            print("   ❗️ Не найден локальный источник для создания календаря.")
            return nil
        }
        
        let newCal = EKCalendar(for: .event, eventStore: eventStore)
        newCal.title = name
        newCal.source = source
        newCal.cgColor = color.cgColor
        
        do {
            try eventStore.saveCalendar(newCal, commit: true)
            reloadCalendars()
            print("   ✅ Системный календарь успешно создан и сохранен: \(name)")
            return newCal
        } catch {
            print("   ❗️ Ошибка при создании системного календаря '\(name)': \(error.localizedDescription)")
            return nil
        }
    }
    
    @MainActor
    private func getShoppingCalendar(for list: ShoppingListModel) -> EKCalendar? {
        print("🛒 getShoppingCalendar for list: '\(list.name)'")
        
        if let listProfile = list.profile {
            print("   -> List is PRIVATE to profile '\(listProfile.name)'")
            if let calendarID = listProfile.shoppingListCalendarID, let existingCal = eventStore.calendar(withIdentifier: calendarID) {
                print("   ✅ Found existing PRIVATE calendar: \(existingCal.title)")
                return existingCal
            }
            
            let calendarName = "\(listProfile.name) – Shopping List"
            print("   ➕ Creating new PRIVATE calendar: \(calendarName)")
            let newCal = createSystemCalendar(name: calendarName, color: .systemYellow)
            
            if let newCal = newCal {
                listProfile.shoppingListCalendarID = newCal.calendarIdentifier
            }
            return newCal
            
        } else {
            print("   -> List is SHARED")
            if let sharedCalID = UserDefaults.standard.string(forKey: sharedShoppingListCalendarIDKey),
               let existingSharedCal = eventStore.calendar(withIdentifier: sharedCalID) {
                print("   ✅ Found existing SHARED calendar: \(existingSharedCal.title)")
                return existingSharedCal
            }
            
            let calendarName = "Shared Shopping List – Wise Eating"
            print("   ➕ Creating new SHARED calendar: \(calendarName)")
            let newSharedCal = createSystemCalendar(name: calendarName, color: .systemOrange)
            
            if let newSharedCal = newSharedCal {
                UserDefaults.standard.set(newSharedCal.calendarIdentifier, forKey: sharedShoppingListCalendarIDKey)
            }
            return newSharedCal
        }
    }
    
    @discardableResult
    @MainActor
    func createOrUpdateShoppingListEvent(
        for list: ShoppingListModel,
        context: ModelContext
    ) async -> String? {
        
        print("🛒 createOrUpdateShoppingListEvent for list: '\(list.name)'")
        
        guard let calendar = getShoppingCalendar(for: list) else {
            print("   ❌ Cannot get or create a calendar for the shopping list. Aborting.")
            return nil
        }
        print("   -> Will save to calendar: '\(calendar.title)'")
        
        let payload = ShoppingListPayload(from: list)
        var invisiblePayload: String? = nil
        do {
            let jsonData = try JSONEncoder().encode(payload)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                invisiblePayload = OptimizedInvisibleCoder.encode(from: jsonString)
                print("   ✅ List payload encoded.")
            }
        } catch {
            print("   ❗️ Error encoding shopping list to JSON: \(error)")
        }
        
        let event: EKEvent = {
            if let id = list.calendarEventID, let ev = eventStore.event(withIdentifier: id) {
                print("   🔄 Updating existing calendar event.")
                return ev
            }
            print("   ➕ Creating new calendar event.")
            let ev = EKEvent(eventStore: eventStore)
            return ev
        }()
        
        event.calendar = calendar
        
        event.title = list.name
        event.startDate = list.eventStartDate
        event.endDate = list.eventStartDate.addingTimeInterval(7200)
        event.isAllDay = false
        event.notes = invisiblePayload ?? ""
        event.alarms = nil
        
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            
            if #available(iOS 17, *) {
                eventStore.refreshSourcesIfNecessary()
            } else {
                eventStore.reset()
            }
            
            let eventID = event.eventIdentifier!
            print("   ✅ Event saved with identifier: \(eventID)")
            return eventID
        } catch {
            print("   ❗️ Error in createOrUpdateShoppingListEvent: \(error.localizedDescription)")
            return nil
        }
    }
    
    @MainActor
    func updateShoppingList(from event: EKEvent, context: ModelContext) {
        print("🔄 Опит за обновяване на ShoppingListModel от EKEvent: \(event.title ?? "N/A")")
        
        guard let notes = event.notes,
              let jsonString = OptimizedInvisibleCoder.decode(from: notes),
              let jsonData = jsonString.data(using: .utf8) else {
            print("   ❌ В събитието няма кодирани данни за ShoppingList.")
            return
        }
        
        do {
            let payload = try JSONDecoder().decode(ShoppingListPayload.self, from: jsonData)
            let listID = payload.id
            
            let fetchDescriptor = FetchDescriptor<ShoppingListModel>(
                predicate: #Predicate { $0.id == listID }
            )
            
            if let listToUpdate = try context.fetch(fetchDescriptor).first {
                listToUpdate.eventStartDate = event.startDate
                
                if let alarm = event.alarms?.first, alarm.relativeOffset < 0 {
                    listToUpdate.reminderMinutes = Int(abs(alarm.relativeOffset / 60))
                } else {
                    listToUpdate.reminderMinutes = nil
                }
                
                print("   ✅ ShoppingListModel с ID \(listID) е намерен и данните му са обновени.")
                
                if context.hasChanges {
                    try context.save()
                    print("   💾 Промените в SwiftData са запазени.")
                }
                
            } else {
                print("   ❌ ShoppingListModel с ID \(listID) не е намерен в SwiftData.")
            }
            
        } catch {
            print("   ❗️ Грешка при декодиране на ShoppingListPayload: \(error)")
        }
    }
    
    @MainActor
    func createShoppingListFromEvent(event: EKEvent, profile: Profile, context: ModelContext) {
        print("VIEWMODEL: 🛒 Започва създаване на ShoppingListModel от EKEvent: \(event.title ?? "N/A")")
        
        let profileForList: Profile?
        if profile.hasSeparateStorage {
            profileForList = profile
        } else {
            profileForList = nil
        }
        
        let newList = ShoppingListModel(profile: profileForList, name: event.title)
        newList.eventStartDate = event.startDate
        newList.calendarEventID = event.eventIdentifier
        
        if let alarm = event.alarms?.first, alarm.relativeOffset < 0 {
            newList.reminderMinutes = Int(abs(alarm.relativeOffset / 60))
        }
        
        context.insert(newList)
        
        let payload = ShoppingListPayload(from: newList)
        var invisiblePayload: String? = nil
        do {
            let jsonData = try JSONEncoder().encode(payload)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                invisiblePayload = OptimizedInvisibleCoder.encode(from: jsonString)
            }
        } catch {
            print("VIEWMODEL: ❗️ Грешка при кодиране на новия списък: \(error)")
        }
        
        event.notes = invisiblePayload
        
        do {
            try context.save()
            try eventStore.save(event, span: .thisEvent, commit: true)
            print("VIEWMODEL: ✅✅ УСПЕХ! Създаден е ShoppingListModel и е обновен EKEvent с payload.")
            
        } catch {
            print("VIEWMODEL: ❗️❗️ КРИТИЧНА ГРЕШКА при финалния запис на модел/събитие: \(error)")
        }
    }
    
    @MainActor
    func ensureSharedShoppingListCalendarExists() async {
        print("🛒 Проверка за съществуване на споделен календар за пазаруване...")
        
        guard await requestCalendarAccessIfNeeded() else {
            print("   ❌ Няма достъп до календара. Проверката е прекратена.")
            return
        }
        
        let calendarName = "Shared Shopping List – Wise Eating"
        
        if let sharedCalID = UserDefaults.standard.string(forKey: sharedShoppingListCalendarIDKey),
           let calendar = eventStore.calendar(withIdentifier: sharedCalID) {
            if calendar.title == calendarName {
                print("   ✅ Споделеният календар е намерен по ID в UserDefaults.")
                return
            }
        }
        
        let allCalendars = eventStore.calendars(for: .event)
        if let foundByName = allCalendars.first(where: { $0.title == calendarName }) {
            print("   ✅ Намерен е съществуващ календар по име. Записване на неговото ID.")
            UserDefaults.standard.set(foundByName.calendarIdentifier, forKey: sharedShoppingListCalendarIDKey)
            return
        }
        
        print("   ➕ Календар с такова име не е намерен. Създаване на нов...")
        if let newSharedCal = createSystemCalendar(name: calendarName, color: .systemOrange) {
            UserDefaults.standard.set(newSharedCal.calendarIdentifier, forKey: sharedShoppingListCalendarIDKey)
            print("   💾 ID-то на новия споделен календар е запазено в UserDefaults.")
        } else {
            print("   ❗️ Неуспешно създаване на споделен календар за пазаруване.")
        }
    }
    
    private func reconstructProfileData(from calendar: EKCalendar) async -> (UUID, ProfilePayload)? {
        let searchDate = profileMetadataEventDate
        guard let oneDayAfter = Calendar.current.date(byAdding: .day, value: 1, to: searchDate) else { return nil }
        
        let predicate = eventStore.predicateForEvents(withStart: searchDate, end: oneDayAfter, calendars: [calendar])
        let events = eventStore.events(matching: predicate)
        
        guard let metadataEvent = events.first(where: { $0.title == profileMetadataEventTitle }) else {
            print("   ... ❌ No metadata event found in calendar '\(calendar.title)'")
            return nil
        }
        
        guard let notes = metadataEvent.notes,
              !notes.isEmpty,
              let decodedString = OptimizedInvisibleCoder.decode(from: notes) else {
            print("   ... ❌ Metadata event has no decodable notes.")
            return nil
        }
        
        let parts = decodedString.components(separatedBy: ":::")
        guard parts.count == 2, let profileUUID = UUID(uuidString: parts[0]) else {
            print("   ... ❌ Decoded string doesn't contain a valid UUID part.")
            return nil
        }
        
        let jsonString = parts[1]
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        
        do {
            let payload = try JSONDecoder().decode(ProfilePayload.self, from: jsonData)
            return (profileUUID, payload)
        } catch {
            print("   ... ❌ Error decoding ProfilePayload from JSON: \(error)")
            return nil
        }
    }
    
    @MainActor
    private func createOrUpdateMetadataEvent(for profile: Profile, in calendar: EKCalendar) async {
        print("   ... ✍️ Updating metadata event in calendar '\(calendar.title)'")
        
        let payload = ProfilePayload(from: profile)
        var invisiblePayload: String?
        do {
            let profileUUIDString = profile.id.uuidString
            let jsonData = try JSONEncoder().encode(payload)
            if let jsonString = String(data: jsonData, encoding: .utf8),
               let encodedPart = OptimizedInvisibleCoder.encode(from: "\(profileUUIDString):::\(jsonString)") {
                invisiblePayload = encodedPart
            }
        } catch {
            print("      ❗️ Failed to encode profile data: \(error)")
            return
        }
        
        guard let finalPayload = invisiblePayload else {
            print("      ❗️ Payload is nil, aborting metadata event update.")
            return
        }
        
        let searchDate = profileMetadataEventDate
        guard let oneDayAfter = Calendar.current.date(byAdding: .day, value: 1, to: searchDate) else { return }
        let predicate = eventStore.predicateForEvents(withStart: searchDate, end: oneDayAfter, calendars: [calendar])
        let existingEvents = eventStore.events(matching: predicate)
        
        let metadataEvent = existingEvents.first { $0.title == profileMetadataEventTitle } ?? EKEvent(eventStore: eventStore)
        
        if metadataEvent.eventIdentifier == nil {
            print("      ➕ Creating new metadata event.")
        } else {
            print("      🔄 Updating existing metadata event.")
        }
        
        metadataEvent.calendar = calendar
        metadataEvent.title = profileMetadataEventTitle
        metadataEvent.startDate = searchDate
        metadataEvent.endDate = searchDate.addingTimeInterval(3600)
        metadataEvent.isAllDay = true
        metadataEvent.notes = finalPayload
        
        do {
            try eventStore.save(metadataEvent, span: .thisEvent, commit: true)
            print("      ✅ Successfully saved metadata event.")
        } catch {
            print("      ❗️ Error saving metadata event: \(error.localizedDescription)")
        }
    }
    
    @discardableResult
    @MainActor
    func createOrUpdateShoppingListCalendar(for profile: Profile, context: ModelContext) async -> EKCalendar? {
        print("🛒 createOrUpdateShoppingListCalendar для \(profile.name)...")
        guard accessGranted else {
            print("   ❌ Нет разрешений на доступ к календарю.")
            return nil
        }
        
        if profile.hasSeparateStorage {
            if let calendarID = profile.shoppingListCalendarID, let existingCal = eventStore.calendar(withIdentifier: calendarID) {
                print("   ✅ Найден существующий ОТДЕЛЬНЫЙ календарь списка покупок: \(existingCal.title)")
                return existingCal
            }
            
            let calendarName = "\(profile.name) – Shopping List"
            print("   ➕ Создание нового ОТДЕЛЬНОГО календаря списка покупок: \(calendarName)")
            let newCal = createSystemCalendar(name: calendarName, color: .systemYellow)
            
            if let newCal = newCal {
                profile.shoppingListCalendarID = newCal.calendarIdentifier
            }
            return newCal
            
        } else {
            if let sharedCalID = UserDefaults.standard.string(forKey: sharedShoppingListCalendarIDKey),
               let existingSharedCal = eventStore.calendar(withIdentifier: sharedCalID) {
                print("   ✅ Найден существующий ОБЩИЙ календарь списка покупок: \(existingSharedCal.title)")
                return existingSharedCal
            }
            
            let calendarName = "Shared Shopping List – Wise Eating"
            print("   ➕ Создание нового ОБЩЕГО календаря списка покупок: \(calendarName)")
            let newSharedCal = createSystemCalendar(name: calendarName, color: .systemOrange)
            
            if let newSharedCal = newSharedCal {
                UserDefaults.standard.set(newSharedCal.calendarIdentifier, forKey: sharedShoppingListCalendarIDKey)
                print("   💾 ID нового ОБЩЕГО календаря списка покупок сохранен в UserDefaults.")
            }
            return newSharedCal
        }
    }
}
