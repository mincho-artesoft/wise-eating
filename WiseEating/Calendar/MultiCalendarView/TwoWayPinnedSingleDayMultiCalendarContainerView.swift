import UIKit
import SwiftUI
import EventKit
import EventKitUI

//
// MARK: - TwoWayPinnedSingleDayMultiCalendarContainerView
//

public enum CalendarFilterType: String, CaseIterable, Identifiable {
    case all = "All"
    case meal = "Meal"
    case training = "Training"
    public var id: String { self.rawValue }
}

fileprivate struct FilterSegmentedControlView: View {
    @Binding var currentFilter: CalendarFilterType
    @ObservedObject private var effectManager = EffectManager.shared

    var body: some View {
        WrappingSegmentedControl(selection: $currentFilter, layoutMode: .wrap)
    }
}

// +++ НАЧАЛО НА ПРОМЯНАТА (1/6): Нов SwiftUI изглед, който комбинира бутона и филтъра +++
fileprivate struct CalendarToolbarItemsView: View {
    var onNodesTapped: () -> Void
    @Binding var currentFilter: CalendarFilterType
    @ObservedObject private var effectManager = EffectManager.shared

    var body: some View {
        HStack(spacing: 2) { // Връщаме оригиналното разстояние
            // 1. "Nodes" бутон, стилизиран като елемент от филтъра
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onNodesTapped()
            }) {
                HStack(spacing: 6) {
                    Text("Notes")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Image(systemName: "list.clipboard")
                        .font(.caption)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
            .buttonStyle(.plain)
            .glassCardStyle(cornerRadius: 20)


            // 2. Съществуващият филтър
            FilterSegmentedControlView(currentFilter: $currentFilter)
        }
    }
}
// +++ КРАЙ НА ПРОМЯНАТА (1/6) +++


public final class TwoWayPinnedSingleDayMultiCalendarContainerView: UIView,
                                                                  UIScrollViewDelegate,
                                                                  UIGestureRecognizerDelegate,
                                                                  UISearchBarDelegate
{
    @ObservedObject private var effectManager = EffectManager.shared

    private var calendarsChangedObserver: NSObjectProtocol?
    private var didScrollToNow = false

    // MARK: - Theme Management
    private var backgroundHostingController: UIHostingController<ThemeBackgroundView>?

    // ---------------------------------------------------------
    // MARK: - Променливи свързани с календарите
    // ---------------------------------------------------------
    
    private let calendarVM = CalendarViewModel.shared
    public var onCalendarsSelectionChanged: (() -> Void)?
    private var dropdownBackgroundView: UIView?
    
    public var currentView: Int = 1
    public var onViewChange: ((Int) -> Void)?
    
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
    public var onEventsReload: (() -> Void)? {
        didSet { weekView.onEventDragEnded = onEventDragEnded }
    }
    public var onEventDragResizeEnded: ((EventDescriptor, Date) -> Void)? {
        didSet { weekView.onEventDragResizeEnded = onEventDragResizeEnded }
    }
    public var onAddNewEvent: (() -> Void)?
    
    // ---------------------------------------------------------
    // MARK: - UI компоненти (scroll views, labels, пр.)
    // ---------------------------------------------------------
    public let hoursColumnScrollView = UIScrollView()
    public let hoursColumnView       = HoursColumnView()
    
    fileprivate let cornerView = UIView()
    
    public let mainScrollView = UIScrollView()
    public let weekView       = SingleDayTimelineMultiCalendarView()
    
    private let userToolbarView = UIView()
    private let timeLabel = UILabel()
    private let profileButton = UIButton(type: .custom)
    private let profileImageView = UIImageView()
    private let profileInitialsLabel = UILabel()
    private var clockTimer: Timer?
    private let notificationBadgeView = UIView()
    private var hasUnreadNotifications: Bool = false

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        return df
    }()
    
    private let navBar = PassthroughView()

    private let monthLabel: UILabel = {
        let label = UILabel()
        label.text = ""
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.isHidden  = true
        return label
    }()
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (2/6): Заменяме двата хостинг контролера с един +++
    private var toolbarHostingController: UIHostingController<CalendarToolbarItemsView>?
    public var onFilterChanged: ((CalendarFilterType) -> Void)?
    public var onNodesButtonTapped: (() -> Void)?
    // +++ КРАЙ НА ПРОМЯНАТА (2/6) +++
    
    public var currentFilter: CalendarFilterType = .all {
        didSet {
            if oldValue != currentFilter, let hostingController = toolbarHostingController {
                hostingController.rootView = createToolbarView()
            }
        }
    }
    
    private let weekCarousel: WeekCarouselView = {
        let view = WeekCarouselView()
        view.isHidden = true
        return view
    }()
    
    public var goalProgressProvider: ((Date) -> Double?)? {
           didSet {
               self.weekCarousel.goalProgressProvider = goalProgressProvider
               self.weekCarousel.reload()
           }
       }
    
    fileprivate let navBarHeight: CGFloat     = 50
    fileprivate let daysHeaderHeight: CGFloat = 20
    fileprivate let leftColumnWidth: CGFloat  = 55
    
    private let topBorder    = CALayer()
    private let bottomBorder = CALayer()
    
    private var showCalendar = false
    private var calendarBackgroundView: UIView?
    
    private var redrawTimer: Timer?
    private var isInSecondPass = false

    // ---------------------------------------------------------
    // MARK: - Втори хедър за календари
    // ---------------------------------------------------------
    fileprivate let calendarsHeaderScrollView = UIScrollView()
    fileprivate let calendarsHeaderView       = CalendarsHeaderView()
    fileprivate let calendarsHeaderHeight: CGFloat = 30
    
    private var profile: Profile
    
    // ---------------------------------------------------------
    // MARK: - Инициализация
    // ---------------------------------------------------------
    public init(profile: Profile, frame: CGRect = .zero) {
        self.profile = profile
        super.init(frame: frame)
        
        self.weekView.profile = profile
        
        setupViews()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCalendarsSelectionChanged),
            name: .calendarsSelectionChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkForUnreadNotifications),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkForUnreadNotifications),
            name: .unreadNotificationStatusChanged,
            object: nil
        )

        updateCalendarsHeader()
        startRedrawTimer()
        startClockTimer()
        checkForUnreadNotifications()
    }

    @objc private func handleCalendarsSelectionChanged(_ note: Notification) {
        Task { @MainActor in
            onCalendarsSelectionChanged?()
            updateCalendarsHeader()
        }
    }

    @MainActor
    private func updateCalendarsHeader() {
        calendarsHeaderView.calendarsDict = calendarVM.calendarsDict
        setNeedsLayout()
        layoutIfNeeded()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented. Use init(profile:frame:).")
    }
    
    deinit {
        redrawTimer?.invalidate()
        clockTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // ---------------------------------------------------------
    // MARK: - Setup на под-views
    // ---------------------------------------------------------
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (3/6): Нова функция за създаване на целия toolbar +++
    private func createToolbarView() -> CalendarToolbarItemsView {
        let filterBinding = Binding<CalendarFilterType>(
            get: { self.currentFilter },
            set: { newFilter in
                if self.currentFilter != newFilter {
                    self.currentFilter = newFilter
                    self.onFilterChanged?(newFilter)
                }
            }
        )
        return CalendarToolbarItemsView(
            onNodesTapped: {
                self.onNodesButtonTapped?()
            },
            currentFilter: filterBinding
        )
    }
    // +++ КРАЙ НА ПРОМЯНАТА (3/6) +++
    
    private func setupViews() {
        let hostingController = UIHostingController(rootView: ThemeBackgroundView())
        if let backgroundView = hostingController.view {
            backgroundView.backgroundColor = .clear
            insertSubview(backgroundView, at: 0)
            self.backgroundHostingController = hostingController
        }
        
        backgroundColor = .clear
        clipsToBounds   = true
        
        // --- user toolbar ---
        userToolbarView.backgroundColor = .clear
        addSubview(userToolbarView)

        timeLabel.font = .systemFont(ofSize: 16, weight: .medium)
        updateTime()
        userToolbarView.addSubview(timeLabel)

        profileButton.addTarget(self, action: #selector(profileButtonTapped), for: .touchUpInside)
        profileImageView.contentMode = .scaleAspectFill
        profileImageView.clipsToBounds = true
        profileButton.addSubview(profileImageView)
        
        profileInitialsLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        profileInitialsLabel.textAlignment = .center
        profileButton.addSubview(profileInitialsLabel)
        
        notificationBadgeView.backgroundColor = .orange
        notificationBadgeView.layer.cornerRadius = 6
        notificationBadgeView.isHidden = !hasUnreadNotifications
        profileButton.addSubview(notificationBadgeView)
        
        userToolbarView.addSubview(profileButton)

        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.baseBackgroundColor = .clear
            config.background.backgroundColor = .clear
            profileButton.configuration = config

            profileButton.configurationUpdateHandler = { [weak self] btn in
                let pressed = btn.isHighlighted || btn.isSelected
                UIView.animate(withDuration: 0.08,
                               delay: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState]) {
                    btn.transform = pressed ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
                    self?.profileImageView.alpha = pressed ? 0.85 : 1.0
                    self?.profileInitialsLabel.alpha = pressed ? 0.85 : 1.0
                }
            }
        }
        // --- край на user toolbar ---

        mainScrollView.delegate = self
        mainScrollView.showsHorizontalScrollIndicator = true
        mainScrollView.showsVerticalScrollIndicator   = true
        mainScrollView.bounces = false
        mainScrollView.layer.zPosition = 1
        
        if #available(iOS 11.0, *) {
            mainScrollView.contentInsetAdjustmentBehavior = .never
        }
        
        mainScrollView.addSubview(weekView)
        addSubview(mainScrollView)
        
        hoursColumnScrollView.showsVerticalScrollIndicator = false
        hoursColumnScrollView.isScrollEnabled = false
        hoursColumnScrollView.bounces = false
        hoursColumnScrollView.layer.zPosition = 3

        if #available(iOS 11.0, *) {
            hoursColumnScrollView.contentInsetAdjustmentBehavior = .never
        }
        
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
        
        // +++ НАЧАЛО НА ПРОМЯНАТА (4/6): Създаваме и добавяме обединения toolbar +++
        let toolbarHC = UIHostingController(rootView: createToolbarView())
        toolbarHC.view.backgroundColor = .clear
        navBar.addSubview(toolbarHC.view)
        self.toolbarHostingController = toolbarHC
        // +++ КРАЙ НА ПРОМЯНАТА (4/6) +++
        
        weekCarousel.backgroundColor = .clear
        addSubview(weekCarousel)
        weekCarousel.onDaySelected = { [weak self] date in
            guard let self = self else { return }
            self.fromDate = date
            self.onRangeChange?(date, date)
            self.setNeedsLayout()
        }

        weekView.hoursColumnView = hoursColumnView
        
        hoursColumnView.hourHeight          = 95
        hoursColumnView.extraMarginTopBottom = 10
        weekView.hourHeight = 95
        weekView.topMargin  = 10
        
        calendarsHeaderScrollView.showsHorizontalScrollIndicator = false
        calendarsHeaderScrollView.showsVerticalScrollIndicator   = false
        calendarsHeaderScrollView.bounces = false
        calendarsHeaderScrollView.delegate = self
        calendarsHeaderScrollView.layer.zPosition = 4
        
        if #available(iOS 11.0, *) {
            calendarsHeaderScrollView.contentInsetAdjustmentBehavior = .never
        }
        
        addSubview(calendarsHeaderScrollView)
        calendarsHeaderView.backgroundColor = .clear
        calendarsHeaderScrollView.addSubview(calendarsHeaderView)
    }
    
    // ---------------------------------------------------------
    // MARK: - Layout
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        backgroundHostingController?.view.frame = self.bounds

        // 1. Позиционираме лентата с часовника и профила най-отгоре
        userToolbarView.frame = CGRect(x: 0, y: 10, width: bounds.width, height: 40)

        timeLabel.textColor = UIColor(effectManager.currentGlobalAccentColor)
        timeLabel.sizeToFit()
        timeLabel.frame.origin = CGPoint(x: 20, y: (userToolbarView.bounds.height - timeLabel.frame.height) / 2)

        let profileButtonSize: CGFloat = 40
        profileButton.frame = CGRect(
            x: userToolbarView.bounds.width - profileButtonSize - 30,
            y: (userToolbarView.bounds.height - profileButtonSize) / 2,
            width: profileButtonSize,
            height: profileButtonSize
        )
        profileImageView.frame = profileButton.bounds
        profileInitialsLabel.frame = profileButton.bounds
        profileButton.layer.cornerRadius = profileButtonSize / 2
        profileImageView.layer.cornerRadius = profileButtonSize / 2
        
        let badgeSize: CGFloat = 12
        notificationBadgeView.frame = CGRect(
            x: profileButton.bounds.width - badgeSize + 1,
            y: -1,
            width: badgeSize,
            height: badgeSize
        )


        if let photoData = profile.photoData, let image = UIImage(data: photoData) {
            profileImageView.image = image
            profileImageView.isHidden = false
            profileInitialsLabel.isHidden = true
            profileButton.backgroundColor = .clear
        } else {
            profileImageView.isHidden = true
            profileInitialsLabel.isHidden = false
            if let firstLetter = profile.name.first {
                profileInitialsLabel.text = String(firstLetter)
            }
            profileInitialsLabel.textColor = UIColor(effectManager.currentGlobalAccentColor)
            profileButton.backgroundColor = UIColor(effectManager.currentGlobalAccentColor.opacity(0.2))
        }
        
        // --- НАЧАЛО НА КОРЕКЦИЯТА ---
        // 2. Позиционираме втората навигационна лента (с месеца и филтъра) ПОД първата.
        navBar.frame = CGRect(x: 0, y: userToolbarView.frame.maxY, width: bounds.width, height: navBarHeight)

        let df = DateFormatter()
        df.dateFormat = "LLLL"
        monthLabel.text = df.string(from: fromDate)
        monthLabel.textColor = UIColor(effectManager.currentGlobalAccentColor)
        monthLabel.sizeToFit()
        // Позиционираме етикета за месеца вляво
        monthLabel.frame = CGRect(
            x: 10,
            y: (navBar.bounds.height - monthLabel.bounds.height) / 2,
            width: monthLabel.bounds.width,
            height: monthLabel.bounds.height
        )
        monthLabel.isHidden = false

        // +++ НАЧАЛО НА ПРОМЯНАТА (5/6): Позиционираме единствения toolbar +++
        // Позиционираме обединения toolbar вдясно, като динамично изчисляваме ширината му
        let toolbarHeight: CGFloat = 34
        let rightPadding: CGFloat = 10
        let spacing: CGFloat = 8 // Разстояние между месеца и инструментите
        
        // 1. Изчисляваме максимално наличната ширина за лентата с инструменти
        let availableToolbarWidth = navBar.bounds.width - monthLabel.frame.maxX - spacing - rightPadding
        
        // 2. Оставяме SwiftUI да изчисли идеалния размер, НО го ограничаваме до наличната ширина
        let idealToolbarSize = toolbarHostingController!.view.sizeThatFits(CGSize(width: availableToolbarWidth, height: toolbarHeight))
        let finalToolbarWidth = min(availableToolbarWidth, idealToolbarSize.width)

        // 3. Позиционираме лентата с инструменти вдясно
        let toolbarX = navBar.bounds.width - finalToolbarWidth - rightPadding
        let toolbarY = (navBar.bounds.height - toolbarHeight) / 2
        
        toolbarHostingController?.view.frame = CGRect(
            x: toolbarX,
            y: toolbarY,
            width: finalToolbarWidth,
            height: toolbarHeight
        )
        // +++ КРАЙ НА ПРОМЯНАТА (5/6) +++
        // --- КРАЙ НА КОРЕКЦИЯТА ---

        let singleDayCarouselHeight: CGFloat = 80
        weekCarousel.isHidden = false
        weekCarousel.layer.zPosition = 8
        // Carousel-ът вече следва новата позиция на navBar
        // +++ НАЧАЛО НА ПРОМЯНАТА (6/6): Обновяваме референцията тук +++
        let singleDayCarouselY = navBar.frame.maxY + 11 // Коригирано, за да следва navBar, а не toolbar-а
        // +++ КРАЙ НА ПРОМЯНАТА (6/6) +++
        weekCarousel.frame = CGRect(x: 0, y: singleDayCarouselY, width: bounds.width, height: singleDayCarouselHeight)
        weekCarousel.selectedDate = fromDate
        
        let yMain = weekCarousel.frame.maxY
        
        cornerView.frame = CGRect(x: 0, y: yMain, width: leftColumnWidth, height: daysHeaderHeight)
        
        let cal = Calendar.current
        let fromOnly = cal.startOfDay(for: fromDate)
        let availableWidth = bounds.width - leftColumnWidth

        let selectedCount   = calendarVM.calendarsDict.values.filter { $0.selected }.count
        let calendarsToShow = selectedCount == 0 ? calendarVM.calendarsDict.count : selectedCount

        if calendarsToShow == 1 {
            weekView.dayColumnWidth = availableWidth
        } else {
            weekView.dayColumnWidth = (CGFloat(calendarsToShow) * availableWidth) - 25
        }
        
        let totalDaysHeaderWidth = weekView.dayColumnWidth
        let calendarsHeaderY = weekCarousel.frame.maxY
        calendarsHeaderScrollView.frame = CGRect(
            x: leftColumnWidth,
            y: calendarsHeaderY,
            width: bounds.width - leftColumnWidth,
            height: calendarsHeaderHeight
        )
        calendarsHeaderScrollView.contentSize = CGSize(width: totalDaysHeaderWidth, height: calendarsHeaderHeight)
        
        calendarsHeaderView.frame = CGRect(x: 0, y: 0, width: totalDaysHeaderWidth, height: calendarsHeaderHeight)
        
        let allDayY = calendarsHeaderScrollView.frame.maxY
        
        let hoursColumnY = allDayY
        hoursColumnScrollView.frame = CGRect(x: 0, y: hoursColumnY, width: leftColumnWidth, height: bounds.height - hoursColumnY)
        
        mainScrollView.frame = CGRect(x: leftColumnWidth, y: hoursColumnY, width: bounds.width - leftColumnWidth, height: bounds.height - hoursColumnY)
        
        let totalHours = 25
        let baseHeight = CGFloat(totalHours) * weekView.hourHeight
        let finalHeight = baseHeight + (weekView.topMargin * 2)
        
        let totalWidth = weekView.dayColumnWidth
        mainScrollView.contentSize = CGSize(width: totalWidth, height: finalHeight)
        weekView.frame = CGRect(x: 0, y: 0, width: totalWidth, height: finalHeight)
        
        hoursColumnScrollView.contentSize = CGSize(width: leftColumnWidth, height: finalHeight)
        hoursColumnView.frame = CGRect(x: 0, y: 0, width: leftColumnWidth, height: finalHeight)
        
        let nowOnly = cal.startOfDay(for: Date())
        hoursColumnView.isCurrentDayInWeek = (nowOnly == fromOnly)
        hoursColumnView.currentTime = hoursColumnView.isCurrentDayInWeek ? Date() : nil
        
        hoursColumnView.setNeedsDisplay()
        weekView.setNeedsDisplay()
        
        if !didScrollToNow {
            scrollToCurrentTime()
            didScrollToNow = true
        }
    }
    
    // --- ПРОМЯНА: Добавени са методи за часовника и бутона ---
    private func startClockTimer() {
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateTime), userInfo: nil, repeats: true)
    }

    @objc private func updateTime() {
        timeLabel.text = Self.timeFormatter.string(from: Date())
    }

    @objc private func profileButtonTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        NotificationCenter.default.post(name: .openProfilesDrawer, object: nil)
    }
    
    // +++ НОВО (4/4): Добавяме функцията за проверка +++
    @objc private func checkForUnreadNotifications() {
        Task { @MainActor in
            let unread = await NotificationManager.shared.getUnreadNotifications()
            let hasUnread = !unread.isEmpty
            if self.hasUnreadNotifications != hasUnread {
                self.hasUnreadNotifications = hasUnread
                self.notificationBadgeView.isHidden = !hasUnread
            }
        }
    }
    
    public func updateProfile(_ newProfile: Profile) {
        self.profile = newProfile
        
        // +++ НАЧАЛО НА ПРОМЯНАТА (2/2) +++
        // Уверяваме се, че и weekView се обновява, когато профилът се смени
        self.weekView.profile = newProfile
        // +++ КРАЙ НА ПРОМЯНАТА (2/2) +++
        
        setNeedsLayout()
    }
    // --- Край на промяната ---
    
    // ---------------------------------------------------------
    // MARK: - UIScrollViewDelegate
    // ---------------------------------------------------------
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
    
    // ---------------------------------------------------------
    // MARK: - Timer за презарисуване
    // ---------------------------------------------------------
    private func startRedrawTimer() {
        redrawTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.setNeedsLayout()
                self?.layoutIfNeeded()
                self?.weekView.setNeedsDisplay()
            }
        }
    }
   
    private func fmt(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: d)
    }
    
    // ---------------------------------------------------------
    // MARK: - Add (+)
    // ---------------------------------------------------------
    @objc private func addEventButtonTapped() {
        onAddNewEvent?()
    }

    private func updateSearchResults() {
        setNeedsLayout()
    }
    
    // ---------------------------------------------------------
    // MARK: - Помощен метод за topVC
    // ---------------------------------------------------------
    private func topMostViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
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
