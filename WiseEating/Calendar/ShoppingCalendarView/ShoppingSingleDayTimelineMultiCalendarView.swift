import UIKit
import EventKit

public final class ShoppingSingleDayTimelineMultiCalendarView: UIView, UIGestureRecognizerDelegate, @preconcurrency UIEditMenuInteractionDelegate {
    var highlightedSubColumn: (dayIndex: Int, calIndex: Int)? = nil
    private var editMenuInteraction: UIEditMenuInteraction?
    private var currentTappedDescriptor: EventDescriptor?
    private let highlightFillColor =  UIColor.systemGray4.withAlphaComponent(0.5)
    
    private var isCurrentlyOverAllDay = false
    
    public var profile: Profile?
    
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
    public var topMargin: CGFloat = 0
    public var dayColumnWidth: CGFloat = 100
    public var hourHeight: CGFloat =  95

    
    public var calendarsDict: [String: (title: String, color: UIColor, selected: Bool, calendar: EKCalendar)] = [:]

    // Hours column (for minute markers, etc.)
    public weak var hoursColumnView: HoursColumnView?
    
    // MARK: - Public Callbacks
    public var onEventTap: ((EventDescriptor) -> Void)?
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
    
    private var eventViews: [EventView] = []
    private var eventViewToDescriptor: [EventView : EventDescriptor] = [:]
    
    // MARK: - Editing / Drag & Drop / Resize
    private var currentlyEditedEventViewID: String?
    private var draggingGhosts: [EventView: EventView] = [:]
    private var draggingOriginalAlphas: [EventView: CGFloat] = [:]
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
    }
    
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        setupLongPressForEmptySpace()
        setupTapOnEmptySpace()
        setupEditMenuInteraction()
    }
    
    private func setupEditMenuInteraction() {
           let interaction = UIEditMenuInteraction(delegate: self)
           self.addInteraction(interaction)
           self.editMenuInteraction = interaction
    }
       
    @objc private func handleEventViewTap(_ gesture: UITapGestureRecognizer) {
       guard
           let tappedView = gesture.view as? EventView,
           let descriptor = eventViewToDescriptor[tappedView]
       else { return }
       
       self.currentTappedDescriptor = descriptor
       
       let location = gesture.location(in: self)
       let menuConfig = UIEditMenuConfiguration(identifier: nil, sourcePoint: location)
       editMenuInteraction?.presentEditMenu(with: menuConfig)
    }
    
    public func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard let descriptor = currentTappedDescriptor else { return nil }

        var children: [UIMenuElement] = []

        let editAction = UIAction(
            title: NSLocalizedString("Edit", comment: ""),
            image: UIImage(systemName: "square.and.pencil")
        ) {_ in
            if let multi = descriptor as? EKMultiDayWrapper {
                self.onEventTap?(multi)
            }
        }
        children.append(editAction)
        
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
        ) {}
        
    private func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            willDismissEditMenuWith configuration: UIEditMenuConfiguration,
            animator: UIEditMenuInteractionAnimating
        ) {}
    
    private func setupTapOnEmptySpace() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapOnEmptySpace(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)
    }
    
    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
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
        print("🛍️ [SHOP-TIMELINE-VIEW] Layouting \(regularLayoutAttributes.count) regular events.")

        for v in eventViews {
            v.isHidden = true
        }
        
        let calsToShow = Array(self.calendarsDict.values)
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
                let finalH = max(1, (yEnd - yStart) - 2 * gap)
                
                print("🛍️ [SHOP-TIMELINE-VIEW]   -> Drawing '\(attr.descriptor.text)' at frame: (x: \(finalX.rounded()), y: \(finalY.rounded()), w: \(finalW.rounded()), h: \(finalH.rounded()))")
                if (finalH <= 1) {
                    print("🛍️ [SHOP-TIMELINE-VIEW]   -> ❗️ WARNING: Event has zero or negative height. yStart=\(yStart), yEnd=\(yEnd)")
                }
                
                let evView = ensureEventView(index: usedEventViewIndex)
                usedEventViewIndex += 1
                
                evView.isHidden = false
                evView.frame = CGRect(x: finalX, y: finalY, width: finalW, height: finalH)
                
                evView.updateWithDescriptor(event: attr.descriptor)
                eventViewToDescriptor[evView] = attr.descriptor
                if let multi = attr.descriptor as? EKMultiDayWrapper {
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
        
        ev.profile = self.profile
        
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
              let descriptor = eventViewToDescriptor[evView] else { return }

        switch gesture.state {
        case .began:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isFirstResize = false
            removeGhostsForDescriptor(descriptor)

            if evView.layer.value(forKey: DRAG_DATA_KEY) != nil { return }
            setScrollsClipping(enabled: false)

            let realStart = (descriptor as? EKMultiDayWrapper)?.realEvent.startDate ?? descriptor.dateInterval.start
            let realEnd   = (descriptor as? EKMultiDayWrapper)?.realEvent.endDate ?? descriptor.dateInterval.end
            let totalDuration = realEnd.timeIntervalSince(realStart)
            
            let totalHeightInPoints = CGFloat(totalDuration / 3600) * hourHeight

            guard let container = superview?.superview as? ShoppingTwoWayPinnedSingleDayMultiCalendarContainerView else { return }
            let finger = gesture.location(in: container)

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
            
            let originalTappedFrameInContainer = container.convert(evView.frame, from: self)
            
            let dayStart = Calendar.current.startOfDay(for: fromDate)
            let timeBeforeToday = max(0, dayStart.timeIntervalSince(realStart))
            
            let yOffsetForPastTime = CGFloat(timeBeforeToday / 3600) * hourHeight

            let ghostFrame = CGRect(
                x: originalTappedFrameInContainer.origin.x,
                y: originalTappedFrameInContainer.origin.y - yOffsetForPastTime,
                width: originalTappedFrameInContainer.width,
                height: totalHeightInPoints - (style.eventGap * 2)
            )

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
                let container = superview?.superview as? ShoppingTwoWayPinnedSingleDayMultiCalendarContainerView
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
                  let container = superview?.superview as? ShoppingTwoWayPinnedSingleDayMultiCalendarContainerView else {
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

        let calsToShow = self.calendarsDict.values
        let numberOfCalendars = calsToShow.count
        if numberOfCalendars > 1 {
            ctx.saveGState()
            ctx.setStrokeColor(style.separatorColor.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(0.5 / UIScreen.main.scale)
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
                if plusHour == 0 { // Rolled over to next day
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
    
    private func setScrollsClipping(enabled: Bool) {}
    
    private func updateAutoScrollDirection(for gesture: UILongPressGestureRecognizer) {
        guard let container = self.superview?.superview as? ShoppingTwoWayPinnedSingleDayMultiCalendarContainerView else { return }
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
              let container = self.superview?.superview as? ShoppingTwoWayPinnedSingleDayMultiCalendarContainerView else { return }
        
        let scrollView = container.mainScrollView
        let scrollSpeed: CGFloat = 5
        var newOffset = scrollView.contentOffset
        
        newOffset.x += autoScrollDirection.x * scrollSpeed
        newOffset.y += autoScrollDirection.y * scrollSpeed
        
        newOffset.x = max(0, min(newOffset.x, scrollView.contentSize.width - scrollView.bounds.width))
        newOffset.y = max(0, min(newOffset.y, scrollView.contentSize.height - scrollView.bounds.height))
        
        scrollView.setContentOffset(newOffset, animated: false)
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
        
        let targets = vm.allCalendars.filter { $0.calendarIdentifier != sourceCalendar?.calendarIdentifier }

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
    
    private func duplicateEventInStore(_ descriptor: EventDescriptor, to destCalendar: EKCalendar?) {
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
            ghostDesc.text = NSLocalizedString("New Shopping List", comment: "")
            ghostDesc.color = .systemBlue
            ghostDesc.backgroundColor = .systemBlue.withAlphaComponent(0.8)
            ghostDesc.textColor = .white
            
            let ghostView = createEventView()
            ghostView.updateWithDescriptor(event: ghostDesc)
            ghostView.applyGhostStyleSopingList()
            
            let calsToShow = Array(self.calendarsDict.values)
            if let firstCalColor = calsToShow.first?.color {
                 ghostView.applyGhostColor(newColor: firstCalColor)
            }
            
            let w = dayColumnWidth - style.eventGap * 2
            let h: CGFloat = 150
            let x = point.x - w / 2
            let y = point.y - 25
            let initialFrame = CGRect(x: x, y: y, width: w, height: h)
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
            
            ghostView.frame = newFrame

            if let rawDate = dateFromPoint(newFrame.origin) {
                let snapped = snapToNearest10Min(rawDate)
                setSingle10MinuteMarkFromDate(snapped)
            }
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
            
            if let unwrapped = rawDate {
                let snappedDate = snapToNearest10Min(unwrapped)
                let chosenCalendar = self.calendarsDict.values.first?.calendar
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
}
