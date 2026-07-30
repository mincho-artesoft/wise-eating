import SwiftUI
import SwiftData

struct AnalyticsChartView: View {
    @State private var canvasSize: CGSize = .zero

    // MARK: - Environment & Managers
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: - Input
    let nutrientID: String
    let points: [PlottableMetric]
    let profile: Profile
    let onDeselect: () -> Void

    // MARK: - Data Queries
    @Query(sort: \Vitamin.name) private var allVitamins: [Vitamin]
    @Query(sort: \Mineral.name) private var allMinerals: [Mineral]

    // MARK: - Interaction State
    @State private var dragLocation: CGPoint?
    
    /// Изчислява коя РЕАЛНА точка е най-близо до плъзгането.
    private var closestPointData: (point: PlottableMetric, position: CGPoint)? {
        guard let dragLocation, !points.isEmpty else { return nil }

        // Ако още не знаем реалния size от Canvas, използваме разумен fallback.
        let size = canvasSize == .zero
            ? CGSize(width: UIScreen.main.bounds.width - 64, height: 250)
            : canvasSize

        let (origin, graphSize) = chartGeometry(for: size)
        let firstDate = points.first?.date ?? Date()
        let lastDate = points.last?.date ?? firstDate
        let totalDuration = lastDate.timeIntervalSince(firstDate)

        let yRange = 0.0...yAxisUpperBound()

        let pointsWithPositions = points.map { point -> (PlottableMetric, CGPoint) in
            let xPos: CGFloat
            if totalDuration > 0 {
                let timeSinceStart = point.date.timeIntervalSince(firstDate)
                xPos = origin.x + (timeSinceStart / totalDuration) * graphSize.width
            } else {
                xPos = origin.x + graphSize.width / 2
            }
            let yPos = yPosition(for: point.value, inYRange: yRange, graphHeight: graphSize.height, originY: origin.y)
            return (point, CGPoint(x: xPos, y: yPos))
        }

        guard let closest = pointsWithPositions.min(by: {
            abs($0.1.x - dragLocation.x) < abs($1.1.x - dragLocation.x)
        }) else {
            return nil
        }

        return (point: closest.0, position: closest.1)
    }


    // MARK: - Body
    var body: some View {
        let requirements = getRequirements(for: nutrientID)
        let accent = effectManager.currentGlobalAccentColor
        let isCaloriesChart = nutrientID == "calories"
        
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                titleRow(accent: accent)

                if points.isEmpty {
                    emptyChartPlaceholder(accent: accent)
                } else {
                    chartContainer(requirements: requirements, accent: accent)

                    chartLegend(
                        requirements: requirements,
                        isCalories: isCaloriesChart,
                        accent: accent
                    )
                    .padding(.top, 8)
                }
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)

            closeButton(accent: accent)
        }
    }

    // MARK: - Subviews
    
    @ViewBuilder
    private func titleRow(accent: Color) -> some View {
        Text(nutrientName(for: nutrientID))
            .font(.headline)
            .foregroundStyle(accent)
    }

    @ViewBuilder
    private func emptyChartPlaceholder(accent: Color) -> some View {
        ContentUnavailableView {
            Label("No Data", systemImage: "chart.bar.xaxis.ascending")
                .foregroundStyle(accent)
        } description: {
            Text("No meal data found for this metric.")
                .foregroundStyle(accent.opacity(0.8))
        }
        .frame(height: 250)
    }
    
    @ViewBuilder
    private func chartContainer(
        requirements: (min: Double?, max: Double?, unit: String?),
        accent: Color
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                // Запазваме реалния размер на канваса за всички други изчисления
                if canvasSize != size {
                    DispatchQueue.main.async { self.canvasSize = size }
                }

                let (origin, graphSize) = chartGeometry(for: size)
                let upperDomainBound = yAxisUpperBound()
                let yValues = yAxisValues(upperBound: upperDomainBound)
                let yRange = 0.0...upperDomainBound

                drawGridAndLabels(
                    context: &context,
                    origin: origin,
                    graphSize: graphSize,
                    yAxisLabels: yValues,
                    xAxisLabels: dateLabels(),
                    yRange: yRange,
                    accent: accent
                )

                drawRequirementLines(
                    context: &context,
                    origin: origin,
                    graphSize: graphSize,
                    requirements: requirements,
                    yRange: yRange,
                    accent: accent
                )

                drawData(
                    context: &context,
                    origin: origin,
                    graphSize: graphSize,
                    yRange: yRange,
                    accent: accent
                )

                if let closestData = closestPointData {
                    drawInteractionIndicator(
                        context: &context,
                        position: closestData.position,
                        graphTopY: origin.y - graphSize.height, // важно: истинският top на графиката
                        graphBottomY: origin.y,
                        accent: accent
                    )
                }
            }
            .frame(height: 250)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragLocation = value.location
                    }
                    .onEnded { _ in
                        dragLocation = nil
                    }
            )

            // Балонче с данни при ховър/драг
            if let closestData = closestPointData {
                let bubbleYOffset = chartPadding.top + 20
                let bubbleWidth: CGFloat = 180
                let bubbleHalfWidth = bubbleWidth / 2

                // Ако още не сме получили real size от Canvas, ползвай разумен fallback.
                let containerWidth = (canvasSize.width > 0) ? canvasSize.width : (UIScreen.main.bounds.width - 64)

                let isLeftSide = closestData.position.x < containerWidth / 2
                let idealX = isLeftSide
                    ? closestData.position.x + bubbleHalfWidth + 12
                    : closestData.position.x - bubbleHalfWidth - 12

                let finalX = idealX.clamped(to: bubbleHalfWidth...(containerWidth - bubbleHalfWidth))

                bubble(for: closestData.point, requirements: requirements, accent: accent)
                    .frame(width: bubbleWidth)
                    .position(x: finalX, y: bubbleYOffset)
                    .transition(.opacity.animation(.easeInOut(duration: 0.1)))
            }
        }
        .clipped()
    }

    
    // +++ НАЧАЛО НА ПРОМЯНАТА (1/2) +++
    @ViewBuilder
    private func bubble(for p: PlottableMetric, requirements: (min: Double?, max: Double?, unit: String?), accent: Color) -> some View {
        // +++ НАЧАЛО НА ПРОМЯНАТА +++
        // Създаваме форматираната дата в локална променлива, преди да конструираме изгледа.
        let formattedDate: String = {
            let formatter = DateFormatter()
            if !GlobalState.dateFormat.isEmpty {
                // Комбинираме глобалния формат за дата с локалния формат за час.
                let timeFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "HH:mm"
                formatter.dateFormat = "\(GlobalState.dateFormat), \(timeFormat)"
            } else {
                // Резервен вариант, ако няма глобален формат.
                formatter.dateStyle = .short
                formatter.timeStyle = .short
            }
            return formatter.string(from: p.date)
        }()
        // +++ КРАЙ НА ПРОМЯНАТА +++

        VStack(alignment: .leading, spacing: 4) {
            // Използваме вече форматираната дата.
            Text(formattedDate)
                .font(.caption)
                .foregroundStyle(accent)
            HStack {
                Text(nutrientName(for: nutrientID))
                    .font(.caption)
                    .foregroundStyle(accent)
                Spacer()
                Text("\(p.value.clean) \(requirements.unit ?? "")")
                    .font(.caption.bold())
                    .foregroundStyle(accent)
            }
        }
        .padding(10)
        .glassCardStyle(cornerRadius: 14)
    }
    // +++ КРАЙ НА ПРОМЯНАТА (1/2) +++

    @ViewBuilder
      private func chartLegend(
          requirements: (min: Double?, max: Double?, unit: String?),
          isCalories: Bool,
          accent: Color
      ) -> some View {
          let isWaterChart = nutrientID == "water"
          let isProteinChart = nutrientID == "protein"
          let isCarbsChart = nutrientID == "carbohydrates"
          let isFatChart = nutrientID == "fat"
          
          HStack {
              HStack(spacing: 24) {
                  if let min = requirements.min {
                      HStack(spacing: 6) {
                          let color = chartColor(for: nutrientID)
                          Circle()
                              .fill(color)
                              .frame(width: 8, height: 8)
                          Text("\(isCalories || isWaterChart || isProteinChart || isCarbsChart || isFatChart ? "Target" : "MIN"): \(min.clean) \(requirements.unit ?? "")")
                              .font(.caption.weight(.semibold))
                              .foregroundStyle(accent)
                      }
                  }
                  if let max = requirements.max, !isCalories, !isWaterChart, !isProteinChart, !isCarbsChart, !isFatChart {
                      HStack(spacing: 6) {
                          Circle()
                              .fill(.red)
                              .frame(width: 8, height: 8)
                          Text("MAX: \(max.clean) \(requirements.unit ?? "")")
                              .font(.caption.weight(.semibold))
                              .foregroundStyle(accent)
                      }
                  }
              }
              Spacer()
          }
          .padding(.horizontal, 4)
      }


    @ViewBuilder
    private func closeButton(accent: Color) -> some View {
        Button(action: onDeselect) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    accent.opacity(0.7),
                    (effectManager.isLightRowTextColor ? Color.black : Color.white).opacity(0.2)
                )
        }
        .buttonStyle(.plain)
        .padding(8)
    }
    
    // MARK: - Helper Functions & Drawing
    
    private let chartPadding = EdgeInsets(top: 20, leading: 10, bottom: 30, trailing: 40)
    
    private func chartGeometry(for size: CGSize = CGSize(width: 300, height: 250)) -> (origin: CGPoint, size: CGSize) {
        let origin = CGPoint(x: chartPadding.leading, y: size.height - chartPadding.bottom)
        let graphSize = CGSize(
            width: size.width - chartPadding.leading - chartPadding.trailing,
            height: size.height - chartPadding.top - chartPadding.bottom
        )
        return (origin, graphSize)
    }

    /// Преобразува стойност от данните в Y координата на екрана.
    private func yPosition(for value: Double, inYRange: ClosedRange<Double>, graphHeight: CGFloat, originY: CGFloat) -> CGFloat {
        let domainSize = inYRange.upperBound - inYRange.lowerBound
        // Предпазваме се от делене на нула, ако всички стойности са еднакви.
        guard domainSize > 0, graphHeight > 0 else { return originY }
        
        let normalizedValue = (value - inYRange.lowerBound) / domainSize
        return originY - (CGFloat(normalizedValue) * graphHeight)
    }

    private func yAxisUpperBound() -> Double {
        let requirements = getRequirements(for: nutrientID)
        let maxData = points.map(\.value).max() ?? 0
        var v = maxData * 1.2
        if let target = requirements.min {
            v = max(v, target * 1.2)
        }
        if let maxReq = requirements.max {
             v = max(v, maxReq * 1.2)
        }
        return v == 0 ? 10 : v
    }

    private func yAxisValues(upperBound: Double) -> [Double] {
        let minVal = 0.0
        let maxVal = max(upperBound, 1);
        let range = maxVal - minVal
        let desiredLines = 5.0
        let rawStep = range / desiredLines
        let mag = pow(10.0, floor(log10(max(rawStep, .leastNonzeroMagnitude))))
        let candidates = [1.0, 2.0, 2.5, 5.0, 10.0].map { $0 * mag }
        let step = candidates.first { $0 >= rawStep } ?? rawStep
        guard step > 0 else { return [] }
        let end = (maxVal / step).rounded(.up) * step
        return stride(from: minVal, through: end, by: step).map { $0 }
    }
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (2/2) +++
    private func dateLabels() -> [(date: Date, label: String)] {
        guard let firstDate = points.first?.date, let lastDate = points.last?.date else { return [] }
        
        let formatter = DateFormatter()
        if !GlobalState.dateFormat.isEmpty {
            formatter.dateFormat = GlobalState.dateFormat
        } else {
            formatter.dateStyle = .short
        }

        var labels = [(Date, String)]()
        labels.append((firstDate, formatter.string(from: firstDate)))
        if !Calendar.current.isDate(firstDate, inSameDayAs: lastDate) {
            labels.append((lastDate, formatter.string(from: lastDate)))
        }
        return labels
    }
    // +++ КРАЙ НА ПРОМЯНАТА (2/2) +++

    private func getRequirements(for nutrientID: String) -> (min: Double?, max: Double?, unit: String?) {
           let demographic = demographicString(for: profile)
           if nutrientID == "calories" {
               return (TDEECalculator.calculate(for: profile, activityLevel: profile.activityLevel), nil, "kcal")
           }
           if nutrientID == "water" {
               let goalInGlasses = calculateWaterGoal(for: profile)
               let goalInMl = Double(goalInGlasses * 200)
               return (goalInMl, nil, "ml")
           }
           if nutrientID == "protein" {
               return (nil, nil, "g")
           }
           if nutrientID == "carbohydrates" {
               return (nil, nil, "g")
           }
           if nutrientID == "fat" {
               return (nil, nil, "g")
           }
        let requirement: Requirement?
        var unit: String?
        if nutrientID.starts(with: "vit_") {
            let id = String(nutrientID.dropFirst(4))
            let vitamin = allVitamins.first { $0.id == id }
            requirement = vitamin?.requirements.first { $0.demographic == demographic }
            unit = vitamin?.unit
        } else if nutrientID.starts(with: "min_") {
            let id = String(nutrientID.dropFirst(4))
            let mineral = allMinerals.first { $0.id == id }
            requirement = mineral?.requirements.first { $0.demographic == demographic }
            unit = mineral?.unit
        } else {
            requirement = nil
            unit = nil
        }
        return (requirement?.dailyNeed, requirement?.upperLimit, unit)
    }

    private func demographicString(for p: Profile) -> String {
        let isF = p.gender.lowercased().hasPrefix("f")
        if isF {
            if p.isPregnant { return Demographic.pregnantWomen }
            if p.isLactating { return Demographic.lactatingWomen }
        }
        let m = Calendar.current.dateComponents([.month], from: p.birthday, to: Date()).month ?? 0
        if m < 6 { return Demographic.babies0_6m }
        if m < 12 { return Demographic.babies7_12m }
        switch p.age {
        case 1..<4: return Demographic.children1_3y
        case 4..<9: return Demographic.children4_8y
        case 9..<14: return Demographic.children9_13y
        case 14..<19: return isF ? Demographic.adolescentFemales14_18y : Demographic.adolescentMales14_18y
        default:
            return isF
            ? (p.age <= 50 ? Demographic.adultWomen19_50y : Demographic.adultWomen51plusY)
            : (p.age <= 50 ? Demographic.adultMen19_50y : Demographic.adultMen51plusY)
        }
    }

    private func nutrientName(for id: String) -> String {
        if id == "calories" { return "Calories" }
        if id == "water" { return "Water Intake" }
        if id == "protein" { return "Protein" }
        if id == "carbohydrates" { return "Carbohydrates" }
        if id == "fat" { return "Fat" }
        if id.starts(with: "vit_") {
            let key = String(id.dropFirst(4))
            return allVitamins.first { $0.id == key }?.name ?? "Unknown Vitamin"
        }
        if id.starts(with: "min_") {
            let key = String(id.dropFirst(4))
            return allMinerals.first { $0.id == key }?.name ?? "Unknown Mineral"
        }
        return "Unknown"
    }
    
    private func calculateWaterGoal(for profile: Profile) -> Int {
        let weight = profile.weight
        let age = profile.age

        let mlPerKg: Double

        switch age {
        case 0...15:
            mlPerKg = 40.0
        case 16...30:
            mlPerKg = 35.0
        case 31...54:
            mlPerKg = 32.5
        case 55...65:
            mlPerKg = 30.0
        default:
            mlPerKg = 25.0
        }

        let totalMilliliters = weight * mlPerKg
        let numberOfGlasses = Int(round(totalMilliliters / 200.0))

        return max(4, numberOfGlasses)
    }
}

// MARK: - Canvas Drawing Extension
private extension AnalyticsChartView {
    
    func drawGridAndLabels(
        context: inout GraphicsContext,
        origin: CGPoint,
        graphSize: CGSize,
        yAxisLabels: [Double],
        xAxisLabels: [(date: Date, label: String)],
        yRange: ClosedRange<Double>,
        accent: Color
    ) {
        // --- Y grid + labels ---
        for value in yAxisLabels {
            let yPos = yPosition(for: value, inYRange: yRange, graphHeight: graphSize.height, originY: origin.y)

            var path = Path()
            path.move(to: CGPoint(x: origin.x, y: yPos))
            path.addLine(to: CGPoint(x: origin.x + graphSize.width, y: yPos))
            context.stroke(path, with: .color(accent.opacity(0.2)), style: StrokeStyle(lineWidth: 0.5, dash: [4]))

            context.draw(
                Text(value.clean)
                    .font(.caption2)
                    .foregroundColor(accent.opacity(0.8)),
                at: CGPoint(x: origin.x + graphSize.width + 20, y: yPos),
                anchor: .center
            )
        }
        
        // --- X labels ---
        guard let firstDate = points.first?.date, let lastDate = points.last?.date else { return }
        let totalDuration = lastDate.timeIntervalSince(firstDate)
        
        for (date, label) in xAxisLabels {
            let xPos: CGFloat
            if totalDuration > 0 {
                let timeSinceStart = date.timeIntervalSince(firstDate)
                let xRatio = timeSinceStart / totalDuration
                xPos = origin.x + xRatio * graphSize.width
            } else {
                xPos = origin.x + graphSize.width / 2
            }

            // Подравняване, за да не се изрязва
            let isFirst = Calendar.current.isDate(date, inSameDayAs: firstDate)
            let isLast  = Calendar.current.isDate(date, inSameDayAs: lastDate)
            let anchor: UnitPoint = isFirst ? .leading : (isLast ? .trailing : .center)

            context.draw(
                Text(label)
                    .font(.caption2)
                    .foregroundColor(accent.opacity(0.8)),
                at: CGPoint(x: xPos, y: origin.y + 12),
                anchor: anchor
            )
        }
    }

    
    func drawRequirementLines(
           context: inout GraphicsContext,
           origin: CGPoint,
           graphSize: CGSize,
           requirements: (min: Double?, max: Double?, unit: String?),
           yRange: ClosedRange<Double>,
           accent: Color
       ) {
           let isCaloriesChart = nutrientID == "calories"
           let isWaterChart = nutrientID == "water"
           let isProteinChart = nutrientID == "protein"
           let isCarbsChart = nutrientID == "carbohydrates"
           let isFatChart = nutrientID == "fat"

           if let min = requirements.min {
               let yPos = yPosition(for: min, inYRange: yRange, graphHeight: graphSize.height, originY: origin.y)
               let color: Color = chartColor(for: nutrientID)
               var path = Path()
               path.move(to: CGPoint(x: origin.x, y: yPos))
               path.addLine(to: CGPoint(x: origin.x + graphSize.width, y: yPos))
               context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
           }

           if let max = requirements.max, !isCaloriesChart, !isWaterChart, !isProteinChart, !isCarbsChart, !isFatChart {
               let yPos = yPosition(for: max, inYRange: yRange, graphHeight: graphSize.height, originY: origin.y)
               var path = Path()
               path.move(to: CGPoint(x: origin.x, y: yPos))
               path.addLine(to: CGPoint(x: origin.x + graphSize.width, y: yPos))
               context.stroke(path, with: .color(.red), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
           }
       }


    func drawData(
        context: inout GraphicsContext,
        origin: CGPoint,
        graphSize: CGSize,
        yRange: ClosedRange<Double>,
        accent: Color
    ) {
        guard !points.isEmpty,
              let firstDate = points.first?.date,
              let lastDate  = points.last?.date
        else { return }

        let isSpecialChart = ["calories", "water", "protein", "carbohydrates", "fat"].contains(nutrientID)
        let totalDuration = lastDate.timeIntervalSince(firstDate)

        // Екранни точки за всяка стойност
        let screenPoints: [CGPoint] = points.map { point in
            let xPos: CGFloat
            if totalDuration > 0 {
                let timeSinceStart = point.date.timeIntervalSince(firstDate)
                xPos = origin.x + (timeSinceStart / totalDuration) * graphSize.width
            } else {
                xPos = origin.x + graphSize.width / 2
            }
            let yPos = yPosition(
                for: point.value,
                inYRange: yRange,
                graphHeight: graphSize.height,
                originY: origin.y
            )
            return CGPoint(x: xPos, y: yPos)
        }

        if isSpecialChart {
            guard let first = screenPoints.first, let last = screenPoints.last else { return }

            let chartColor = self.chartColor(for: nutrientID)

            // Fill
            var fillPath = Path()
            fillPath.move(to: CGPoint(x: first.x, y: origin.y))
            for p in screenPoints { fillPath.addLine(to: p) }
            fillPath.addLine(to: CGPoint(x: last.x, y: origin.y))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(chartColor.opacity(0.18)))

            // Stroke
            var linePath = Path()
            linePath.move(to: first)
            for p in screenPoints.dropFirst() { linePath.addLine(to: p) }
            context.stroke(
                linePath,
                with: .color(chartColor),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
            return
        }

        // --- Останалите нутриенти: динамично зелено/червено за линия и запълване ---
        let req = getRequirements(for: nutrientID)
        let minReq = req.min
        let maxReq = req.max

        func colorForValue(_ v: Double) -> Color {
            if let maxReq, v > maxReq { return .red }
            if let minReq, v < minReq { return .red }
            return .green
        }

        func crossingsBetween(v1: Double, v2: Double) -> [(t: CGFloat, value: Double)] {
            var cs: [(CGFloat, Double)] = []
            guard v1 != v2 else { return cs }
            if let minReq {
                let t = (minReq - v1) / (v2 - v1)
                if t >= 0.0, t <= 1.0 { cs.append((CGFloat(t), minReq)) }
            }
            if let maxReq {
                let t = (maxReq - v1) / (v2 - v1)
                if t >= 0.0, t <= 1.0 { cs.append((CGFloat(t), maxReq)) }
            }
            cs.sort { $0.0 < $1.0 }
            return cs
        }

        for i in 0..<(points.count - 1) {
            let v1 = points[i].value
            let v2 = points[i+1].value
            let p1 = screenPoints[i]
            let p2 = screenPoints[i+1]

            var subPts: [(pt: CGPoint, value: Double)] = [(p1, v1)]
            let cs = crossingsBetween(v1: v1, v2: v2)
            for c in cs {
                let x = p1.x + c.t * (p2.x - p1.x)
                let y = yPosition(for: c.value, inYRange: yRange, graphHeight: graphSize.height, originY: origin.y)
                subPts.append((CGPoint(x: x, y: y), c.value))
            }
            subPts.append((p2, v2))

            for j in 0..<(subPts.count - 1) {
                let a = subPts[j]
                let b = subPts[j+1]
                let midVal = (a.value + b.value) / 2.0
                let segColor = colorForValue(midVal)

                // Fill
                var fillPath = Path()
                fillPath.move(to: CGPoint(x: a.pt.x, y: origin.y))
                fillPath.addLine(to: a.pt)
                fillPath.addLine(to: b.pt)
                fillPath.addLine(to: CGPoint(x: b.pt.x, y: origin.y))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .color(segColor.opacity(0.15)))

                // Stroke
                var segPath = Path()
                segPath.move(to: a.pt)
                segPath.addLine(to: b.pt)
                context.stroke(
                    segPath,
                    with: .color(segColor),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
    
    func drawInteractionIndicator(
        context: inout GraphicsContext,
        position: CGPoint,
        graphTopY: CGFloat,
        graphBottomY: CGFloat,
        accent: Color
    ) {
        var vLine = Path()
        vLine.move(to: CGPoint(x: position.x, y: graphTopY))
        vLine.addLine(to: CGPoint(x: position.x, y: graphBottomY))
        context.stroke(vLine, with: .color(accent.opacity(0.4)), lineWidth: 1)
        
        let dotRect = CGRect(center: position, radius: 5)
        context.fill(Path(ellipseIn: dotRect), with: .color(accent))
        context.stroke(Path(ellipseIn: dotRect), with: .color(.white.opacity(0.8)), lineWidth: 2)
    }
    
    
    private func chartColor(for nutrientID: String) -> Color {
          switch nutrientID {
          case "calories": return .orange
          case "water": return .blue
          case "protein": return Color(hex: "#C9BFED")
          case "carbohydrates": return Color(hex: "#A8D7FF")
          case "fat": return Color(hex: "#FFDAB3")
          default:
              if nutrientID.starts(with: "vit_") {
                  let id = String(nutrientID.dropFirst(4))
                  if let vitamin = allVitamins.first(where: { $0.id == id }) {
                      return Color(hex: vitamin.colorHex)
                  }
              }
              if nutrientID.starts(with: "min_") {
                  let id = String(nutrientID.dropFirst(4))
                  if let mineral = allMinerals.first(where: { $0.id == id }) {
                      return Color(hex: mineral.colorHex)
                  }
              }
              return .green
          }
      }
}
