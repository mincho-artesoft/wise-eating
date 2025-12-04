import SwiftUI
import SwiftData

fileprivate enum HistoryNavigation: Hashable {
    case growthChart
}

struct WeightHeightHistoryView: View {
    @Bindable var profile: Profile
       @Environment(\.modelContext) private var modelContext
       @ObservedObject private var effectManager = EffectManager.shared

       @Binding var navBarIsHiden: Bool
       @Binding var isProfilesDrawerVisible: Bool   // 👈 NEW
       @Binding var menuState: MenuState
       let onDismiss: () -> Void

       enum TimeRange: String, CaseIterable, Identifiable {
           case week = "Week", month = "Month", year = "Year", all = "All Time"
           var id: Self { self }
       }

       @State private var path = NavigationPath()
       @State private var selectedTimeRange: TimeRange = .all
       @State private var visibleMetrics: Set<String> = ["Weight", "Height"]
       @State private var isHiden: Bool = true

       @State private var canvasSize: CGSize = .zero
       @State private var dragLocation: CGPoint?
       @State private var pinnedPointData: (date: Date, metrics: [PlottableMetric], indicatorPosition: CGPoint)? = nil
       @State private var hasPinnedInitialPoint = false
       private let bubbleSize = CGSize(width: 160, height: 120)

       @State private var isAddButtonVisible: Bool = true
       @State private var buttonOffset: CGSize = .zero
       @State private var isDragging: Bool = false
       @GestureState private var gestureDragOffset: CGSize = .zero
       @State private var isPressed: Bool = false
       private let buttonPositionKey = "weightHeightHistoryFloatingButtonPosition"

       @State private var isShowingDeleteConfirmation = false
       @State private var recordToDelete: WeightHeightRecord? = nil

       private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
       private var weightUnit: String { isImperial ? "lbs" : "kg" }
       private var heightUnit: String { isImperial ? "in" : "cm" }

       private var baseHistory: [WeightHeightRecord] {
           profile.weightHeightHistory.sorted { $0.date < $1.date }
       }
       private var filteredHistory: [WeightHeightRecord] {
           guard selectedTimeRange != .all else { return baseHistory }
           let now = Date()
           let start: Date? = {
               switch selectedTimeRange {
               case .week:  return Calendar.current.date(byAdding: .day,  value: -7,  to: now)
               case .month: return Calendar.current.date(byAdding: .month, value: -1, to: now)
               case .year:  return Calendar.current.date(byAdding: .year, value: -1, to: now)
               case .all:   return nil
               }
           }()
           return start != nil ? baseHistory.filter { $0.date >= start! } : baseHistory
       }

       private var plottableData: [PlottableMetric] {
           filteredHistory.flatMap { rec -> [PlottableMetric] in
               var arr: [PlottableMetric] = []
               let displayedWeight = isImperial ? UnitConversion.kgToLbs(rec.weight) : rec.weight
               let displayedHeight = isImperial ? UnitConversion.cmToInches(rec.height) : rec.height
               arr.append(.init(date: rec.date, metricName: "Weight", value: displayedWeight))
               arr.append(.init(date: rec.date, metricName: "Height", value: displayedHeight))
               if let hc = rec.headCircumference {
                   let displayedHC = isImperial ? UnitConversion.cmToInches(hc) : hc
                   arr.append(.init(date: rec.date, metricName: "Head Circ.", value: displayedHC))
               }
               for (k, v) in rec.customMetrics {
                   arr.append(.init(date: rec.date, metricName: k.capitalized, value: v))
               }
               return arr
           }
       }
       private var finalPlottableData: [PlottableMetric] {
           plottableData.filter { visibleMetrics.contains($0.metricName) }
       }
       private var allMetricKeys: [String] {
           let core = ["Weight", "Height", "Head Circ."]
           let rest = Set(plottableData.map(\.metricName)).subtracting(core).sorted()
           return core.filter { key in plottableData.contains { $0.metricName == key } } + rest
       }
       private var isSingleDayRange: Bool {
           guard let firstDate = filteredHistory.first?.date, let lastDate = filteredHistory.last?.date else { return false }
           return Calendar.current.isDate(firstDate, inSameDayAs: lastDate)
       }
       private var closestPointData: (date: Date, metrics: [PlottableMetric], indicatorPosition: CGPoint)? {
           guard let dragLocation, !finalPlottableData.isEmpty else { return nil }
           let size = canvasSize == .zero ? CGSize(width: UIScreen.main.bounds.width - 64, height: 250) : canvasSize
           let (origin, graphSize) = chartGeometry(for: size)
           guard let firstDate = finalPlottableData.first?.date, let lastDate = finalPlottableData.last?.date else { return nil }
           let totalDuration = lastDate.timeIntervalSince(firstDate)
           let yRange = yAxisDomain()

           let pointsWithPositions = finalPlottableData.map { point -> (PlottableMetric, CGPoint) in
               let xPos = (totalDuration > 0)
               ? origin.x + (point.date.timeIntervalSince(firstDate) / totalDuration) * graphSize.width
               : origin.x + graphSize.width / 2
               let yPos = yPosition(for: point.value, inYRange: yRange, graphHeight: graphSize.height, originY: origin.y)
               return (point, CGPoint(x: xPos, y: yPos))
           }
           guard let closestPointWithPos = pointsWithPositions.min(by: { abs($0.1.x - dragLocation.x) < abs($1.1.x - dragLocation.x) }) else { return nil }
           let targetDate = closestPointWithPos.0.date
           let allMetricsForDate = finalPlottableData.filter { $0.date == targetDate }
           return (date: targetDate, metrics: allMetricsForDate, indicatorPosition: closestPointWithPos.1)
       }
       private var dataForBubble: (date: Date, metrics: [PlottableMetric], indicatorPosition: CGPoint)? {
           if let closest = closestPointData { return closest }
           if isHiden { return pinnedPointData }
           return nil
       }

       var body: some View {
           NavigationStack(path: $path) {
               GeometryReader { geometry in
                   ZStack(alignment: .bottomTrailing) {
                       ThemeBackgroundView().ignoresSafeArea()

                       VStack(spacing: 0) {
                           customToolbar
                           if baseHistory.isEmpty {
                               emptyStateView
                           } else {
                               contentView
                           }
                       }

                       if isAddButtonVisible {
                           addButton(geometry: geometry)
                       }
                   }
                   .toolbar(.hidden, for: .navigationBar)
                   .onAppear {
                       navBarIsHiden = true
                       isProfilesDrawerVisible = false  // 👈 hide profiles drawer while viewing history
                       visibleMetrics = Set(allMetricKeys)
                       loadButtonPosition()
                   }
                   .onChange(of: path) { _, newPath in
                       if newPath.isEmpty {
                           withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { isAddButtonVisible = true }
                       }
                   }
                   .onChange(of: allMetricKeys) { _, newKeys in visibleMetrics.formUnion(Set(newKeys)) }
                   .onChange(of: canvasSize) { _, newSize in
                       if !hasPinnedInitialPoint && newSize != .zero {
                           pinLastDataPoint()
                           hasPinnedInitialPoint = true
                       }
                   }
                   .onChange(of: selectedTimeRange) { _, _ in
                       pinnedPointData = nil
                       hasPinnedInitialPoint = false
                   }
                   .onChange(of: isHiden) { _, newValue in
                       if !newValue { pinnedPointData = nil } else { pinLastDataPoint() }
                   }
               }
               .navigationDestination(for: WeightHeightRecord.self) { record in
                   AddWeightHeightRecordView(profile: profile, record: record, isNew: !baseHistory.contains { $0.id == record.id })
               }
               .navigationDestination(for: HistoryNavigation.self) { destination in
                   switch destination {
                   case .growthChart:
                       GrowthChartView(profile: profile)
                   }
               }
               .alert("Delete Record", isPresented: $isShowingDeleteConfirmation) {
                   Button("Delete", role: .destructive) {
                       if let record = recordToDelete { delete(record: record) }
                       recordToDelete = nil
                   }
                   Button("Cancel", role: .cancel) { recordToDelete = nil }
               } message: {
                   let dateString = recordToDelete?.date.formatted(date: .abbreviated, time: .shortened) ?? "this record"
                   Text("Are you sure you want to delete the record from \(dateString)? This action cannot be undone.")
               }
           }
       }
    
    // MARK: - Subviews
    private var emptyStateView: some View {
       ContentUnavailableView("No History Found", systemImage: "chart.xyaxis.line", description: Text("Add a record to see the history for \(profile.name)."))
       .foregroundStyle(effectManager.currentGlobalAccentColor)
       .frame(maxHeight: .infinity)
    }
   
    private var contentView: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 24) {
                    timeRangePicker.padding([.top, .horizontal])
                    combinedChartView.padding(.horizontal)
                    customLegendView.padding(.horizontal)
                }
            }
            .listRowSeparator(.hidden).listRowBackground(Color.clear).listRowInsets(EdgeInsets()).padding(.bottom, 16)
            
            Section {
                Text("History Records").font(.headline).padding([.horizontal]).padding(.bottom, 8).foregroundStyle(effectManager.currentGlobalAccentColor)
                    .listRowSeparator(.hidden).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0)).padding(.horizontal)

                ForEach(filteredHistory.reversed()) { rec in
                    historyRow(for: rec).padding(.horizontal).padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { isAddButtonVisible = false }
                            path.append(rec)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            // --- НАЧАЛО НА ПРОМЯНАТА ---
                            Button(role: .destructive) {
                                if #available(iOS 26.0, *) {
                                    delete(record: rec)
                                } else {
                                    self.recordToDelete = rec
                                    self.isShowingDeleteConfirmation = true
                                }
                            } label: {
                                Image(systemName: "trash.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                            }
                            .tint(.clear)
                            // --- КРАЙ НА ПРОМЯНАТА ---
                        }
                        .listRowSeparator(.hidden).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }
            Section { Color.clear.frame(height: 150) }.listRowSeparator(.hidden).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
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
    }

    @ViewBuilder
    private var combinedChartView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Metric Trends").font(.headline).foregroundStyle(effectManager.currentGlobalAccentColor)
                Spacer()
                Toggle("", isOn: $isHiden).padding(.horizontal, 4).foregroundColor(effectManager.currentGlobalAccentColor)
            }.padding(.bottom, 8)
            
            if filteredHistory.count < 2 {
                chartPlaceholder
            } else {
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        if canvasSize != size { DispatchQueue.main.async { self.canvasSize = size } }
                        
                        let (origin, graphSize) = chartGeometry(for: size)
                        let yRange = yAxisDomain()
                        let yValues = yAxisValues(yRange: yRange)
                        
                        drawGridAndLabels(context: &context, origin: origin, graphSize: graphSize, yAxisLabels: yValues, yRange: yRange, accent: effectManager.currentGlobalAccentColor)
                        drawData(context: &context, origin: origin, graphSize: graphSize, yRange: yRange, accent: effectManager.currentGlobalAccentColor)
                        
                        if let interactionData = dataForBubble {
                            drawInteractionIndicator(context: &context, position: interactionData.indicatorPosition, graphTopY: origin.y - graphSize.height, graphBottomY: origin.y, accent: effectManager.currentGlobalAccentColor)
                        }
                    }
                    .frame(height: 250)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in dragLocation = value.location }
                            .onEnded { _ in
                                if let lastHoveredData = closestPointData { pinnedPointData = lastHoveredData }
                                dragLocation = nil
                            }
                    )

                    if let bubbleData = dataForBubble {
                        let (origin, graphSize) = chartGeometry(for: canvasSize)
                        let geometryTuple = (origin: origin, size: graphSize)
                        
                        bubble(for: bubbleData.date, metrics: bubbleData.metrics, accent: effectManager.currentGlobalAccentColor)
                            .position(bubblePosition(for: bubbleData.indicatorPosition, graphGeometry: geometryTuple))
                            .transition(.opacity.animation(.easeInOut(duration: 0.1)))
                    }
                }
                .clipped()
            }
        }
        .padding().glassCardStyle(cornerRadius: 20)
    }
    
    private func bubblePosition(for pointPosition: CGPoint, graphGeometry: (origin: CGPoint, size: CGSize)) -> CGPoint {
        let yPadding: CGFloat = 12
        let xPadding: CGFloat = 12
        let estimatedBubbleHeight = CGFloat(visibleMetrics.count) * 18 + 40
        
        let graphTopY = graphGeometry.origin.y - graphGeometry.size.height
        let spaceAbove = pointPosition.y - graphTopY
        let finalY = (spaceAbove > (estimatedBubbleHeight + yPadding))
            ? pointPosition.y - yPadding - (estimatedBubbleHeight / 2)
            : pointPosition.y + yPadding + (estimatedBubbleHeight / 2)
        
        let graphMinX = graphGeometry.origin.x
        let graphMaxX = graphGeometry.origin.x + graphGeometry.size.width
        let isLeftSide = pointPosition.x < (graphMinX + graphGeometry.size.width / 2)
        let targetX = isLeftSide ? pointPosition.x + xPadding + (bubbleSize.width / 2) : pointPosition.x - xPadding - (bubbleSize.width / 2)
        
        let minBubbleX = graphMinX + (bubbleSize.width / 2)
        let maxBubbleX = graphMaxX - (bubbleSize.width / 2)
        let finalX = targetX.clamped(to: minBubbleX...maxBubbleX)
        
        return CGPoint(x: finalX, y: finalY)
    }

    private var chartPlaceholder: some View {
        ContentUnavailableView("Not Enough Data", systemImage: "chart.bar", description: Text("You need at least two records to show a trend."))
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .frame(height: 250)
    }
    
    private var timeRangePicker: some View {
        WrappingSegmentedControl(selection: $selectedTimeRange, layoutMode: .wrap)

    }
    
    private var customLegendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(allMetricKeys, id: \.self) { key in
                    Button { toggleVisibility(for: key) } label: {
                        HStack(spacing: 4) {
                            Circle().fill(color(for: key)).frame(width: 10, height: 10)
                            Text(key).font(.caption).fontWeight(.medium).foregroundStyle(effectManager.currentGlobalAccentColor)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(visibleMetrics.contains(key) ? Color(color(for: key)).opacity(0.15) : (effectManager.isLightRowTextColor ? .black.opacity(0.15) : .white.opacity(0.15)))
                        .glassCardStyle(cornerRadius: 15)
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(color(for: key).opacity(visibleMetrics.contains(key) ? 0.8 : 0.3), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    
    private func historyRow(for rec: WeightHeightRecord) -> some View {
           let displayedWeight = isImperial ? UnitConversion.kgToLbs(rec.weight) : rec.weight
           let displayedHeight = isImperial ? UnitConversion.cmToInches(rec.height) : rec.height
           let formattedWeight = UnitConversion.formatDecimal(displayedWeight)
           let formattedHeight = UnitConversion.formatDecimal(displayedHeight)

           return HStack(spacing: 16) {
               VStack(alignment: .leading) {
                   Text(rec.date, style: .date).font(.headline).foregroundStyle(effectManager.currentGlobalAccentColor)
                   Text(rec.date, style: .time).font(.caption).foregroundStyle(effectManager.currentGlobalAccentColor)
               }
               Spacer()
               VStack(alignment: .trailing, spacing: 4) {
                   Text("Weight: \(formattedWeight) \(weightUnit)").foregroundStyle(effectManager.currentGlobalAccentColor)
                   Text("Height: \(formattedHeight) \(heightUnit)").foregroundStyle(effectManager.currentGlobalAccentColor)
                   
                   if let hc = rec.headCircumference {
                       let displayedHC = isImperial ? UnitConversion.cmToInches(hc) : hc
                       let formattedHC = UnitConversion.formatDecimal(displayedHC)
                       Text("Head Circ.: \(formattedHC) \(heightUnit)").foregroundStyle(effectManager.currentGlobalAccentColor)
                   }
                   
                   if !rec.customMetrics.isEmpty {
                       ForEach(rec.customMetrics.keys.sorted(), id: \.self) { k in
                           HStack {
                               Text("\(k.capitalized):").foregroundStyle(effectManager.currentGlobalAccentColor)
                               Text(UnitConversion.formatDecimal(rec.customMetrics[k]!)).foregroundStyle(effectManager.currentGlobalAccentColor)
                           }
                       }
                   }
               }
           }.padding().glassCardStyle(cornerRadius: 20)
       }
    private var hasDataForGrowthChart: Bool {
          let calendar = Calendar.current
          return profile.weightHeightHistory.contains { record in
              let ageInMonths = calendar.dateComponents([.month], from: profile.birthday, to: record.date).month ?? -1
              return ageInMonths >= 0 && ageInMonths <= 24
          }
      }
    @ViewBuilder
        private var customToolbar: some View {
            HStack {
                HStack { Button("Cancel") { onDismiss() } }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                
                Spacer()
                
                Text("Metrics History").font(.headline).foregroundStyle(effectManager.currentGlobalAccentColor)
                
                Spacer()
                
                HStack {
                    if hasDataForGrowthChart {
                        Button {
                            withAnimation {
                                path.append(HistoryNavigation.growthChart)
                            }
                        } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                        }
                    } else {
                        Image(systemName: "chart.line.uptrend.xyaxis").hidden()
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .opacity(hasDataForGrowthChart ? 1.0 : 0.0)
            }
            .padding(.horizontal).padding(.top, 10).padding(.bottom, 8)
        }

    @ViewBuilder
    private func bubble(for date: Date, metrics: [PlottableMetric], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.formatted(.dateTime.day().month().year().hour().minute()))
                .font(.caption)
                .foregroundStyle(accent)
            
            ForEach(metrics.sorted(by: { $0.metricName < $1.metricName })) { p in
                HStack {
                    Circle().fill(color(for: p.metricName)).frame(width: 8, height: 8)
                    Text("\(p.metricName):").foregroundStyle(accent)
                    Spacer()
                    Text(format(p.value, for: p.metricName)).bold().foregroundStyle(accent)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .frame(width: bubbleSize.width)
        .glassCardStyle(cornerRadius: 14)
    }

    // MARK: - Floating Button Logic
    private func dragGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($gestureDragOffset) { value, state, _ in state = value.translation; DispatchQueue.main.async { self.isPressed = true } }
            .onChanged { value in if abs(value.translation.width) > 10 || abs(value.translation.height) > 10 { self.isDragging = true } }
            .onEnded { value in
                self.isPressed = false
                if isDragging {
                    var newOffset = self.buttonOffset
                    newOffset.width += value.translation.width; newOffset.height += value.translation.height
                    let buttonRadius: CGFloat = 40, viewSize = geometry.size, safeArea = geometry.safeAreaInsets
                    let minY = -viewSize.height + buttonRadius + safeArea.top, maxY = safeArea.bottom - 25
                    newOffset.height = min(max(minY, newOffset.height), maxY)
                    self.buttonOffset = newOffset
                    self.saveButtonPosition()
                } else { Task { await self.handleButtonTap() } }
                self.isDragging = false
            }
    }
    
    private func addButton(geometry: GeometryProxy) -> some View {
        let currentOffset = CGSize(width: buttonOffset.width + gestureDragOffset.width, height: buttonOffset.height + gestureDragOffset.height)
        let scale = isDragging ? 1.15 : (isPressed ? 0.9 : 1.0)
        return ZStack { Image(systemName: "plus").font(.title3).foregroundColor(effectManager.currentGlobalAccentColor) }
            .frame(width: 60, height: 60).glassCardStyle(cornerRadius: 32).scaleEffect(scale)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging).animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .contentShape(Rectangle()).padding(.trailing, trailingPadding(for: geometry)).padding(.bottom, bottomPadding(for: geometry))
            .offset(currentOffset).gesture(dragGesture(geometry: geometry)).transition(.scale.combined(with: .opacity))
    }
    
    private func handleButtonTap() async {
            withAnimation(.easeInOut(duration: 0.3)) { isAddButtonVisible = false }
            let lastRecord = baseHistory.last
            
            let newRecord = WeightHeightRecord(
                date: Date(),
                weight: lastRecord?.weight ?? profile.weight,
                height: lastRecord?.height ?? profile.height,
                headCircumference: lastRecord?.headCircumference
            )

            newRecord.customMetrics = lastRecord?.customMetrics ?? [:]
            path.append(newRecord)
        }
    
    private func bottomPadding(for geometry: GeometryProxy) -> CGFloat { (geometry.size.width > 0 && (geometry.size.height / geometry.size.width) > 1.9) ? 75 : 95 }
    private func trailingPadding(for geometry: GeometryProxy) -> CGFloat { 45 }
    private func saveButtonPosition() { UserDefaults.standard.set(buttonOffset.width, forKey: "\(buttonPositionKey)_width"); UserDefaults.standard.set(buttonOffset.height, forKey: "\(buttonPositionKey)_height") }
    private func loadButtonPosition() { self.buttonOffset = CGSize(width: UserDefaults.standard.double(forKey: "\(buttonPositionKey)_width"), height: UserDefaults.standard.double(forKey: "\(buttonPositionKey)_height")) }
    
    // MARK: - Helper Functions & Drawing Logic
    private let chartPadding = EdgeInsets(top: 20, leading: 10, bottom: 30, trailing: 40)
    private func chartGeometry(for size: CGSize) -> (origin: CGPoint, size: CGSize) { (CGPoint(x: chartPadding.leading, y: size.height - chartPadding.bottom), CGSize(width: size.width - chartPadding.leading - chartPadding.trailing, height: size.height - chartPadding.top - chartPadding.bottom)) }
    private func yPosition(for value: Double, inYRange: ClosedRange<Double>, graphHeight: CGFloat, originY: CGFloat) -> CGFloat {
        let domainSize = inYRange.upperBound - inYRange.lowerBound
        guard domainSize > 0, graphHeight > 0 else { return originY }
        let normalizedValue = (value - inYRange.lowerBound) / domainSize
        return originY - (CGFloat(normalizedValue) * graphHeight)
    }
    private func yAxisDomain() -> ClosedRange<Double> {
        let values = finalPlottableData.map(\.value)
        guard let minVal = values.min(), let maxVal = values.max() else { return 0...100 }
        let padding = max((maxVal - minVal) * 0.1, 1.0)
        return max(0, minVal - padding)...(maxVal + padding)
    }
    private func yAxisValues(yRange: ClosedRange<Double>) -> [Double] {
        let range = yRange.upperBound - yRange.lowerBound
        let desiredLines = 5.0; let rawStep = range / desiredLines; let mag = pow(10.0, floor(log10(max(rawStep, .leastNonzeroMagnitude)))); let candidates = [1.0, 2.0, 2.5, 5.0, 10.0].map { $0 * mag }; let step = candidates.first { $0 >= rawStep } ?? rawStep
        guard step > 0 else { return [] }
        let start = floor(yRange.lowerBound / step) * step; let end = ceil(yRange.upperBound / step) * step
        return stride(from: start, through: end, by: step).map { $0 }
    }

    private func generateXAxisLabels() -> [(value: Double, label: String)] {
        guard let firstDate = filteredHistory.first?.date, let lastDate = filteredHistory.last?.date else { return [] }
        
        if isSingleDayRange {
            let calendar = Calendar.current
            let startHour = calendar.component(.hour, from: firstDate)
            let endHour = calendar.component(.hour, from: lastDate)
            let hourRange = max(1, endHour - startHour)
            let step = max(1, hourRange / 4)

            var labels: [(Double, String)] = []
            for hour in stride(from: startHour, through: endHour + 1, by: step) {
                if let dateForHour = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: firstDate) {
                    labels.append((dateForHour.timeIntervalSince1970, dateForHour.formatted(.dateTime.hour().minute())))
                }
            }
            return labels
        } else {
            let formatter = DateFormatter(); formatter.dateFormat = "MMM d"
            var labels: [(Double, String)] = []
            labels.append((firstDate.timeIntervalSince1970, formatter.string(from: firstDate)))
            if !Calendar.current.isDate(firstDate, inSameDayAs: lastDate) {
                labels.append((lastDate.timeIntervalSince1970, formatter.string(from: lastDate)))
            }
            return labels
        }
    }

    private func value(for key: String, in record: WeightHeightRecord) -> Double? {
        switch key {
        case "Weight": return isImperial ? UnitConversion.kgToLbs(record.weight) : record.weight
        case "Height": return isImperial ? UnitConversion.cmToInches(record.height) : record.height
        default: return record.customMetrics.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
        }
    }
    private func toggleVisibility(for key: String) { if visibleMetrics.contains(key) { visibleMetrics.remove(key) } else { visibleMetrics.insert(key) } }
    private func color(for key: String) -> Color { let palette: [Color] = [.blue, .green, .orange, .red, .purple, .brown, .cyan, .mint, .pink, .indigo]; let idx = allMetricKeys.firstIndex(of: key) ?? 0; return palette[idx % palette.count] }
    private func format(_ v: Double, for key: String) -> String {
          switch key {
          case "Weight": return "\(UnitConversion.formatDecimal(v)) \(weightUnit)"
          case "Height": return "\(UnitConversion.formatDecimal(v)) \(heightUnit)"
          case "Head Circ.": return "\(UnitConversion.formatDecimal(v)) \(heightUnit)"
          default: return UnitConversion.formatDecimal(v)
          }
      }
    private func delete(record: WeightHeightRecord) { withAnimation { modelContext.delete(record); try? modelContext.save() } }
    
    private func pinLastDataPoint() {
        guard let lastRecord = filteredHistory.last,
              let firstDate = finalPlottableData.first?.date,
              let lastDate = finalPlottableData.last?.date
        else {
            pinnedPointData = nil
            return
        }
        
        let allMetricsForLastDate = finalPlottableData.filter { $0.date == lastRecord.date }
        guard !allMetricsForLastDate.isEmpty else { return }
        
        let size = canvasSize
        guard size != .zero else { return }
        
        let (origin, graphSize) = chartGeometry(for: size)
        let totalDuration = lastDate.timeIntervalSince(firstDate)
        let yRange = yAxisDomain()

        let xPos = (totalDuration > 0) ? origin.x + (lastRecord.date.timeIntervalSince(firstDate) / totalDuration) * graphSize.width : origin.x + graphSize.width / 2
        let yPos = yPosition(for: allMetricsForLastDate[0].value, inYRange: yRange, graphHeight: graphSize.height, originY: origin.y)
        
        pinnedPointData = (date: lastRecord.date, metrics: allMetricsForLastDate, indicatorPosition: CGPoint(x: xPos, y: yPos))
    }
}

// MARK: - Canvas Drawing Extension
private extension WeightHeightHistoryView {
    func drawGridAndLabels(context: inout GraphicsContext, origin: CGPoint, graphSize: CGSize, yAxisLabels: [Double], yRange: ClosedRange<Double>, accent: Color) {
        for value in yAxisLabels {
            let yPos = yPosition(for: value, inYRange: yRange, graphHeight: graphSize.height, originY: origin.y)
            var path = Path(); path.move(to: CGPoint(x: origin.x, y: yPos)); path.addLine(to: CGPoint(x: origin.x + graphSize.width, y: yPos))
            context.stroke(path, with: .color(accent.opacity(0.2)), style: StrokeStyle(lineWidth: 0.5, dash: [4]))
            context.draw(Text(value.clean).font(.caption2).foregroundColor(accent.opacity(0.8)), at: CGPoint(x: origin.x + graphSize.width + 20, y: yPos), anchor: .center)
        }
        
        guard let firstDate = filteredHistory.first?.date, let lastDate = filteredHistory.last?.date else { return }
        let totalDuration = lastDate.timeIntervalSince(firstDate)
        
        for (value, label) in generateXAxisLabels() {
            let date = Date(timeIntervalSince1970: value)
            let xPos = (totalDuration > 0) ? origin.x + (date.timeIntervalSince(firstDate) / totalDuration) * graphSize.width : origin.x + graphSize.width / 2
            
            let isFirst = abs(date.timeIntervalSince(firstDate)) < 1
            let isLast = abs(date.timeIntervalSince(lastDate)) < 1
            let anchor: UnitPoint = isFirst ? .leading : (isLast ? .trailing : .center)

            context.draw(Text(label).font(.caption2).foregroundColor(accent.opacity(0.8)), at: CGPoint(x: xPos, y: origin.y + 12), anchor: anchor)
        }
    }

    func drawData(context: inout GraphicsContext, origin: CGPoint, graphSize: CGSize, yRange: ClosedRange<Double>, accent: Color) {
        guard let firstDate = finalPlottableData.first?.date, let lastDate = finalPlottableData.last?.date else { return }
        let totalDuration = lastDate.timeIntervalSince(firstDate)
        let dataByMetric = Dictionary(grouping: finalPlottableData, by: { $0.metricName })

        for (metricName, points) in dataByMetric {
            var path = Path()
            for (index, point) in points.enumerated() {
                let xPos = (totalDuration > 0) ? origin.x + (point.date.timeIntervalSince(firstDate) / totalDuration) * graphSize.width : origin.x + graphSize.width / 2
                let yPos = yPosition(for: point.value, inYRange: yRange, graphHeight: graphSize.height, originY: origin.y)
                if index == 0 { path.move(to: CGPoint(x: xPos, y: yPos)) } else { path.addLine(to: CGPoint(x: xPos, y: yPos)) }
            }
            context.stroke(path, with: .color(color(for: metricName)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    func drawInteractionIndicator(context: inout GraphicsContext, position: CGPoint, graphTopY: CGFloat, graphBottomY: CGFloat, accent: Color) {
        var vLine = Path(); vLine.move(to: CGPoint(x: position.x, y: graphTopY)); vLine.addLine(to: CGPoint(x: position.x, y: graphBottomY))
        context.stroke(vLine, with: .color(accent.opacity(0.4)), lineWidth: 1)
        let dotRect = CGRect(center: position, radius: 5)
        context.fill(Path(ellipseIn: dotRect), with: .color(accent)); context.stroke(Path(ellipseIn: dotRect), with: .color(.white.opacity(0.8)), lineWidth: 2)
    }
}
