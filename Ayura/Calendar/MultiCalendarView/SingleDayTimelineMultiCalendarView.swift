import UIKit
import EventKit
import SwiftUI
import Combine

public final class SingleDayTimelineMultiCalendarView: UIView, UIGestureRecognizerDelegate, @preconcurrency UIEditMenuInteractionDelegate {
    var highlightedSubColumn: (dayIndex: Int, calIndex: Int)? = nil
    private var editMenuInteraction: UIEditMenuInteraction?
    private var currentTappedDescriptor: EventDescriptor?
    // Цвят / стил на хайлайта (може да си го сложите в style, ако предпочитате)
    private let highlightFillColor =  UIColor.systemGray4.withAlphaComponent(0.5)
    
    private var isCurrentlyOverAllDay = false
    private let calendarVM = CalendarViewModel.shared
    private let effectManager = EffectManager.shared
    private var themeCancellables = Set<AnyCancellable>()
    private var sleepTextColor: UIColor = .label

    private var ghostEmptySpaceView: EventView?
    private var ghostEmptySpaceDescriptor: EventDescriptor?
    private struct GhostDragData {
        let initialFingerPoint: CGPoint
        let anchorOffsetX: CGFloat
        let anchorOffsetY: CGFloat
        let originalFrame: CGRect
    }
    
    // MARK: - Local DateFormatter (for debug prints)
    private static let localFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        df.timeZone = TimeZone.current
        return df
    }()
    
    // MARK: - Public Style / Config
    public var fromDate: Date = Date()
    public var style = TimelineStyle()
    var isFirstResize = false
    /// Top margin so drawing aligns with HoursColumnView lines
    public var topMargin: CGFloat = 0
    
    public var dayColumnWidth: CGFloat = 100
    public var hourHeight: CGFloat = 95

    public var sleepIntervals: [DateInterval] = [] {
        didSet { setNeedsDisplay() }
    }

    var recommendedSleep: AyurvedaSleepRecommendation? {
        didSet { setNeedsDisplay() }
    }
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (1/2) +++
    public var profile: Profile?
    // +++ КРАЙ НА ПРОМЯНАТА (1/2) +++
    
    // Hours column (for minute markers, etc.)
    public weak var hoursColumnView: HoursColumnView?
    
    // MARK: - Public Callbacks
    public var onEventTap: ((EventDescriptor) -> Void)?
    public var onEditMenuPresentationChanged: ((Bool) -> Void)?
    public var onEmptyLongPress: ((Date, EKCalendar?) -> Void)?
    public var onEventDragEnded: ((EventDescriptor, Date, Bool) -> Void)?
    public var onEventDragResizeEnded: ((EventDescriptor, Date) -> Void)?
    public var onEventConvertToAllDay: ((EventDescriptor, Int) -> Void)?
    public var onEventDeleted: ((EventDescriptor) -> Void)?
    public var onEventDuplicated: ((EventDescriptor) -> Void)?
    // MARK: - Events to Layout
    public var regularLayoutAttributes = [EventLayoutAttributes]() {
        didSet { setNeedsLayout() }
    }
    
    // Actual subviews for normal events
    private var eventViews: [EventView] = []
    private var eventViewToDescriptor: [EventView : EventDescriptor] = [:]
    
    // MARK: - Editing / Drag & Drop / Resize
    private var currentlyEditedEventViewID: String?
    
    // Ghosts during drag (one ghost per day slice)
    private var draggingGhosts: [EventView: EventView] = [:]
    private var draggingOriginalAlphas: [EventView: CGFloat] = [:]
    
    // Ключ за запазване на данни при drag
    private let DRAG_DATA_KEY = "DragDataKey"
    
    // MARK: - Auto-Scroll
    private var autoScrollDisplayLink: CADisplayLink?
    private var autoScrollDirection = CGPoint.zero
    
    // MARK: - Init
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setupLongPressForEmptySpace()
        setupTapOnEmptySpace()
        setupEditMenuInteraction()
        setupSleepThemeObservation()

    }
    
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        setupLongPressForEmptySpace()
        setupTapOnEmptySpace()
        setupEditMenuInteraction()
        setupSleepThemeObservation()
    }

    private func setupSleepThemeObservation() {
        effectManager.$currentGlobalAccentColor
            .receive(on: RunLoop.main)
            .sink { [weak self] color in
                self?.sleepTextColor = UIColor(color)
                self?.setNeedsDisplay()
            }
            .store(in: &themeCancellables)
    }
    
    private func setupEditMenuInteraction() {
           let interaction = UIEditMenuInteraction(delegate: self)
           self.addInteraction(interaction)
           self.editMenuInteraction = interaction
    }
       
    @objc private func handleEventViewTap(_ gesture: UITapGestureRecognizer) {
       guard
           let tappedView = gesture.view as? EventView,
           let descriptor = eventViewToDescriptor[tappedView],
           !isPracticeDescriptor(descriptor)
       else { return }
       
       self.currentTappedDescriptor = descriptor
       
       let location = gesture.location(in: self)
       let menuConfig = UIEditMenuConfiguration(identifier: nil, sourcePoint: location)
       editMenuInteraction?.presentEditMenu(with: menuConfig)
    }
    
    private func isTrainingEvent(_ event: EKEvent) -> Bool {
        guard let profile = self.profile else {
            return false
        }
        let eventTitle = event.title ?? ""
    
        if let notes = event.notes, let decoded = OptimizedInvisibleCoder.decode(from: notes) {
            if decoded.starts(with: "#TRAINING#") {
                return true
            }
        }
        
        if profile.trainings.contains(where: { $0.name == eventTitle }) {
            return true
        }
    
        if profile.meals.contains(where: { $0.name == eventTitle }) {
            return false
        }
        
        return false
    }
    
    public func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard let descriptor = currentTappedDescriptor,
              !isPracticeDescriptor(descriptor) else { return nil }
        
        var existingVideoURL: URL? = nil
        if let notes = (descriptor as? EKMultiDayWrapper)?.realEvent.notes {
            if let range = notes.range(of: "https://meet.google.com/") {
                let meetLink = String(notes[range.lowerBound...])
                if let url = URL(string: meetLink) {
                    existingVideoURL = url
                }
            }
            if existingVideoURL == nil, let range = notes.range(of: "https://teams.live.com/") {
                let teamsLink = String(notes[range.lowerBound...])
                if let url = URL(string: teamsLink) {
                    existingVideoURL = url
                }
            }
        }

        var children: [UIMenuElement] = []

        let editAction = UIAction(
            title: NSLocalizedString("Edit", comment: ""),
            image: UIImage(systemName: "square.and.pencil")
        ) { _ in
            guard let multi = descriptor as? EKMultiDayWrapper else { return }
            let ev = multi.realEvent
            
            if self.isTrainingEvent(ev) {
                let payload = EditNutritionPayload(
                    calendarID: ev.calendar.calendarIdentifier,
                    date: ev.startDate,
                    mealName: ev.title ?? ""
                )
                NotificationCenter.default.post(name: .editTrainingForEvent, object: payload)
            } else {
                let payload = EditNutritionPayload(
                    calendarID: ev.calendar.calendarIdentifier,
                    date: ev.startDate,
                    mealName: ev.title ?? ""
                )
                NotificationCenter.default.post(name: .editNutritionForEvent, object: payload)
            }
        }
        children.append(editAction)

        let duplicateAction = UIAction(
            title: NSLocalizedString("Copy to Calendar", comment: ""),
            image: UIImage(systemName: "doc.on.doc")
        ) { [weak self] _ in
            guard let self else { return }
            self.presentDuplicateDestinationPicker(for: descriptor)
        }
        children.append(duplicateAction)
        
        let copyToAction = UIAction(
            title: NSLocalizedString("Copy to another day", comment: "Context menu action to copy an event to another day"),
            image: UIImage(systemName: "doc.on.doc.fill")
        ) { [weak self] _ in
            guard let self, let descriptor = self.currentTappedDescriptor else { return }
            self.presentDayPickerForDuplication(for: descriptor)
        }
        children.append(copyToAction)

        let deleteAction = UIAction(
            title: NSLocalizedString("Delete", comment: ""),
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { action in
            self.deleteEventFromStore(descriptor)
            self.onEventDeleted?(descriptor)
        }
        children.append(deleteAction)
   
        return UIMenu(title: "", children: children)
    }
    
    @MainActor
    private func presentDayPickerForDuplication(for descriptor: EventDescriptor) {
        let datePickerVC = UIViewController()
        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .date
        if #available(iOS 14.0, *) {
            datePicker.preferredDatePickerStyle = .inline
        }
        datePicker.date = descriptor.dateInterval.start

        datePickerVC.view.addSubview(datePicker)
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            datePicker.leadingAnchor.constraint(equalTo: datePickerVC.view.leadingAnchor),
            datePicker.trailingAnchor.constraint(equalTo: datePickerVC.view.trailingAnchor),
            datePicker.topAnchor.constraint(equalTo: datePickerVC.view.topAnchor),
            datePicker.bottomAnchor.constraint(equalTo: datePickerVC.view.bottomAnchor)
        ])

        let alert = UIAlertController(
            title: NSLocalizedString("Copy Event to Day", comment: "Alert title for copying an event"),
            message: nil,
            preferredStyle: .actionSheet
        )

        alert.setValue(datePickerVC, forKey: "contentViewController")

        let copyAction = UIAlertAction(title: NSLocalizedString("Copy", comment: "Alert action to confirm copying"), style: .default) { [weak self] _ in
            guard let self = self else { return }
            let newDate = datePicker.date
            self.duplicateEventInStore(descriptor, toDate: newDate)
            self.onEventDuplicated?(descriptor)
        }
        alert.addAction(copyAction)

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action to cancel"), style: .cancel)
        alert.addAction(cancelAction)

        if let topVC = UIApplication.shared.topMostViewController {
            alert.popoverPresentationController?.sourceView = topVC.view
            alert.popoverPresentationController?.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            alert.popoverPresentationController?.permittedArrowDirections = []
            topVC.present(alert, animated: true)
        }
    }
    
    private func duplicateEventInStore(_ descriptor: EventDescriptor, toDate newSelectedDay: Date) {
        guard let multi = descriptor as? EKMultiDayWrapper else { return }
        let original = multi.realEvent
        let store = CalendarViewModel.shared.eventStore

        let newEv = EKEvent(eventStore: store)
        newEv.title = original.title
        newEv.isAllDay = original.isAllDay
        newEv.notes = original.notes
        newEv.location = original.location
        newEv.calendar = original.calendar

        let calendar = Calendar.current
        
        let originalStartComponents = calendar.dateComponents([.hour, .minute, .second], from: original.startDate)
        
        let newDayComponents = calendar.dateComponents([.year, .month, .day], from: newSelectedDay)

        var newStartComponents = newDayComponents
        newStartComponents.hour = originalStartComponents.hour
        newStartComponents.minute = originalStartComponents.minute
        newStartComponents.second = originalStartComponents.second

        guard let newStartDate = calendar.date(from: newStartComponents) else {
            print("Грешка: Не може да се създаде нова начална дата за копирането.")
            return
        }

        let duration = original.endDate.timeIntervalSince(original.startDate)
        let newEndDate = newStartDate.addingTimeInterval(duration)

        newEv.startDate = newStartDate
        newEv.endDate = newEndDate

        do {
            try store.save(newEv, span: .thisEvent, commit: true)
        } catch {
            print("Грешка при дублиране на събитие към нова дата: \(error.localizedDescription)")
        }
    }
    
    private func deleteEventFromStore(_ descriptor: EventDescriptor) {
        guard let multi = descriptor as? EKMultiDayWrapper else { return }
        let realEv = multi.realEvent
        let store = CalendarViewModel.shared.eventStore
        do {
            try store.remove(realEv, span: .thisEvent, commit: true)
        } catch {
            print("Error:", error)
        }
    }

    private func duplicateEventInStore(_ descriptor: EventDescriptor) {
        guard let multi = descriptor as? EKMultiDayWrapper else { return }
        let original = multi.realEvent
        let store = CalendarViewModel.shared.eventStore
        
        let newEv = EKEvent(eventStore: store)
        newEv.title = original.title
        newEv.startDate = original.startDate
        newEv.endDate   = original.endDate
        newEv.isAllDay  = original.isAllDay
        newEv.notes     = original.notes
        newEv.location  = original.location
        newEv.calendar  = original.calendar
        
        do {
            try store.save(newEv, span: .thisEvent, commit: true)
        } catch {
            print("Error duplicating:", error)
        }
    }
    
    private func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            willPresentEditMenuWith configuration: UIEditMenuConfiguration,
            animator: UIEditMenuInteractionAnimating
        ) {
            onEditMenuPresentationChanged?(true)
        }
        
    private func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            willDismissEditMenuWith configuration: UIEditMenuConfiguration,
            animator: UIEditMenuInteractionAnimating
        ) {
            onEditMenuPresentationChanged?(false)
        }
    
    private func setupTapOnEmptySpace() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapOnEmptySpace(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)
    }
    
    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let eventView = gestureRecognizer.view as? EventView,
           let descriptor = eventViewToDescriptor[eventView],
           isPracticeDescriptor(descriptor) {
            return false
        }
        return true
    }

    private func isPracticeDescriptor(_ descriptor: EventDescriptor) -> Bool {
        guard let wrapper = descriptor as? EKMultiDayWrapper else { return false }
        return PracticeCalendarEvent.isPractice(wrapper.realEvent)
    }
    
    @objc private func handleTapOnEmptySpace(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        let point = gesture.location(in: self)
        for evView in eventViews {
            if !evView.isHidden && evView.frame.contains(point) {
                return
            }
        }

        for (view, _) in eventViewToDescriptor {
            view.eventResizeHandles[0].isHidden = true
            view.eventResizeHandles[1].isHidden = true
        }
        currentlyEditedEventViewID = ""

        for evView in eventViews {
            guard let gestures = evView.gestureRecognizers else { continue }
            for g in gestures {
                if let longPress = g as? UILongPressGestureRecognizer {
                    longPress.minimumPressDuration = 0.2
                }
            }
        }

        hoursColumnView?.selectedMinuteMark = nil
        hoursColumnView?.setNeedsDisplay()
    }
    
    // MARK: - Layout
    public override func layoutSubviews() {
        super.layoutSubviews()
        for v in eventViews {
            v.isHidden = true
        }
        layoutRegularEvents()
    }
    
    var dayCount: Int = 1
    
    private func layoutRegularEvents() {
        for v in eventViews {
            v.isHidden = true
        }
        
        let allCals = calendarVM.calendarsDict
        let selectedCals = allCals.filter { $0.value.selected }
        let calsToShow = selectedCals.isEmpty ? Array(allCals.values) : Array(selectedCals.values)
        let sortedCals = calsToShow.sorted { $0.title < $1.title }
        
        let numberOfSubcolumns = max(1, sortedCals.count)
        let subColumnWidth = (dayColumnWidth / CGFloat(numberOfSubcolumns))
        
        let grouped = Dictionary(grouping: regularLayoutAttributes) { dayIndexFor($0.descriptor.dateInterval.start) }
        
        var usedEventViewIndex = 0
        
        for dayIndex in 0 ..< dayCount {
            guard let eventsForDay = grouped[dayIndex], !eventsForDay.isEmpty else { continue }
            
            for attr in eventsForDay {
                let calID = attr.descriptor.calendarID ?? ""
                let subIndex: Int = sortedCals.firstIndex(where: { $0.calendar.calendarIdentifier == calID }) ?? 0
                
                let dayStart = dayStartDate(for: dayIndex)
                guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else { continue }

                let eventStart = attr.descriptor.dateInterval.start
                let eventEnd = attr.descriptor.dateInterval.end
                
                let visibleStart = max(eventStart, dayStart)
                let visibleEnd = min(eventEnd, dayEnd)

                let yStart = topMargin + dateToY(visibleStart)
                
                var yEnd: CGFloat
                if Calendar.current.isDate(visibleEnd, inSameDayAs: dayStart) {
                    yEnd = topMargin + dateToY(visibleEnd)
                } else {
                    yEnd = topMargin + hourHeight * 24
                }
                
                let xPos = CGFloat(dayIndex) * dayColumnWidth + subColumnWidth * CGFloat(subIndex)
                
                let gap: CGFloat = style.eventGap
                
                let finalX = xPos + gap
                let finalW = subColumnWidth - 2 * gap
                let finalY = yStart + gap
                let naturalHeight = max(1, (yEnd - yStart) - 2 * gap)
                let isPracticeEvent = (attr.descriptor as? EKMultiDayWrapper)
                    .map { PracticeCalendarEvent.isPractice($0.realEvent) } ?? false
                let minimumHeight: CGFloat = isPracticeEvent ? 44 : 1
                let remainingDayHeight = max(1, topMargin + hourHeight * 24 - finalY)
                let finalH = min(max(minimumHeight, naturalHeight), remainingDayHeight)
                
                let evView = ensureEventView(index: usedEventViewIndex)
                usedEventViewIndex += 1
                
                evView.isHidden = false
                evView.frame = CGRect(x: finalX, y: finalY, width: finalW, height: finalH)
                
                evView.updateWithDescriptor(event: attr.descriptor)
                eventViewToDescriptor[evView] = attr.descriptor
                if isPracticeEvent {
                    evView.eventResizeHandles.forEach { $0.isHidden = true }
                }
                if let multi = attr.descriptor as? EKMultiDayWrapper,
                   !isPracticeEvent {
                    var isCurrentlyEditedEventView = false
                    if currentlyEditedEventViewID == multi.realEvent.eventIdentifier {
                        isCurrentlyEditedEventView = true
                    }
                    if isCurrentlyEditedEventView {
                        let firstDayIndex = dayIndexFor(multi.realEvent.startDate)
                        let lastDayIndex  = dayIndexFor(multi.realEvent.endDate ?? multi.realEvent.startDate)
                        
                        if firstDayIndex == lastDayIndex {
                            evView.eventResizeHandles[0].isHidden = false
                            evView.eventResizeHandles[1].isHidden = false
                        } else if dayIndex == firstDayIndex {
                            evView.eventResizeHandles[0].isHidden = false
                            evView.eventResizeHandles[1].isHidden = true
                        } else if dayIndex == lastDayIndex {
                            evView.eventResizeHandles[0].isHidden = true
                            evView.eventResizeHandles[1].isHidden = false
                        }
                    }
                }
            }
        }
    }

    private func ensureEventView(index: Int) -> EventView {
        if index < eventViews.count {
            return eventViews[index]
        } else {
            let v = createEventView()
            eventViews.append(v)
            return v
        }
    }
    
    private func createEventView() -> EventView {
        let ev = EventView()
        
        // +++ НАЧАЛО НА ПРОМЯНАТА (2/2) +++
        // Предаваме профила на всяка новосъздадена EventView
        ev.profile = self.profile
        // +++ КРАЙ НА ПРОМЯНАТА (2/2) +++
        
        let tapGR = UITapGestureRecognizer(target: self, action: #selector(handleEventViewTap(_:)))
        tapGR.delegate = self
        ev.addGestureRecognizer(tapGR)
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleEventViewPan(_:)))
        lp.minimumPressDuration = 0.2
        lp.delegate = self
        ev.addGestureRecognizer(lp)
        ev.isUserInteractionEnabled = true
        addSubview(ev)
        return ev
    }
    
    private struct DragData {
        let totalDuration: TimeInterval
        let originalContainerFrame: CGRect
        let anchorOffsetX: CGFloat
        let anchorOffsetY: CGFloat
        let originalStart: Date
    }
    
    private func removeGhostsForDescriptor(_ descriptor: EventDescriptor) {
        let pairsToRemove = draggingGhosts.filter { (originalView, ghostView) in
            if let d = eventViewToDescriptor[originalView] {
                return d === descriptor
            }
            return false
        }
        for (originalView, ghostView) in pairsToRemove {
            ghostView.removeFromSuperview()
            draggingGhosts.removeValue(forKey: originalView)
            if let oldAlpha = draggingOriginalAlphas[originalView] {
                originalView.alpha = oldAlpha
                draggingOriginalAlphas.removeValue(forKey: originalView)
            }
        }
    }
    
    @objc private func handleEventViewPan(_ gesture: UILongPressGestureRecognizer) {
        guard let evView = gesture.view as? EventView,
              let descriptor = eventViewToDescriptor[evView],
              !isPracticeDescriptor(descriptor) else { return }

        switch gesture.state {
        case .began:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isFirstResize = false
            removeGhostsForDescriptor(descriptor)

            if evView.layer.value(forKey: DRAG_DATA_KEY) != nil { return }
            setScrollsClipping(enabled: false)

            // 1. Взимаме реалните начална и крайна дата на ЦЯЛОТО събитие
            let realStart = (descriptor as? EKMultiDayWrapper)?.realEvent.startDate ?? descriptor.dateInterval.start
            let realEnd   = (descriptor as? EKMultiDayWrapper)?.realEvent.endDate ?? descriptor.dateInterval.end
            let totalDuration = realEnd.timeIntervalSince(realStart)
            
            let totalHeightInPoints = CGFloat(totalDuration / 3600) * hourHeight

            guard let container = superview?.superview as? TwoWayPinnedSingleDayMultiCalendarContainerView else { return }
            let finger = gesture.location(in: container)

            // Скриваме всички парчета на събитието
            var slicesToHide: [EventView] = []
            if let multi = descriptor as? EKMultiDayWrapper, let id = multi.realEvent.eventIdentifier {
                 slicesToHide = eventViewToDescriptor.compactMap { (view, d) -> EventView? in
                    (d as? EKMultiDayWrapper)?.realEvent.eventIdentifier == id ? view : nil
                }
            } else {
                slicesToHide = [evView]
            }
            
            draggingGhosts.removeAll()
            draggingOriginalAlphas.removeAll()
            
            for slice in slicesToHide {
                draggingOriginalAlphas[slice] = slice.alpha
                slice.alpha = 0
            }
            
            // ----- 👇 НАЧАЛО НА КОРЕКЦИЯТА 👇 -----
            let originalTappedFrameInContainer = container.convert(evView.frame, from: self)

            // Изчисляваме колко време (в секунди) от събитието е минало ПРЕДИ началото на текущия ден.
            let dayStart = Calendar.current.startOfDay(for: fromDate)
            let timeBeforeToday = max(0, dayStart.timeIntervalSince(realStart))
            
            // Преобразуваме това време в пиксели
            let yOffsetForPastTime = CGFloat(timeBeforeToday / 3600) * hourHeight

            // Създаваме рамката на призрака, като я преместваме нагоре с изчисления офсет
            let ghostFrame = CGRect(
                x: originalTappedFrameInContainer.origin.x,
                y: originalTappedFrameInContainer.origin.y - yOffsetForPastTime, // <-- ТОВА Е КЛЮЧЪТ
                width: originalTappedFrameInContainer.width,
                height: totalHeightInPoints - (style.eventGap * 2)
            )
            // ----- 👆 КРАЙ НА КОРЕКЦИЯТА 👆 -----

            let ghost = createEventView()
            ghost.updateWithDescriptor(event: descriptor)
            ghost.frame = ghostFrame
            ghost.layer.zPosition = 2
            container.addSubview(ghost)
            
            draggingGhosts[evView] = ghost
            
            let offsetX = finger.x - ghostFrame.minX
            let offsetY = finger.y - ghostFrame.minY

            let dragData = DragData(
                totalDuration: totalDuration,
                originalContainerFrame: ghostFrame,
                anchorOffsetX: offsetX,
                anchorOffsetY: offsetY,
                originalStart: realStart
            )
            evView.layer.setValue(dragData, forKey: DRAG_DATA_KEY)

        case .changed:
            guard
                let d = evView.layer.value(forKey: DRAG_DATA_KEY) as? DragData,
                let ghost = draggingGhosts[evView],
                let container = superview?.superview as? TwoWayPinnedSingleDayMultiCalendarContainerView
            else { return }

            let finger = gesture.location(in: container)
            let rawTopY = finger.y - d.anchorOffsetY
            
            ghost.frame.origin.y = rawTopY
            
            let frameInSelf = container.convert(ghost.frame, to: self)
            if let rawDate = dateFromFrame(frameInSelf) {
                let snappedDate = snapToNearest10Min(rawDate)
                setSingle10MinuteMarkFromDate(snappedDate)
            }

            updateAutoScrollDirection(for: gesture)

        case .ended, .cancelled:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            setScrollsClipping(enabled: true)
            stopAutoScroll()
            hoursColumnView?.selectedMinuteMark = nil

            guard let d = evView.layer.value(forKey: DRAG_DATA_KEY) as? DragData,
                  let ghost = draggingGhosts[evView],
                  let container = superview?.superview as? TwoWayPinnedSingleDayMultiCalendarContainerView else {
                cleanupAfterDrag(for: evView)
                return
            }

            let finalFrame = container.convert(ghost.frame, to: self)
            let dayIdx     = dayIndexForFrame(finalFrame) ?? 0
            let hourOff    = (finalFrame.minY - topMargin) / hourHeight
            let dayDate    = dayStartDate(for: dayIdx)
            let newStart   = snapToNearest10Min(dayDate.addingTimeInterval(hourOff * 3600))
            
            descriptor.dateInterval = DateInterval(start: newStart, duration: d.totalDuration)
            onEventDragEnded?(descriptor, newStart, false)

            cleanupAfterDrag(for: evView)

        default: break
        }
    }

    private func cleanupAfterDrag(for mainView: EventView) {
        if let ghost = draggingGhosts[mainView] {
            ghost.removeFromSuperview()
            draggingGhosts.removeValue(forKey: mainView)
        }
        
        for (slice, alpha) in draggingOriginalAlphas {
            slice.alpha = alpha
        }
        draggingOriginalAlphas.removeAll()

        mainView.layer.setValue(nil, forKey: DRAG_DATA_KEY)
        highlightedSubColumn = nil
    }
    
    private func dayIndexFor(_ date: Date) -> Int {
        let cal = Calendar.current
        let startOnly = cal.startOfDay(for: fromDate)
        let dateOnly = cal.startOfDay(for: date)
        let comps = cal.dateComponents([.day], from: startOnly, to: dateOnly)
        return comps.day ?? 0
    }
    
    func dayStartDate(for dayIndex: Int) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: fromDate)
        return cal.date(byAdding: .day, value: dayIndex, to: start) ?? start
    }
    
    override public func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let totalWidth = dayColumnWidth * CGFloat(dayCount)

        drawSleepHighlights(in: ctx)
        
        ctx.saveGState()
        ctx.setStrokeColor(style.separatorColor.cgColor)
        ctx.setLineWidth(1.0 / UIScreen.main.scale)
        ctx.beginPath()

        var lastY: CGFloat = 0
        for hour in 0...24 {
            let y = topMargin + CGFloat(hour) * hourHeight
            lastY = y
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: totalWidth, y: y))
        }
        ctx.strokePath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setStrokeColor(style.separatorColor.cgColor)
        ctx.setLineWidth(1.0 / UIScreen.main.scale)
        ctx.beginPath()

        ctx.move(to: CGPoint(x: 0, y: 0))
        ctx.addLine(to: CGPoint(x: 0, y: bounds.height))

        for i in 0...dayCount {
            let colX = CGFloat(i) * dayColumnWidth
            ctx.move(to: CGPoint(x: colX, y: 0))
            ctx.addLine(to: CGPoint(x: colX, y: lastY))
        }
        ctx.strokePath()
        ctx.restoreGState()

        let allCals = calendarVM.calendarsDict
        let selectedCals = allCals.filter { $0.value.selected }
        let calsToShow = selectedCals.isEmpty ? allCals : selectedCals
        let numberOfCalendars = calsToShow.count
        if numberOfCalendars > 0 {
            ctx.saveGState()
            ctx.setStrokeColor(style.separatorColor.cgColor)
            ctx.setLineWidth(1.0 / UIScreen.main.scale)
            ctx.beginPath()

            let subColumnWidth = dayColumnWidth / CGFloat(numberOfCalendars)

            for dayIndex in 0..<dayCount {
                let dayX = CGFloat(dayIndex) * dayColumnWidth
                for calIndex in 1..<numberOfCalendars {
                    let xPos = dayX + subColumnWidth * CGFloat(calIndex)
                    ctx.move(to: CGPoint(x: xPos, y: 0))
                    ctx.addLine(to: CGPoint(x: xPos, y: lastY))
                }
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
     
        if let (dayIndex, subIndex) = highlightedSubColumn {
            let subColumnCount = max(numberOfCalendars, 1)
            let subColumnWidth = dayColumnWidth / CGFloat(subColumnCount)

            if dayIndex >= 0, dayIndex < dayCount, subIndex >= 0, subIndex < subColumnCount {
                let xPos = CGFloat(dayIndex) * dayColumnWidth + CGFloat(subIndex) * subColumnWidth
                let highlightRect = CGRect(x: xPos, y: 0, width: subColumnWidth, height: bounds.height)
                ctx.saveGState()
                ctx.setFillColor(highlightFillColor.cgColor)
                ctx.fill(highlightRect)
                ctx.restoreGState()
            }
        }

        let now = Date()
        let cal = Calendar.current
        let dayIndexNow = dayIndexFor(now)

        if dayIndexNow >= 0 && dayIndexNow < dayCount {
            let hour = CGFloat(cal.component(.hour,   from: now))
            let min  = CGFloat(cal.component(.minute, from: now))
            let fraction = hour + min / 60.0
            let yNow = topMargin + fraction * hourHeight

            ctx.saveGState()
            ctx.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(1.5)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: yNow))
            ctx.addLine(to: CGPoint(x: totalWidth, y: yNow))
            ctx.strokePath()
            ctx.restoreGState()

            let currentDayX1 = CGFloat(dayIndexNow) * dayColumnWidth
            let currentDayX2 = currentDayX1 + dayColumnWidth

            ctx.saveGState()
            ctx.setStrokeColor(UIColor.systemRed.cgColor)
            ctx.setLineWidth(1.5)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: currentDayX1, y: yNow))
            ctx.addLine(to: CGPoint(x: currentDayX2, y: yNow))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    private enum SleepHighlightKind {
        case recorded
        case recommended
        case covered
        case missed

        var color: UIColor {
            switch self {
            case .recorded: .systemIndigo
            case .recommended: .systemGray
            case .covered: .systemGreen
            case .missed: .systemRed
            }
        }
    }

    private func drawSleepHighlights(in context: CGContext) {
        let calendar = Calendar.current
        let now = Date()

        for dayIndex in 0..<dayCount {
            let dayStart = dayStartDate(for: dayIndex)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }

            for interval in sleepIntervals where interval.start < dayEnd && interval.end > dayStart {
                drawSleepInterval(
                    DateInterval(
                        start: max(interval.start, dayStart),
                        end: min(interval.end, dayEnd)
                    ),
                    kind: .recorded,
                    dayIndex: dayIndex,
                    dayEnd: dayEnd,
                    in: context
                )
            }

            guard let recommendedSleep else { continue }
            let recommendedIntervals = recommendedSleep.visibleIntervals(
                on: dayStart,
                calendar: calendar
            )

            for recommendedInterval in recommendedIntervals {
                var coveredIntervals: [DateInterval] = []
                let elapsedEnd = min(recommendedInterval.end, now)
                if recommendedInterval.start < elapsedEnd {
                    let elapsed = DateInterval(
                        start: recommendedInterval.start,
                        end: elapsedEnd
                    )
                    coveredIntervals = intersections(
                        between: elapsed,
                        and: sleepIntervals
                    )
                    var cursor = elapsed.start
                    for coveredInterval in coveredIntervals {
                        if cursor < coveredInterval.start {
                            drawSleepInterval(
                                DateInterval(start: cursor, end: coveredInterval.start),
                                kind: .missed,
                                dayIndex: dayIndex,
                                dayEnd: dayEnd,
                                in: context
                            )
                        }
                        drawSleepInterval(
                            coveredInterval,
                            kind: .covered,
                            dayIndex: dayIndex,
                            dayEnd: dayEnd,
                            in: context
                        )
                        drawMatchedSleepLabel(
                            in: coveredInterval,
                            recommendationStart: recommendedInterval.start,
                            dayIndex: dayIndex,
                            dayEnd: dayEnd
                        )
                        cursor = max(cursor, coveredInterval.end)
                    }
                    if cursor < elapsed.end {
                        drawSleepInterval(
                            DateInterval(start: cursor, end: elapsed.end),
                            kind: .missed,
                            dayIndex: dayIndex,
                            dayEnd: dayEnd,
                            in: context
                        )
                    }
                }

                let futureStart = max(recommendedInterval.start, now)
                if futureStart < recommendedInterval.end {
                    drawSleepInterval(
                        DateInterval(
                            start: futureStart,
                            end: recommendedInterval.end
                        ),
                        kind: .recommended,
                        dayIndex: dayIndex,
                        dayEnd: dayEnd,
                        in: context
                    )
                }

                drawRecommendedSleepLabel(
                    in: recommendedInterval,
                    timeRange: recommendedSleep.timeRangeLabel,
                    healthKitIntervals: healthKitIntervals(
                        relatedTo: recommendedInterval
                    ),
                    coveredIntervals: coveredIntervals,
                    showMissingHealthKitMessage: recommendedInterval.end <= now,
                    dayIndex: dayIndex,
                    dayEnd: dayEnd
                )
            }
        }
    }

    private func intersections(
        between interval: DateInterval,
        and candidates: [DateInterval]
    ) -> [DateInterval] {
        candidates.compactMap { candidate in
            let start = max(interval.start, candidate.start)
            let end = min(interval.end, candidate.end)
            guard start < end else { return nil }
            return DateInterval(start: start, end: end)
        }.sorted { $0.start < $1.start }
    }

    private func healthKitIntervals(
        relatedTo recommendedInterval: DateInterval
    ) -> [DateInterval] {
        let comparisonWindow = DateInterval(
            start: recommendedInterval.start.addingTimeInterval(-4 * 60 * 60),
            end: recommendedInterval.end.addingTimeInterval(4 * 60 * 60)
        )
        return sleepIntervals.filter { sleepInterval in
            sleepInterval.start < comparisonWindow.end
                && sleepInterval.end > comparisonWindow.start
        }
    }

    private func drawSleepInterval(
        _ interval: DateInterval,
        kind: SleepHighlightKind,
        dayIndex: Int,
        dayEnd: Date,
        in context: CGContext
    ) {
        guard interval.start < interval.end else { return }
        let rect = sleepHighlightRect(
            for: interval,
            dayIndex: dayIndex,
            dayEnd: dayEnd
        )
        guard !rect.isEmpty else { return }

        let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        let color = kind.color

        context.saveGState()
        context.setFillColor(color.withAlphaComponent(0.13).cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        context.setStrokeColor(color.withAlphaComponent(0.34).cgColor)
        context.setLineWidth(1)
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
    }

    private func sleepHighlightRect(
        for interval: DateInterval,
        dayIndex: Int,
        dayEnd: Date
    ) -> CGRect {
        let yStart = topMargin + dateToY(interval.start)
        let yEnd = interval.end == dayEnd
            ? topMargin + hourHeight * 24
            : topMargin + dateToY(interval.end)
        return CGRect(
            x: CGFloat(dayIndex) * dayColumnWidth + 2,
            y: yStart,
            width: max(0, dayColumnWidth - 4),
            height: max(1, yEnd - yStart)
        )
    }

    private func drawMatchedSleepLabel(
        in interval: DateInterval,
        recommendationStart: Date,
        dayIndex: Int,
        dayEnd: Date
    ) {
        let rect = sleepHighlightRect(
            for: interval,
            dayIndex: dayIndex,
            dayEnd: dayEnd
        )
        let recommendationY = topMargin + dateToY(recommendationStart)
        guard rect.height >= 24,
              rect.minY - recommendationY >= 58 else {
            return
        }

        let matchedLabel = NSLocalizedString(
            "Matched",
            comment: "Calendar recommended and recorded sleep overlap label"
        )
        let text = "✓  \(matchedLabel)  \(clockRange(from: interval.start, to: interval.end))  ·  \(durationLabel(interval.duration))"
        NSString(string: text).draw(
            in: CGRect(
                x: rect.minX + 8,
                y: rect.minY + 6,
                width: max(0, rect.width - 16),
                height: 17
            ),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: sleepTextColor.withAlphaComponent(0.95)
            ]
        )
    }

    private func drawRecommendedSleepLabel(
        in interval: DateInterval,
        timeRange: String,
        healthKitIntervals: [DateInterval],
        coveredIntervals: [DateInterval],
        showMissingHealthKitMessage: Bool,
        dayIndex: Int,
        dayEnd: Date
    ) {
        let rect = sleepHighlightRect(
            for: interval,
            dayIndex: dayIndex,
            dayEnd: dayEnd
        )
        guard rect.height >= 26, rect.width >= 120 else { return }

        let recommendedLabel = NSLocalizedString(
            "Recommended sleep",
            comment: "Calendar recommended sleep highlight label"
        )
        var lines: [(text: String, color: UIColor)] = [
            (
                "☾  \(recommendedLabel)  \(timeRange)",
                sleepTextColor.withAlphaComponent(0.95)
            )
        ]

        if !healthKitIntervals.isEmpty {
            let firstStart = healthKitIntervals.map(\.start).min() ?? interval.start
            let lastEnd = healthKitIntervals.map(\.end).max() ?? interval.end
            let duration = healthKitIntervals.reduce(0) {
                $0 + $1.duration
            }
            let healthKitLabel = NSLocalizedString(
                "HealthKit sleep",
                comment: "Calendar recorded sleep summary label"
            )
            lines.append((
                "♥  \(healthKitLabel)  \(clockRange(from: firstStart, to: lastEnd))  ·  \(durationLabel(duration))",
                sleepTextColor.withAlphaComponent(0.95)
            ))
        } else if showMissingHealthKitMessage {
            let missingLabel = NSLocalizedString(
                "No HealthKit sleep data for this night",
                comment: "Calendar missing recorded sleep message"
            )
            lines.append((
                "!  \(missingLabel)",
                sleepTextColor.withAlphaComponent(0.95)
            ))
        }

        if !coveredIntervals.isEmpty {
            let duration = coveredIntervals.reduce(0) {
                $0 + $1.duration
            }
            let matchedLabel = NSLocalizedString(
                "Matched",
                comment: "Calendar recommended and recorded sleep overlap label"
            )
            lines.append((
                "✓  \(matchedLabel)  \(intervalRangesLabel(coveredIntervals))  ·  \(durationLabel(duration))",
                sleepTextColor.withAlphaComponent(0.95)
            ))
        }

        let lineHeight: CGFloat = 17
        let availableLineCount = max(
            1,
            min(lines.count, Int((rect.height - 8) / lineHeight))
        )
        let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        for (index, line) in lines.prefix(availableLineCount).enumerated() {
            let lineRect = CGRect(
                x: rect.minX + 8,
                y: rect.minY + 6 + CGFloat(index) * lineHeight,
                width: max(0, rect.width - 16),
                height: lineHeight
            )
            NSString(string: line.text).draw(
                in: lineRect,
                withAttributes: [
                    .font: font,
                    .foregroundColor: line.color
                ]
            )
        }
    }

    private func clockRange(from start: Date, to end: Date) -> String {
        "\(clockLabel(start))–\(clockLabel(end))"
    }

    private func intervalRangesLabel(_ intervals: [DateInterval]) -> String {
        let ranges = intervals.prefix(2).map {
            clockRange(from: $0.start, to: $0.end)
        }
        let remainingCount = max(0, intervals.count - ranges.count)
        let suffix = remainingCount > 0 ? " +\(remainingCount)" : ""
        return ranges.joined(separator: ", ") + suffix
    }

    private func clockLabel(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(
            format: "%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int((duration / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes)m"
        }
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }
    
    private func dateToY(_ date: Date) -> CGFloat {
        let cal = Calendar.current
        let hour = CGFloat(cal.component(.hour, from: date))
        let minute = CGFloat(cal.component(.minute, from: date))
        return hourHeight * (hour + minute/60.0)
    }
    
    private func setSingle10MinuteMarkFromDate(_ date: Date) {
        guard let hoursView = hoursColumnView else { return }
        
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        guard let hour = comps.hour, let minute = comps.minute else {
            hoursView.selectedMinuteMark = nil
            hoursView.setNeedsDisplay()
            return
        }
        if minute == 0 {
            hoursView.selectedMinuteMark = nil
            hoursView.setNeedsDisplay()
            return
        }
        let remainder = minute % 10
        var closest10 = minute
        if remainder < 5 {
            closest10 = minute - remainder
        } else {
            closest10 = minute + (10 - remainder)
            if closest10 == 60 {
                hoursView.selectedMinuteMark = nil
                hoursView.setNeedsDisplay()
                return
            }
        }
        hoursView.selectedMinuteMark = (hour, closest10)
        hoursView.setNeedsDisplay()
    }
    
    private func snapToNearest10Min(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let y = comps.year, let mo = comps.month, let d = comps.day,
              let h = comps.hour, let m = comps.minute else {
            return date
        }
        if m == 0 { return date }
        
        let remainder = m % 10
        var finalM = m
        if remainder < 5 {
            finalM = m - remainder
        } else {
            finalM = m + (10 - remainder)
            if finalM == 60 {
                finalM = 0
                let plusHour = (h + 1) % 24
                var nextDayComps = DateComponents(year: y, month: mo, day: d, hour: plusHour, minute: 0)
                if plusHour == 0 {
                    if let nextDayDate = cal.date(byAdding: .day, value: 1, to: date) {
                        nextDayComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: nextDayDate)
                    }
                }
                return cal.date(from: nextDayComps) ?? date
            }
        }
        var comps2 = DateComponents()
        comps2.year = y
        comps2.month = mo
        comps2.day = d
        comps2.hour = h
        comps2.minute = finalM
        comps2.second = 0
        return cal.date(from: comps2) ?? date
    }
    
    // ----- 👇 НАЧАЛО НА КОРЕКЦИЯТА 👇 -----
    func dateFromPoint(_ point: CGPoint) -> Date? {
        let localY = point.y - topMargin
        if point.x < 0 { return nil }
        let dayIndex = Int(point.x / dayColumnWidth)
        if dayIndex < 0 || dayIndex >= dayCount { return nil }
        
        let cal = Calendar.current
        if let dayDate = cal.date(byAdding: .day, value: dayIndex, to: cal.startOfDay(for: fromDate)) {
            return timeToDate(dayDate: dayDate, verticalOffset: localY)
        }
        return nil
    }
    
    private func timeToDate(dayDate: Date, verticalOffset: CGFloat) -> Date? {
        let hoursFloat = verticalOffset / hourHeight
        let hour = floor(hoursFloat)
        let minuteFloat = (hoursFloat - hour) * 60
        let minute = floor(minuteFloat)
        
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: dayDate)
        comps.hour = Int(hour)
        comps.minute = Int(minute)
        comps.second = 0
        return cal.date(from: comps)
    }
    
    func dateFromFrame(_ frame: CGRect) -> Date? {
        let topY = frame.minY - topMargin
        let midX = frame.midX
        if midX < 0 { return nil }
        let dayIndex = Int(midX / dayColumnWidth)
        if dayIndex < 0 || dayIndex >= dayCount { return nil }
        
        let cal = Calendar.current
        if let dayDate = cal.date(byAdding: .day, value: dayIndex, to: cal.startOfDay(for: fromDate)) {
            return timeToDate(dayDate: dayDate, verticalOffset: topY)
        }
        return nil
    }
    // ----- 👆 КРАЙ НА КОРЕКЦИЯТА 👆 -----
    
    private func setScrollsClipping(enabled: Bool) {}
    
    private func updateAutoScrollDirection(for gesture: UILongPressGestureRecognizer) {
        guard let container = self.superview?.superview as? TwoWayPinnedSingleDayMultiCalendarContainerView else { return }
        let location = gesture.location(in: container)
        let threshold: CGFloat = 50
        var direction = CGPoint.zero
        
        let scrollFrame = container.mainScrollView.frame
        
        if location.x < scrollFrame.minX + threshold {
            direction.x = -1
        } else if location.x > scrollFrame.maxX - threshold {
            direction.x = 1
        }
        
        if location.y < scrollFrame.minY + threshold {
            direction.y = -1
        } else if location.y > scrollFrame.maxY - (threshold + 50) {
            direction.y = 1
        }
        
        autoScrollDirection = direction
        if direction != .zero {
            startAutoScrollIfNeeded()
        } else {
            stopAutoScroll()
        }
    }
    
    private func startAutoScrollIfNeeded() {
        if autoScrollDisplayLink == nil {
            autoScrollDisplayLink = CADisplayLink(target: self, selector: #selector(handleAutoScroll))
            autoScrollDisplayLink?.add(to: .main, forMode: .common)
        }
    }
    
    private func stopAutoScroll() {
        autoScrollDisplayLink?.invalidate()
        autoScrollDisplayLink = nil
    }
    
    @objc private func handleAutoScroll() {
        guard autoScrollDirection != .zero,
              let container = self.superview?.superview as? TwoWayPinnedSingleDayMultiCalendarContainerView else { return }
        
        let scrollView = container.mainScrollView
        let scrollSpeed: CGFloat = 5
        var newOffset = scrollView.contentOffset
        
        newOffset.x += autoScrollDirection.x * scrollSpeed
        newOffset.y += autoScrollDirection.y * scrollSpeed
        
        newOffset.x = max(0, min(newOffset.x, scrollView.contentSize.width - scrollView.bounds.width))
        newOffset.y = max(0, min(newOffset.y, scrollView.contentSize.height - scrollView.bounds.height))
        
        scrollView.setContentOffset(newOffset, animated: false)
    }
    
    private func dayIndexForFrame(_ frame: CGRect) -> Int? {
        let midX = frame.midX
        let rawIndex = midX / dayColumnWidth
        let i = Int(floor(rawIndex))
        if i < 0 { return nil }
        return i
    }
    
    @MainActor
    private func presentDuplicateDestinationPicker(for descriptor: EventDescriptor) {
        guard let multi = descriptor as? EKMultiDayWrapper else { return }
        let sourceCalendar = multi.realEvent.calendar
        let vm = CalendarViewModel.shared
        let targets = vm.allowedCalendars().filter { $0.calendarIdentifier != sourceCalendar!.calendarIdentifier }

        guard !targets.isEmpty else {
            duplicateEventInStore(descriptor, to: nil)
            onEventDuplicated?(descriptor)
            return
        }

        let alert = UIAlertController(title: NSLocalizedString("Copy to calendar", comment: ""), message: nil, preferredStyle: .actionSheet)

        for cal in targets {
            let title = cal.title
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                self.duplicateEventInStore(descriptor, to: cal)
                self.onEventDuplicated?(descriptor)
            })
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))

        if let top = UIApplication.shared.topMostViewController {
            alert.popoverPresentationController?.sourceView = top.view
            top.present(alert, animated: true)
        }
    }
    
    private func duplicateEventInStore(_ descriptor: EventDescriptor, to destCalendar: EKCalendar? = nil) {
        guard let multi = descriptor as? EKMultiDayWrapper else { return }
        let original = multi.realEvent
        let store = CalendarViewModel.shared.eventStore

        let newEv = EKEvent(eventStore: store)
        newEv.title = original.title
        newEv.startDate = original.startDate
        newEv.endDate = original.endDate
        newEv.isAllDay = original.isAllDay
        newEv.notes = original.notes
        newEv.location = original.location
        newEv.calendar = destCalendar ?? original.calendar

        do {
            try store.save(newEv, span: .thisEvent, commit: true)
        } catch {
            print("Error duplicating:", error)
        }
    }

    @objc private func handleLongPressOnEmptySpace(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)

        switch gesture.state {
        case .began:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            for evView in eventViews {
                if !evView.isHidden && evView.frame.contains(point) {
                    return
                }
            }
            draggingGhosts.removeAll()
            draggingOriginalAlphas.removeAll()
            if let oldGhost = ghostEmptySpaceView {
                oldGhost.removeFromSuperview()
            }

            let ghostDesc = BasicEvent()
            ghostDesc.dateInterval = DateInterval(start: Date(), end: Date().addingTimeInterval(3600))
            ghostDesc.text = NSLocalizedString("New Meal", comment: "")
            ghostDesc.color = .systemBlue
            ghostDesc.backgroundColor = .systemBlue
            ghostDesc.textColor = .black
            
            let ghostView = createEventView()
            ghostView.updateWithDescriptor(event: ghostDesc)
            ghostView.applyGhostStyle()
            draggingGhosts[ghostView] = ghostView
            
            let xPoint = point.x
            let dayIndex = Int(xPoint / dayColumnWidth)
            let allCals = calendarVM.calendarsDict
            let selectedCals = allCals.filter { $0.value.selected }
            let calsToShow = selectedCals.isEmpty ? allCals : selectedCals
            let sortedCals = calsToShow.sorted { $0.value.title < $1.value.title }
            let subCount = max(sortedCals.count, 1)
            let subColumnWidth = dayColumnWidth / CGFloat(subCount)
            let offsetXWithinDay = xPoint - CGFloat(dayIndex) * dayColumnWidth
            let subIndex = Int(offsetXWithinDay / subColumnWidth)
            
            if subIndex >= 0, subIndex < sortedCals.count {
                ghostView.applyGhostColor(newColor: sortedCals[subIndex].value.color)
            }
            
            let columNumber = CGFloat(CalendarViewModel.shared.calendarsDict.filter { $0.value.selected }.count)
            let w = dayColumnWidth - style.eventGap * 2 * columNumber
            let h: CGFloat = 75
            let x = point.x - w / columNumber / 2
            let y = point.y - 25
            let initialFrame = CGRect(x: x, y: y, width: w / columNumber, height: h)
            ghostView.frame = initialFrame
            addSubview(ghostView)
            
            ghostEmptySpaceView = ghostView
            ghostEmptySpaceDescriptor = ghostDesc

            let ghostDragData = GhostDragData(initialFingerPoint: point, anchorOffsetX: point.x - initialFrame.minX, anchorOffsetY: point.y - initialFrame.minY, originalFrame: initialFrame)
            ghostView.layer.setValue(ghostDragData, forKey: DRAG_DATA_KEY)
            setScrollsClipping(enabled: false)
            
        case .changed:
            guard let ghostView = ghostEmptySpaceView,
                  let dragData  = ghostView.layer.value(forKey: DRAG_DATA_KEY) as? GhostDragData else { return }

            let current = gesture.location(in: self)
            var newFrame = dragData.originalFrame
            newFrame.origin.x += current.x - dragData.initialFingerPoint.x
            newFrame.origin.y += current.y - dragData.initialFingerPoint.y
            
            // ----- 👇 НАЧАЛО НА КОРЕКЦИЯТА: Премахваме ограничаването (clamping) 👇 -----
            ghostView.frame = newFrame
            // ----- 👆 КРАЙ НА КОРЕКЦИЯТА 👆 -----

            let topPoint = CGPoint(x: newFrame.midX, y: newFrame.minY)
            if let rawDate = dateFromPoint(topPoint) {
                let snapped = snapToNearest10Min(rawDate)
                setSingle10MinuteMarkFromDate(snapped)
            }

            let xPoint = newFrame.midX
            let dayIndex = Int(xPoint / dayColumnWidth)
            let allCals = calendarVM.calendarsDict
            let selected = allCals.filter { $0.value.selected }
            let calsToShow = selected.isEmpty ? allCals : selected
            let sortedCals = calsToShow.sorted { $0.value.title < $1.value.title }
            let subCount = max(sortedCals.count, 1)
            let subColumnWidth = dayColumnWidth / CGFloat(subCount)
            let offsetXWithinDay = xPoint - CGFloat(dayIndex) * dayColumnWidth
            let subIndex = min(max(Int(offsetXWithinDay / subColumnWidth), 0), subCount - 1)

            ghostView.applyGhostColor(newColor: sortedCals[subIndex].value.color)
            updateAutoScrollDirection(for: gesture)
            
        case .ended, .cancelled:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            stopAutoScroll()
            setScrollsClipping(enabled: true)

            guard let ghostView = ghostEmptySpaceView else { return }
            ghostView.layer.setValue(nil, forKey: DRAG_DATA_KEY)

            let finalFrame = ghostView.frame
            let topPoint = CGPoint(x: finalFrame.midX, y: finalFrame.minY)
            let rawDate = dateFromPoint(topPoint)
            
            ghostView.removeFromSuperview()
            ghostEmptySpaceView = nil
            ghostEmptySpaceDescriptor = nil
            draggingGhosts.removeAll()
            draggingOriginalAlphas.removeAll()

            if let unwrapped = rawDate {
                let snappedDate = snapToNearest10Min(unwrapped)
                
                let xMid = finalFrame.midX
                var dayIndex = Int(xMid / dayColumnWidth)
                dayIndex = max(0, min(dayIndex, dayCount - 1))
                
                let allCals = calendarVM.calendarsDict
                let selectedCals = allCals.filter { $0.value.selected }
                let calsToShow = selectedCals.isEmpty ? allCals : selectedCals
                let sortedCals = calsToShow.sorted { $0.value.title < $1.value.title }
                
                let subCount = max(sortedCals.count, 1)
                let subColumnWidth = dayColumnWidth / CGFloat(subCount)
                
                let offsetXWithinDay = xMid - CGFloat(dayIndex) * dayColumnWidth
                var subIndex = Int(offsetXWithinDay / subColumnWidth)
                subIndex = max(0, min(subIndex, subCount - 1))
                
                let chosenCalendar = sortedCals[subIndex].value.calendar
                
                onEmptyLongPress?(snappedDate, chosenCalendar)
            }
        default: break
        }
    }
    
    private func setupLongPressForEmptySpace() {
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressOnEmptySpace(_:)))
        lp.minimumPressDuration = 0.7
        addGestureRecognizer(lp)
    }

    // ----- 👇 НАЧАЛО НА КОРЕКЦИЯТА: Премахваме неизползваните функции 👇 -----
    // Функциите clampY и clampYInContainer вече не са необходими и се премахват.
    // ----- 👆 КРАЙ НА КОРЕКЦИЯТА 👆 -----
}
