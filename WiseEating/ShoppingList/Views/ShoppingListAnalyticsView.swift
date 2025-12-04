import SwiftUI
import SwiftData

// Помощна структура за данните в графиката
fileprivate struct SpendingDataPoint: Identifiable {
    let id: Date
    let startDate: Date
    let endDate: Date
    let totalSpent: Double
}

struct ShoppingListAnalyticsView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // MARK: - Enums & State
    private enum AnalyticsMode: String, CaseIterable, Identifiable {
        case weekly = "Weekly", monthly = "Monthly"
        var id: Self { self }
    }
    @State private var selectedMode: AnalyticsMode = .weekly
    @State private var displayDate = Date()
    
    // MARK: - Input & Dependencies
    let profile: Profile
    let onDismiss: () -> Void
    @Environment(\.modelContext) private var modelContext

    // MARK: - Data Query
    @Query private var shoppingLists: [ShoppingListModel]

    // MARK: - Interaction State
    @State private var canvasSize: CGSize = .zero
    @State private var dragLocation: CGPoint?

    // MARK: - Initializer
    init(profile: Profile, onDismiss: @escaping () -> Void) {
        self.profile = profile
        self.onDismiss = onDismiss
        
        let profileID = profile.persistentModelID
        let usesSeparateStorage = profile.hasSeparateStorage
        
        let predicate: Predicate<ShoppingListModel>
        if usesSeparateStorage {
            predicate = #Predicate<ShoppingListModel> { $0.profile?.persistentModelID == profileID }
        } else {
            predicate = #Predicate<ShoppingListModel> { $0.profile == nil }
        }
        
        _shoppingLists = Query(filter: predicate, sort: [SortDescriptor(\.eventStartDate, order: .forward)])
    }
    
    // MARK: - Computed Properties for Data Processing
    
    private func getWeeks(for month: Date) -> [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDayOfMonth = monthInterval.start
        guard let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstDayOfMonth) else { return [] }

        var weeks: [Date] = []
        var currentWeekStart = firstWeek.start
        
        while currentWeekStart < monthInterval.end {
            weeks.append(currentWeekStart)
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) else { break }
            currentWeekStart = nextWeek
        }
        return weeks
    }

    private var chartData: [SpendingDataPoint] {
        let calendar = Calendar.current
        let completedLists = shoppingLists.filter { $0.isCompleted }

        switch selectedMode {
        case .weekly:
            guard let monthInterval = calendar.dateInterval(of: .month, for: displayDate) else { return [] }
            
            let groupedByWeek = Dictionary(grouping: completedLists) { list -> Date in
                return calendar.dateInterval(of: .weekOfYear, for: list.eventStartDate)!.start
            }
            
            let weeksThatIntersectMonth = groupedByWeek.filter { (weekStartDate, _) in
                guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: weekStartDate) else { return false }
                return monthInterval.intersects(weekInterval)
            }
            
            return weeksThatIntersectMonth.map { (weekStartDate, lists) -> SpendingDataPoint in
                let total = lists.reduce(0.0) { $0 + $1.items.filter { $0.isBought && $0.price != nil }.reduce(0.0) { $0 + $1.price! } }
                let weekInterval = calendar.dateInterval(of: .weekOfYear, for: weekStartDate)!
                return SpendingDataPoint(id: weekStartDate, startDate: weekStartDate, endDate: weekInterval.end, totalSpent: total)
            }
            .filter { $0.totalSpent > 0 }
            .sorted { $0.startDate < $1.startDate }

        case .monthly:
            guard let yearInterval = calendar.dateInterval(of: .year, for: displayDate) else { return [] }
            let listsInYear = completedLists.filter { yearInterval.contains($0.eventStartDate) }
            let groupedByMonth = Dictionary(grouping: listsInYear) { list -> Date in
                return calendar.date(from: calendar.dateComponents([.year, .month], from: list.eventStartDate))!
            }
            return groupedByMonth.map { (monthStartDate, lists) -> SpendingDataPoint in
                let total = lists.reduce(0.0) { $0 + $1.items.filter { $0.isBought && $0.price != nil }.reduce(0.0) { $0 + $1.price! } }
                let monthInterval = calendar.dateInterval(of: .month, for: monthStartDate)!
                return SpendingDataPoint(id: monthStartDate, startDate: monthStartDate, endDate: monthInterval.end, totalSpent: total)
            }
            .filter { $0.totalSpent > 0 }
            .sorted { $0.startDate < $1.startDate }
        }
    }
    
    private var closestPointData: (point: SpendingDataPoint, position: CGPoint)? {
        guard let dragLocation, !chartData.isEmpty, canvasSize != .zero else { return nil }

        let (origin, graphSize) = chartGeometry(for: canvasSize)
        
        let allPossibleSlots = selectedMode == .weekly ? getWeeks(for: displayDate) : (1...12).map { Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: displayDate), month: $0, day: 1))! }
        let totalSlots = allPossibleSlots.count
        
        let barWidth = calculateBarWidth(graphWidth: graphSize.width, totalSlots: totalSlots)
        let totalBarAndSpacingWidth = barWidth + 5

        let rawIndex = (dragLocation.x - origin.x) / totalBarAndSpacingWidth
        let potentialIndex = Int(rawIndex.rounded())
        
        guard let dataPoint = chartData.min(by: {
            abs(index(for: $0.startDate) - potentialIndex) < abs(index(for: $1.startDate) - potentialIndex)
        }) else { return nil }
        
        let finalIndex = index(for: dataPoint.startDate)
        let yRange = 0.0...(yAxisUpperBound())
        
        let yPos = yPosition(for: dataPoint.totalSpent, inYRange: yRange, graphHeight: graphSize.height, originY: origin.y)
        let xPos = origin.x + CGFloat(finalIndex) * totalBarAndSpacingWidth + (barWidth / 2)
        
        return (point: dataPoint, position: CGPoint(x: xPos, y: yPos))
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            ThemeBackgroundView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                customToolbar
                    .padding(.horizontal)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        modePicker
                        
                        if shoppingLists.filter({ $0.isCompleted }).isEmpty {
                            emptyStateView
                        } else {
                            spendingChart
                        }
                    }
                    .padding()
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
    }

    // MARK: - Subviews

    @ViewBuilder
    private var customToolbar: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onDismiss) {
                    HStack { Image(systemName: "chevron.backward"); Text("All Lists") }
                }
                .padding(.horizontal, 10).padding(.vertical, 5).glassCardStyle(cornerRadius: 20)
                
                Spacer()
                Text("List Analytics").font(.headline)
                Spacer()
                
                Button(action: {}) {
                    HStack { Image(systemName: "chevron.backward"); Text("All Lists") }
                }.padding(.horizontal, 10).padding(.vertical, 5).hidden()
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding(.top, 10)
            
            navigationHeader
        }
    }
    
    private var navigationHeader: some View {
        HStack {
            Button(action: { navigate(by: -1) }) {
                Image(systemName: "chevron.left")
            }
            
            Spacer()
            
            Text(navigationTitle)
                .font(.headline.weight(.semibold))
                .contentTransition(.interpolate)
            
            Spacer()
            
            Button(action: { navigate(by: 1) }) {
                Image(systemName: "chevron.right")
            }
            .disabled(isNextPeriodInFuture())
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding(.horizontal)
    }

    private var navigationTitle: String {
        let formatter = DateFormatter()
        switch selectedMode {
        case .weekly:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: displayDate)
        case .monthly:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: displayDate)
        }
    }
    
    // --- 👇 НАЧАЛО НА ПРОМЯНАТА 👇 ---
    private var modePicker: some View {
        WrappingSegmentedControl(selection: $selectedMode, layoutMode: .wrap)
    }
    // --- 👆 КРАЙ НА ПРОМЯНАТА 👆 ---
    
    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Spending Data", systemImage: "chart.bar.xaxis.ascending")
        } description: {
            Text("No completed lists with prices found for this period.")
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
        .padding(.vertical, 50).glassCardStyle(cornerRadius: 20)
    }

    @ViewBuilder
    private var spendingChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedMode == .weekly ? "Weekly Spending" : "Monthly Spending")
                    .font(.headline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                Spacer()
                Text("(\(GlobalState.currencyCode))")
                    .font(.subheadline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            }

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    if canvasSize != size {
                        DispatchQueue.main.async { self.canvasSize = size }
                    }
                    
                    let (origin, graphSize) = chartGeometry(for: size)
                    let yRange = 0.0...yAxisUpperBound()
                    let yValues = yAxisValues(upperBound: yRange.upperBound)

                    drawGridAndLabels(context: &context, origin: origin, graphSize: graphSize, yAxisLabels: yValues, yRange: yRange)
                    drawBars(context: &context, origin: origin, graphSize: graphSize, yRange: yRange)
                    
                    if let closestData = self.closestPointData {
                        drawInteractionIndicator(context: &context, position: closestData.position, graphTopY: origin.y - graphSize.height, graphBottomY: origin.y)
                    }
                }
                .frame(height: 300)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in dragLocation = value.location }
                        .onEnded { _ in dragLocation = nil }
                )

                if let closestData = self.closestPointData {
                    bubble(for: closestData.point)
                        .position(self.bubblePosition(for: closestData.position))
                        .transition(.opacity.animation(.easeInOut(duration: 0.1)))
                }
            }
            .clipped()
            .id(selectedMode.rawValue + displayDate.description)
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }
    
    @ViewBuilder
    private func bubble(for p: SpendingDataPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bubbleDateTitle(for: p))
                .font(.caption)
            Text("Spent: \(p.totalSpent, format: .currency(code: GlobalState.currencyCode))")
                .font(.caption.bold())
        }
        .padding(10)
        .frame(minWidth: 140)
        .fixedSize(horizontal: true, vertical: false)
        .glassCardStyle(cornerRadius: 14)
        .foregroundStyle(effectManager.currentGlobalAccentColor)
    }
    
    private func bubbleDateTitle(for p: SpendingDataPoint) -> String {
        let formatter = DateFormatter()
        switch selectedMode {
        case .weekly:
            formatter.dateFormat = "MMM d"
            let actualEndDate = Calendar.current.date(byAdding: .day, value: -1, to: p.endDate)!
            return "\(formatter.string(from: p.startDate)) - \(formatter.string(from: actualEndDate))"
        case .monthly:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: p.startDate)
        }
    }
    
    private func bubblePosition(for pointPosition: CGPoint) -> CGPoint {
        let bubbleHeight: CGFloat = 60
        let (origin, graphSize) = chartGeometry(for: canvasSize)
        
        let graphTopY = origin.y - graphSize.height
        let spaceAbove = pointPosition.y - graphTopY
        let finalY = (spaceAbove > bubbleHeight + 12)
            ? pointPosition.y - 12 - bubbleHeight / 2
            : pointPosition.y + 12 + bubbleHeight / 2
        
        let bubbleWidth: CGFloat = 140
        let containerWidth = (canvasSize.width > 0) ? canvasSize.width : (UIScreen.main.bounds.width - 64)
        let isLeft = pointPosition.x < containerWidth / 2
        let targetX = isLeft
            ? pointPosition.x + 12 + bubbleWidth / 2
            : pointPosition.x - 12 - bubbleWidth / 2
        
        return CGPoint(x: targetX, y: finalY)
    }

    private func navigate(by amount: Int) {
        let component: Calendar.Component = selectedMode == .weekly ? .month : .year
        if let newDate = Calendar.current.date(byAdding: component, value: amount, to: displayDate) {
            withAnimation {
                displayDate = newDate
            }
        }
    }
    
    private func isNextPeriodInFuture() -> Bool {
        let component: Calendar.Component = selectedMode == .weekly ? .month : .year
        guard let nextPeriod = Calendar.current.date(byAdding: component, value: 1, to: displayDate) else { return true }
        return nextPeriod > Date()
    }

    private let chartPadding = EdgeInsets(top: 20, leading: 10, bottom: 40, trailing: 40)
    
    private func chartGeometry(for size: CGSize) -> (origin: CGPoint, size: CGSize) {
        let origin = CGPoint(x: chartPadding.leading, y: size.height - chartPadding.bottom)
        let graphSize = CGSize(width: size.width - chartPadding.leading - chartPadding.trailing, height: size.height - chartPadding.top - chartPadding.bottom)
        return (origin, graphSize)
    }

    private func yPosition(for value: Double, inYRange: ClosedRange<Double>, graphHeight: CGFloat, originY: CGFloat) -> CGFloat {
        let domainSize = inYRange.upperBound - inYRange.lowerBound
        guard domainSize > 0, graphHeight > 0 else { return originY }
        let normalizedValue = (value - inYRange.lowerBound) / domainSize
        return originY - (CGFloat(normalizedValue) * graphHeight)
    }
    
    private func yAxisUpperBound() -> Double {
        let maxData = chartData.map(\.totalSpent).max() ?? 0
        return maxData == 0 ? 10 : maxData * 1.2
    }

    private func yAxisValues(upperBound: Double) -> [Double] {
        let range = max(upperBound, 1); let lines = 5.0; let raw = range / lines; let mag = pow(10.0, floor(log10(max(raw, .leastNonzeroMagnitude)))); let candidates = [1.0, 2.0, 2.5, 5.0, 10.0].map { $0 * mag }; let step = candidates.first { $0 >= raw } ?? raw; guard step > 0 else { return [] }; let end = (range / step).rounded(.up) * step; return stride(from: 0, through: end, by: step).map { $0 }
    }
    
    private func calculateBarWidth(graphWidth: CGFloat, totalSlots: Int) -> CGFloat {
        guard totalSlots > 0 else { return 0 }
        let spacing: CGFloat = 5
        return max(5, (graphWidth - (spacing * CGFloat(totalSlots - 1))) / CGFloat(totalSlots))
    }
    
    private func index(for date: Date) -> Int {
        let calendar = Calendar.current
        switch selectedMode {
        case .weekly:
            let allWeeksInMonth = getWeeks(for: displayDate)
            return allWeeksInMonth.firstIndex(of: calendar.dateInterval(of: .weekOfYear, for: date)!.start) ?? 0
        case .monthly:
            return (calendar.component(.month, from: date) - 1)
        }
    }
    
    private func drawGridAndLabels(context: inout GraphicsContext, origin: CGPoint, graphSize: CGSize, yAxisLabels: [Double], yRange: ClosedRange<Double>) {
        let accent = effectManager.currentGlobalAccentColor
        for value in yAxisLabels {
            let yPos = yPosition(for: value, inYRange: yRange, graphHeight: graphSize.height, originY: origin.y)
            var path = Path(); path.move(to: CGPoint(x: origin.x, y: yPos)); path.addLine(to: CGPoint(x: origin.x + graphSize.width, y: yPos))
            context.stroke(path, with: .color(accent.opacity(0.2)), style: StrokeStyle(lineWidth: 0.5, dash: [4]))
            let labelText = Text(value.clean).font(.caption2).foregroundColor(accent.opacity(0.8))
            context.draw(labelText, at: CGPoint(x: origin.x + graphSize.width + 20, y: yPos), anchor: .center)
        }
    }
    
    private func drawBars(context: inout GraphicsContext, origin: CGPoint, graphSize: CGSize, yRange: ClosedRange<Double>) {
        let calendar = Calendar.current
        let accent = effectManager.currentGlobalAccentColor
        
        let allPossibleSlots: [Date]
        
        switch selectedMode {
        case .weekly:
            allPossibleSlots = getWeeks(for: displayDate)
        case .monthly:
            allPossibleSlots = (1...12).compactMap { calendar.date(from: DateComponents(year: calendar.component(.year, from: displayDate), month: $0, day: 1)) }
        }
        
        let totalSlots = allPossibleSlots.count
        guard totalSlots > 0 else { return }

        let barWidth = calculateBarWidth(graphWidth: graphSize.width, totalSlots: totalSlots)
        let totalBarAndSpacingWidth = barWidth + 5

        let dataMap = Dictionary(uniqueKeysWithValues: chartData.map { ($0.startDate, $0) })

        for (index, slotDate) in allPossibleSlots.enumerated() {
            let xPos = origin.x + CGFloat(index) * totalBarAndSpacingWidth
            let labelText: String
            let labelFormatter = DateFormatter()

            switch selectedMode {
            case .weekly:
                guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: slotDate) else { continue }
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                
                let startText = Text(formatter.string(from: weekInterval.start)).font(.system(size: 10)).foregroundColor(accent.opacity(0.8))
                let endText = Text(formatter.string(from: weekInterval.end.addingTimeInterval(-1))).font(.system(size: 10)).foregroundColor(accent.opacity(0.8))
                
                context.draw(startText, at: CGPoint(x: xPos + barWidth / 2, y: origin.y + 12), anchor: .center)
                context.draw(endText, at: CGPoint(x: xPos + barWidth / 2, y: origin.y + 24), anchor: .center)

            case .monthly:
                labelFormatter.dateFormat = "MMM"
                labelText = labelFormatter.string(from: slotDate)
                context.draw(Text(labelText).font(.caption2).foregroundColor(accent.opacity(0.8)), at: CGPoint(x: xPos + barWidth / 2, y: origin.y + 12), anchor: .center)
            }
            
            if let dataPoint = dataMap[slotDate] {
                let barHeight = (dataPoint.totalSpent / yRange.upperBound) * Double(graphSize.height)
                let yPos = origin.y - CGFloat(barHeight)
                
                let barRect = CGRect(x: xPos, y: yPos, width: barWidth, height: CGFloat(barHeight))
                let barPath = Path(roundedRect: barRect, cornerRadius: 4)
                
                let gradientData = Gradient(colors: [accent.opacity(0.8), accent])
                let shading = GraphicsContext.Shading.linearGradient(gradientData, startPoint: CGPoint(x: barRect.midX, y: barRect.minY), endPoint: CGPoint(x: barRect.midX, y: barRect.maxY))
                context.fill(barPath, with: shading)
            }
        }
    }
    
    private func drawInteractionIndicator(context: inout GraphicsContext, position: CGPoint, graphTopY: CGFloat, graphBottomY: CGFloat) {
        let accent = effectManager.currentGlobalAccentColor
        var vLine = Path(); vLine.move(to: CGPoint(x: position.x, y: graphTopY)); vLine.addLine(to: CGPoint(x: position.x, y: graphBottomY))
        context.stroke(vLine, with: .color(accent.opacity(0.4)), lineWidth: 1)
        
        let dotRect = CGRect(center: position, radius: 5)
        context.fill(Path(ellipseIn: dotRect), with: .color(accent))
        context.stroke(Path(ellipseIn: dotRect), with: .color(.white.opacity(0.8)), lineWidth: 2)
    }
}
