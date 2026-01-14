
import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    // MARK: - Environment & Managers
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared

    // --- НАЧАЛО НА ПРОМЯНА 1: Добавяме safeAreaInsets и състояния за часовника ---
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @State private var currentTimeString: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let tFmt = DateFormatter.shortTime
    // --- КРАЙ НА ПРОМЯНА 1 ---

    // MARK: - Input
    let profile: Profile
    
    // MARK: - Data Queries
    @Query(sort: \Vitamin.name) private var allVitamins: [Vitamin]
    @Query(sort: \Mineral.name) private var allMinerals: [Mineral]

    // MARK: - State & ViewModel
    @StateObject private var viewModel: AnalyticsViewModel

    @State private var selectedTimeRange: TimeRange = .week
    @State private var customStartDate: Date?
    @State private var customEndDate: Date?
    @State private var selectedNutrientIDs: Set<String> = ["calories", "water"]
    
    // +++ НОВО: Състояние за непрочетени известия +++
    @State private var hasUnreadNotifications: Bool = false
    
    private enum SheetContent: Identifiable {
        case metrics, dateRange
        var id: Self { self }
    }
    @State private var presentedSheet: SheetContent? = nil
    
    enum TimeRange: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year", all = "All Time", custom = "Custom"
        var id: String { self.rawValue }
    }
    
    private let selectedMetricsKey = "selectedAnalyticMetricIDs"
    
    // MARK: - Initializer
    init(profile: Profile) {
        self.profile = profile
        _viewModel = StateObject(wrappedValue: AnalyticsViewModel(profile: profile, modelContext: GlobalState.modelContext!))
    }

    // --- НАЧАЛО НА ПРОМЯНА 2: Добавяме изчисляемо свойство за горното отстояние ---
    private var headerTopPadding: CGFloat {
#if targetEnvironment(macCatalyst)
        10
#else
        -safeAreaInsets.top + 10
#endif
    }    // --- КРАЙ НА ПРОМЯНАТА 2 ---

    // MARK: - Computed Properties
    private var allSelectableNutrients: [SelectableNutrient] {
           var items: [SelectableNutrient] = [
               SelectableNutrient(id: "calories", label: "Calories"),
               SelectableNutrient(id: "water", label: "Water Intake"),
               SelectableNutrient(id: "protein", label: "Protein"),
               SelectableNutrient(id: "carbohydrates", label: "Carbohydrates"),
               SelectableNutrient(id: "fat", label: "Fat")
           ]
           items.append(contentsOf: allVitamins.map { SelectableNutrient(id: "vit_\($0.id)", label: $0.name) })
           items.append(contentsOf: allMinerals.map { SelectableNutrient(id: "min_\($0.id)", label: $0.name) })
           return items
       }
    
    // MARK: - Body
    var body: some View {
        // --- НАЧАЛО НА ПРОМЯНА 3: Обвиваме всичко във VStack и добавяме отстояние ---
        VStack(spacing: 0) {
            userToolbar(for: profile)
                .padding(.trailing, 50)
                .padding(.leading, 40)
                .padding(.horizontal, -20)
                .padding(.bottom, 8)
            
            UpdatePlanBanner()
            
            VStack(spacing: 0) {
                AnalyticsToolbarView(
                    selectedTimeRange: $selectedTimeRange,
                    customStartDate: customStartDate,
                    customEndDate: customEndDate,
                    onCustomDateTapped: {
                                   withAnimation(.easeInOut) {
                                       presentedSheet = .dateRange
                                   }
                               }
                )
                .padding(.horizontal)

                timeRangePicker
                 .padding(.top)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        metricSelectorSection
                            .padding(.horizontal)

                        chartsSection
                            .padding(.horizontal)

                    }
                    .padding(.top)
                    Spacer(minLength: 150)
                }
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: effectManager.currentGlobalAccentColor, location: 0.01),
                            .init(color: effectManager.currentGlobalAccentColor, location: 0.9),
                            .init(color: .clear, location: 0.95)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(Color.clear)
            }
        }
        .padding(.top, headerTopPadding)
        // --- КРАЙ НА ПРОМЯНА 3 ---
        .overlay {
            if presentedSheet != nil {
                bottomSheetPanel
            }
        }
        // --- НАЧАЛО НА ПРОМЯНА 4: Добавяме onReceive за таймера ---
        .onReceive(timer) { _ in
            self.currentTimeString = Self.tFmt.string(from: Date())
        }
        // --- КРАЙ НА ПРОМЯНАТА 4 ---
        // +++ НОВО: .task и .onReceive за проверка на известия +++
        .task {
            await checkForUnreadNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await checkForUnreadNotifications()
            }
        }
        // --- START OF CHANGE: Add observer for notification status changes ---
        .onReceive(NotificationCenter.default.publisher(for: .unreadNotificationStatusChanged)) { _ in
            Task {
                await checkForUnreadNotifications()
            }
        }
        // --- END OF CHANGE ---
        .task(id: selectedTimeRange) { await updateViewModelAndFetch() }
        .task(id: selectedNutrientIDs) { await updateViewModelAndFetch() }
        .task(id: customStartDate) { await updateViewModelAndFetch() }
        .task(id: customEndDate) { await updateViewModelAndFetch() }
        .onAppear(perform: loadSelection)
        .onChange(of: selectedNutrientIDs) {
            saveSelection()
        }
        .onChange(of: selectedTimeRange) { _, newRange in
            if newRange == .custom {
                if customStartDate == nil {
                    let weekRange = calculateCurrentWeekRange()
                    customStartDate = weekRange.start
                    customEndDate = weekRange.end
                }
                withAnimation(.easeInOut) {
                    presentedSheet = .dateRange
                }
            }
        }
    }
    
    // +++ НОВА ПОМОЩНА ФУНКЦИЯ +++
    private func checkForUnreadNotifications() async {
        let unread = await NotificationManager.shared.getUnreadNotifications()
        self.hasUnreadNotifications = !unread.isEmpty
    }
    
    // --- НАЧАЛО НА ПРОМЯНА 5: Добавяме userToolbar ViewBuilder ---
    @ViewBuilder
    private func userToolbar(for profile: Profile) -> some View {
        HStack {
            Text(currentTimeString)
                .font(.system(size: 16))
                .fontWeight(.medium)
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .onAppear {
                    self.currentTimeString = Self.tFmt.string(from: Date())
                }

            Spacer()
            
            Button(action: {
                NotificationCenter.default.post(name: Notification.Name("openProfilesDrawer"), object: nil)
            }) {
                // +++ НАЧАЛО НА ПРОМЯНАТА: Обвиваме в ZStack +++
                ZStack(alignment: .topTrailing) {
                    if let photoData = profile.photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle()
                                .fill(effectManager.currentGlobalAccentColor.opacity(0.2))
                            if let firstLetter = profile.name.first {
                                Text(String(firstLetter))
                                    .font(.headline)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                            }
                        }
                        .frame(width: 40, height: 40)
                    }
                    
                    // +++ НОВО: Условна оранжева точка +++
                    if hasUnreadNotifications {
                        Circle()
                           .fill(Color.orange)
                           .frame(width: 12, height: 12)
                           .offset(x: 1, y: -1)
                    }
                }
                // +++ КРАЙ НА ПРОМЯНАТА +++
            }
            .buttonStyle(.plain)
            .foregroundColor(effectManager.currentGlobalAccentColor)
        }
    }
    // --- КРАЙ НА ПРОМЯНА 5 ---

    // MARK: - Subviews
    private var timeRangePicker: some View {
        WrappingSegmentedControl(selection: $selectedTimeRange, layoutMode: .wrap)
    }

    private var metricSelectorSection: some View {
        MultiSelectButton(
            selection: $selectedNutrientIDs,
            items: allSelectableNutrients,
            label: { $0.label },
            prompt: "Choose nutrients to display...",
            displayLimit: 6,
            isExpanded: presentedSheet == .metrics
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut) {
                presentedSheet = .metrics
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .font(.system(size: 16))
        .glassCardStyle(cornerRadius: 20)
    }

    private var chartsSection: some View {
        // Сортираме ID-тата по име (както и преди)
        let sortedIDs = Array(
            selectedNutrientIDs.sorted { nutrientName(for: $0) < nutrientName(for: $1) }
        )
        
        return VStack(spacing: 20) {
            ForEach(Array(sortedIDs.enumerated()), id: \.element) { index, nutrientID in
                // 👇 Реклама над първата графика и след това между всеки 2
                if shouldShowBannerAd(beforeChartAt: index) {
                    BannerAdRowView()
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
                
                AnalyticsChartView(
                    nutrientID: nutrientID,
                    points: viewModel.chartData[nutrientID] ?? [],
                    profile: profile,
                    onDeselect: {
                        withAnimation {
                            selectedNutrientIDs.remove(nutrientID)
                            saveSelection()
                        }
                    }
                )
            }
        }
    }

    private func shouldShowBannerAd(beforeChartAt index: Int) -> Bool {
        // Без реклами за платени абонаменти
        if SubscriptionManager.shared.subscriptionStatus != .base {
            return false
        }
        
        // Над първата графика
        if index == 0 { return true }
        
        // След това между всеки 2:
        // layout става: Banner, Chart0, Chart1, Banner, Chart2, Chart3, Banner, ...
        return index % 2 == 0
    }


    @ViewBuilder
    private var bottomSheetPanel: some View {
        ZStack(alignment: .bottom) {
            if effectManager.isLightRowTextColor {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            presentedSheet = nil
                        }
                    }
            } else {
                Color.white.opacity(0.4).ignoresSafeArea()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            presentedSheet = nil
                        }
                    }
            }
           
            VStack(spacing: 8) {
                switch presentedSheet {
                case .metrics: metricSelectionSheetContent
                case .dateRange: dateRangePickerSheetContent
                case .none: EmptyView()
                }
            }
            .padding(.top)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light) // 👈 Това принуждава материала да е тъмен
            }
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .zIndex(1)
        .transition(.move(edge: .bottom))
    }
    
    @ViewBuilder
    private var metricSelectionSheetContent: some View {
        ZStack {
            HStack {
                Text("Select Metrics").font(.headline).foregroundColor(effectManager.currentGlobalAccentColor)
                Spacer()
                Button("Done") { withAnimation { presentedSheet = nil } }
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
            }
        }
        .padding(.horizontal).frame(height: 35)
        DropdownMenu(selection: $selectedNutrientIDs, items: allSelectableNutrients, label: { $0.label }, selectAllBtn: false)
    }

    private var dateRangePickerSheetContent: some View {
        CalendarDateRangePickerWrapper(
            startDate: customStartDate,
            endDate: customEndDate,
            minimumDate: Calendar.current.date(byAdding: .year, value: -10, to: Date()),
            maximumDate: Date()
        ) { start, end in
            self.customStartDate = start
            self.customEndDate = end
            withAnimation { self.presentedSheet = nil }
        }
    }
    
    // MARK: - Logic & Helpers
    private func updateViewModelAndFetch() async {
        viewModel.selectedTimeRange = selectedTimeRange
        viewModel.customStartDate = customStartDate
        viewModel.customEndDate = customEndDate
        viewModel.selectedNutrientIDs = selectedNutrientIDs
        await viewModel.processAnalyticsData()
    }
    
    private func calculateCurrentWeekRange() -> (start: Date, end: Date) {
        var calendar = Calendar.current
        calendar.firstWeekday = GlobalState.firstWeekday
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return (Date(), Date())
        }
        let startOfWeek = weekInterval.start
        let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek)!
        return (startOfWeek, endOfWeek)
    }
    
    private func nutrientName(for id: String) -> String {
        allSelectableNutrients.first { $0.id == id }?.label ?? "Unknown"
    }
    
    private func saveSelection() {
        UserDefaults.standard.set(Array(selectedNutrientIDs), forKey: selectedMetricsKey)
    }
    
    private func loadSelection() {
           if let savedArray = UserDefaults.standard.array(forKey: selectedMetricsKey) as? [String] {
               selectedNutrientIDs = savedArray.isEmpty ? ["calories", "water", "protein", "carbohydrates", "fat"] : Set(savedArray)
           } else {
               selectedNutrientIDs = ["calories", "water", "protein", "carbohydrates", "fat"]
           }
       }
}
