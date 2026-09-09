import UIKit
import SwiftUI
import EventKit
import EventKitUI

public final class ShoppingTwoWayPinnedSingleDayMultiCalendarContainerView: UIView,
                                                                  UIScrollViewDelegate,
                                                                  UIGestureRecognizerDelegate,
                                                                  UISearchBarDelegate
{
    @ObservedObject private var effectManager = EffectManager.shared

    private var didScrollToNow = false

    // MARK: - Theme Management
    private var backgroundHostingController: UIHostingController<ThemeBackgroundView>?

    // MARK: - Calendar Properties
    private let calendarVM = CalendarViewModel.shared
    private let profile: Profile
    
    public var onShowListsTap: (() -> Void)?
    
    public var onCalendarsSelectionChanged: (() -> Void)?
    public var fromDate: Date = Date() {
        didSet {
            weekView.fromDate = fromDate
            setNeedsLayout()
        }
    }
    
    public var onRangeChange: ((Date, Date) -> Void)?
    public var onEventTap: ((EventDescriptor) -> Void)? {
        didSet { weekView.onEventTap = onEventTap }
    }
    public var onEventDeleted: ((EventDescriptor) -> Void)? {
        didSet { weekView.onEventDeleted = onEventDeleted }
    }
    public var onEventDuplicated: ((EventDescriptor) -> Void)? {
        didSet { weekView.onEventDuplicated = onEventDuplicated }
    }
    public var onEmptyLongPress: ((Date, EKCalendar?) -> Void)? {
        didSet { weekView.onEmptyLongPress = onEmptyLongPress }
    }
    public var onEventDragEnded: ((EventDescriptor, Date, Bool) -> Void)? {
        didSet { weekView.onEventDragEnded = onEventDragEnded }
    }
    public var onEventDragResizeEnded: ((EventDescriptor, Date) -> Void)? {
        didSet { weekView.onEventDragResizeEnded = onEventDragResizeEnded }
    }
    public var onAddNewEvent: (() -> Void)?
    
    // MARK: - UI Components
    public let hoursColumnScrollView = UIScrollView()
    public let hoursColumnView       = HoursColumnView()
    fileprivate let cornerView = UIView()
    public let mainScrollView = UIScrollView()
    public let weekView       = ShoppingSingleDayTimelineMultiCalendarView()
    
    private let navBar = PassthroughView()
    
    private let monthLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        return label
    }()
    private let weekCarousel = WeekCarouselView()
    public var goalProgressProvider: ((Date) -> Double?)? {
           didSet {
               self.weekCarousel.goalProgressProvider = goalProgressProvider
               self.weekCarousel.reload()
           }
       }
    fileprivate let navBarHeight: CGFloat     = 50
    fileprivate let daysHeaderHeight: CGFloat = 20
    fileprivate let leftColumnWidth: CGFloat  = 55
    private var redrawTimer: Timer?

    fileprivate let calendarsHeaderScrollView = UIScrollView()
    fileprivate let calendarsHeaderView       = CalendarsHeaderView()
    fileprivate let calendarsHeaderHeight: CGFloat = 30
    
    private var buttonBackgroundHostingController: UIHostingController<GlassBackgroundView>?
    private let buttonBackgroundContainerView = UIView()
    private let showListsButton = UIButton(type: .system)
    
    // MARK: - Init
    public init(profile: Profile, frame: CGRect = .zero) {
        self.profile = profile
        super.init(frame: frame)
        setupViews()
        updateCalendarsHeader()
        startRedrawTimer()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented. Use init(profile:).")
    }
    
    deinit {
        redrawTimer?.invalidate()
    }
    
    @MainActor
    private func updateCalendarsHeader() {
        let shoppingCalendarID: String?
        if profile.hasSeparateStorage {
            shoppingCalendarID = profile.shoppingListCalendarID
        } else {
            shoppingCalendarID = UserDefaults.standard.string(forKey: calendarVM.sharedShoppingListCalendarIDKey)
        }
        
        var calendarToDisplay: [String: (title: String, color: UIColor, selected: Bool, calendar: EKCalendar)] = [:]
        
        if let id = shoppingCalendarID, let cal = calendarVM.eventStore.calendar(withIdentifier: id) {
            let color = cal.cgColor != nil ? UIColor(cgColor: cal.cgColor) : .systemGray
            calendarToDisplay[id] = (title: cal.title, color: color, selected: true, calendar: cal)
        }
        
        calendarsHeaderView.calendarsDict = calendarToDisplay
        weekView.calendarsDict = calendarToDisplay
        
        setNeedsLayout()
        layoutIfNeeded()
    }

    // MARK: - Setup
    private func setupViews() {
        let hostingController = UIHostingController(rootView: ThemeBackgroundView())
        if let backgroundView = hostingController.view {
            backgroundView.backgroundColor = .clear
            insertSubview(backgroundView, at: 0)
            self.backgroundHostingController = hostingController
        }
        
        backgroundColor = .clear
        
        mainScrollView.delegate = self
        mainScrollView.showsHorizontalScrollIndicator = true
        mainScrollView.showsVerticalScrollIndicator   = true
        mainScrollView.bounces = false
        mainScrollView.layer.zPosition = 1
        mainScrollView.contentInsetAdjustmentBehavior = .never
        mainScrollView.addSubview(weekView)
        
        weekView.profile = self.profile
        
        addSubview(mainScrollView)
        
        hoursColumnScrollView.showsVerticalScrollIndicator = false
        hoursColumnScrollView.isScrollEnabled = false
        hoursColumnScrollView.bounces = false
        hoursColumnScrollView.layer.zPosition = 3
        hoursColumnScrollView.contentInsetAdjustmentBehavior = .never
        hoursColumnScrollView.addSubview(hoursColumnView)
        addSubview(hoursColumnScrollView)
        
        cornerView.backgroundColor = .clear
        cornerView.layer.zPosition = 5
        addSubview(cornerView)
        
        navBar.backgroundColor = .clear
        navBar.layer.zPosition = 7
        addSubview(navBar)
        navBar.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        
        navBar.addSubview(monthLabel)

        let buttonHostingController = UIHostingController(rootView: GlassBackgroundView(cornerRadius: 17))
        if let backgroundView = buttonHostingController.view {
            backgroundView.backgroundColor = .clear
            buttonBackgroundContainerView.addSubview(backgroundView)
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                backgroundView.topAnchor.constraint(equalTo: buttonBackgroundContainerView.topAnchor),
                backgroundView.bottomAnchor.constraint(equalTo: buttonBackgroundContainerView.bottomAnchor),
                backgroundView.leadingAnchor.constraint(equalTo: buttonBackgroundContainerView.leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: buttonBackgroundContainerView.trailingAnchor),
            ])
        }
        self.buttonBackgroundHostingController = buttonHostingController
        navBar.addSubview(buttonBackgroundContainerView)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(showListsButtonTapped))
        buttonBackgroundContainerView.addGestureRecognizer(tapGesture)
        buttonBackgroundContainerView.isUserInteractionEnabled = true
        
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = UIImage(systemName: "checklist", withConfiguration: config)
        showListsButton.setImage(image, for: .normal)
        showListsButton.isUserInteractionEnabled = false
        navBar.addSubview(showListsButton)
        
        weekCarousel.backgroundColor = .clear
        addSubview(weekCarousel)
        weekCarousel.onDaySelected = { [weak self] date in
            guard let self = self else { return }
            self.fromDate = date
            self.onRangeChange?(date, date)
        }

        weekView.hoursColumnView = hoursColumnView
        hoursColumnView.hourHeight = 95
        hoursColumnView.extraMarginTopBottom = 10
        weekView.hourHeight = 95
        weekView.topMargin  = 10
        
        calendarsHeaderScrollView.showsHorizontalScrollIndicator = false
        calendarsHeaderScrollView.showsVerticalScrollIndicator   = false
        calendarsHeaderScrollView.bounces = false
        calendarsHeaderScrollView.delegate = self
        calendarsHeaderScrollView.layer.zPosition = 4
        calendarsHeaderScrollView.contentInsetAdjustmentBehavior = .never
        addSubview(calendarsHeaderScrollView)
        
        calendarsHeaderView.backgroundColor = .clear
        calendarsHeaderScrollView.addSubview(calendarsHeaderView)
    }

    @objc private func showListsButtonTapped() {
        onShowListsTap?()
    }
    
    // MARK: - Layout
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        backgroundHostingController?.view.frame = self.bounds

        let topOffset: CGFloat = 20
        
        navBar.frame = CGRect(x: 0, y: topOffset, width: bounds.width - 2, height: navBarHeight)
        
        let df = DateFormatter()
        df.dateFormat = "LLLL"
        monthLabel.text = df.string(from: fromDate)
        monthLabel.textColor = UIColor(effectManager.currentGlobalAccentColor)
        monthLabel.sizeToFit()
        monthLabel.frame = CGRect(x: 10, y: (navBar.bounds.height - monthLabel.bounds.height) / 2 + 26, width: monthLabel.bounds.width, height: monthLabel.bounds.height)

        let buttonDiameter: CGFloat = 34
        let buttonX = navBar.bounds.width - buttonDiameter - 16
        let buttonY = monthLabel.center.y - (buttonDiameter / 2)
        
        buttonBackgroundContainerView.frame = CGRect(x: buttonX, y: buttonY, width: buttonDiameter, height: buttonDiameter)
        buttonBackgroundContainerView.layer.cornerRadius = buttonDiameter / 2
        buttonBackgroundContainerView.clipsToBounds = true

        showListsButton.frame = buttonBackgroundContainerView.frame
        showListsButton.tintColor = UIColor(effectManager.currentGlobalAccentColor)
        
        let singleDayCarouselHeight: CGFloat = 80
        weekCarousel.layer.zPosition = 8
        weekCarousel.frame = CGRect(x: 0, y: navBar.frame.maxY + 11, width: bounds.width, height: singleDayCarouselHeight)
        weekCarousel.selectedDate = fromDate
        
        let yMain = weekCarousel.frame.maxY
        cornerView.frame = CGRect(x: 0, y: yMain, width: leftColumnWidth, height: daysHeaderHeight)
        
        let availableWidth = bounds.width - leftColumnWidth
        weekView.dayColumnWidth = availableWidth
        
        let calendarsHeaderY = weekCarousel.frame.maxY
        calendarsHeaderScrollView.frame = CGRect(x: leftColumnWidth, y: calendarsHeaderY, width: availableWidth, height: calendarsHeaderHeight)
        calendarsHeaderScrollView.contentSize = CGSize(width: weekView.dayColumnWidth, height: calendarsHeaderHeight)
        calendarsHeaderView.frame = CGRect(x: 0, y: 0, width: weekView.dayColumnWidth, height: calendarsHeaderHeight)
        
        let hoursColumnY = calendarsHeaderScrollView.frame.maxY
        hoursColumnScrollView.frame = CGRect(x: 0, y: hoursColumnY, width: leftColumnWidth, height: bounds.height - hoursColumnY)
        mainScrollView.frame = CGRect(x: leftColumnWidth, y: hoursColumnY, width: availableWidth, height: bounds.height - hoursColumnY)
        
        let totalHours = 25
        let finalHeight = CGFloat(totalHours) * weekView.hourHeight + (weekView.topMargin * 2)
        mainScrollView.contentSize = CGSize(width: weekView.dayColumnWidth, height: finalHeight)
        weekView.frame = CGRect(x: 0, y: 0, width: weekView.dayColumnWidth, height: finalHeight)
        hoursColumnScrollView.contentSize = CGSize(width: leftColumnWidth, height: finalHeight)
        hoursColumnView.frame = CGRect(x: 0, y: 0, width: leftColumnWidth, height: finalHeight)
        
        let cal = Calendar.current
        let nowOnly = cal.startOfDay(for: Date())
        let fromOnly = cal.startOfDay(for: fromDate)
        hoursColumnView.isCurrentDayInWeek = (nowOnly == fromOnly)
        hoursColumnView.currentTime = hoursColumnView.isCurrentDayInWeek ? Date() : nil
        
        hoursColumnView.setNeedsDisplay()
        weekView.setNeedsDisplay()
        
        if !didScrollToNow {
            scrollToCurrentTime()
            didScrollToNow = true
        }
    }
    
    // MARK: - Delegate & Timer
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == mainScrollView {
            calendarsHeaderScrollView.contentOffset.x = scrollView.contentOffset.x
            let newOffsetY = scrollView.contentOffset.y
            let maxHoursColumnOffsetY = max(0, hoursColumnScrollView.contentSize.height - hoursColumnScrollView.bounds.height)
            let clampedOffsetY = min(max(0, newOffsetY), maxHoursColumnOffsetY)
            hoursColumnScrollView.contentOffset.y = clampedOffsetY
        } else if scrollView == calendarsHeaderScrollView {
            mainScrollView.contentOffset.x = scrollView.contentOffset.x
        }
    }
    
    private func startRedrawTimer() {
        redrawTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.setNeedsLayout()
                self?.layoutIfNeeded()
            }
        }
    }
   
    private func scrollToCurrentTime() {
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        guard let hour = comps.hour, let minute = comps.minute else { return }

        let hoursFloat = CGFloat(hour) + CGFloat(minute) / 60.0
        let positionOfNowInContent = weekView.topMargin + (hoursFloat * weekView.hourHeight)
        let targetOffsetY = positionOfNowInContent - (mainScrollView.bounds.height / 2.0)
        let maxOffsetY = max(0, mainScrollView.contentSize.height - mainScrollView.bounds.height)
        let clampedOffsetY = min(max(0, targetOffsetY), maxOffsetY)

        mainScrollView.setContentOffset(CGPoint(x: mainScrollView.contentOffset.x, y: clampedOffsetY), animated: false)
    }
}
