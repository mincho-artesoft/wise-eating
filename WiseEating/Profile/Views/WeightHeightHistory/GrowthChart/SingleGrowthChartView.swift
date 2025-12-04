import SwiftUI

struct SingleGrowthChartView: View {
    // MARK: - Input
    let title: String
    let yAxisLabel: String
    let percentileData: [CDCPercentileCurve]
    let userData: [PlottableMetric]
    let lineColor: Color // This color will be used for both lines and percentile labels
    let profileBirthday: Date

    // MARK: - Interaction & State
    @State private var canvasSize: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero

    // Gesture-specific state, automatically resets
    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureOffset: CGSize = .zero

    // State for the interactive bubble (nil by default)
    @State private var activeBubbleData: (point: PlottableMetric, position: CGPoint)? = nil

    // Cached paths for performance
    @State private var cachedUserDataPath: (path: Path, points: [CGPoint])?
    // MODIFICATION 1: Change cachedPercentilePaths to store (path, points, percentile string)
    @State private var cachedPercentileCurveData: [(path: Path, points: [CGPoint], percentile: String)]?


    // MARK: - Managers
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: - Logic Enum
    private enum MetricType { case length, weight, head }
    private var chartMetricType: MetricType {
        if title.lowercased().contains("length") { return .length }
        if title.lowercased().contains("weight") { return .weight }
        return .head
    }

    // MARK: - Computed Properties
    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            
            if userData.isEmpty {
                emptyStateView
            } else {
                GeometryReader { geometry in
                    chartBody(geometry: geometry)
                }
            }
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
        .onChange(of: userData) { _, _ in updateCachedPaths(for: canvasSize) }
        .onChange(of: isImperial) { _, _ in updateCachedPaths(for: canvasSize) }
    }

    // MARK: - Subviews
    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            Spacer()
            Text("(\(yAxisLabel))")
                .font(.subheadline)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
        }
        .padding(.bottom, 8)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Data", systemImage: "chart.bar.xaxis.ascending")
        } description: {
            Text("Add records to see growth data.")
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
        .frame(maxHeight: .infinity)
    }

    private func chartBody(geometry: GeometryProxy) -> some View {
        let newSize = geometry.size
        
        // This is now the main trigger for updating paths when the size is first known or changes.
        if newSize != self.canvasSize && newSize != .zero {
            DispatchQueue.main.async {
                self.canvasSize = newSize
                self.updateCachedPaths(for: newSize)
            }
        }
        
        return ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let (origin, graphSize) = chartGeometry(for: size)
                let totalScale = currentScale * gestureScale
                let totalOffset = currentOffset + gestureOffset

                // MODIFICATION 4: drawGridAndLabels вече не чертае персентилни етикети
                drawGridAndLabels(context: &context, origin: origin, graphSize: graphSize, scale: totalScale, offset: totalOffset)

                context.drawLayer { layerContext in
                    let graphRect = CGRect(origin: CGPoint(x: origin.x, y: origin.y - graphSize.height), size: graphSize)
                    layerContext.clip(to: Path(graphRect))
                    layerContext.translateBy(x: origin.x + totalOffset.width, y: origin.y - graphSize.height + totalOffset.height)
                    layerContext.scaleBy(x: totalScale, y: totalScale)
                    // MODIFICATION 5: Предаваме graphSize към drawCachedData за правилно позициониране на етикетите
                    drawCachedData(context: &layerContext, scale: totalScale, graphSize: graphSize)
                }
            }
            .gesture(combinedGesture)
            .gesture(doubleTapToResetGesture)

            if let bubbleData = activeBubbleData {
                bubble(for: bubbleData.point)
                    .position(bubblePosition(for: bubbleData.position))
                    .transition(.opacity.animation(.easeInOut(duration: 0.1)))
            }
        }
    }

    // MARK: - Gestures
    private var doubleTapToResetGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.easeInOut) {
                    currentScale = 1.0
                    currentOffset = .zero
                }
            }
    }

    private var combinedGesture: some Gesture {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                // при 1× мащаб – само „слайдър“-функцията за балончето
                if currentScale == 1.0 {
                    updateBubbleForDrag(location: value.location)
                }
            }
            .updating($gestureOffset) { value, state, _ in
                // при zoom > 1 – истинско панорираме, но КЛАМПВАМЕ превода
                if currentScale > 1.0, canvasSize != .zero {
                    let (_, graphSize) = chartGeometry(for: canvasSize)

                    // новият моментен offset = текущ + превод от жеста
                    let proposedFixed = CGSize(width: currentOffset.width  + value.translation.width,
                                          height: currentOffset.height + value.translation.height)

                    // кламп -> после го превръщаме обратно в „само превод“ спрямо currentOffset
                    let clamped = clampedOffset(proposedFixed, graphSize: graphSize, scale: currentScale)
                    state = CGSize(width: clamped.width  - currentOffset.width,
                                   height: clamped.height - currentOffset.height)
                }
            }
            .onEnded { value in
                if currentScale > 1.0, canvasSize != .zero {
                    let (_, graphSize) = chartGeometry(for: canvasSize)
                    // Fixed the bug here too.
                    let proposedFixed = CGSize(width: currentOffset.width  + value.translation.width,
                                          height: currentOffset.height + value.translation.height)
                    currentOffset = clampedOffset(proposedFixed, graphSize: graphSize, scale: currentScale)
                }
                activeBubbleData = nil
            }

        let magnification = MagnificationGesture()
            .updating($gestureScale) { value, state, _ in state = value }
            .onEnded(handleMagnificationEnd)

        return drag.simultaneously(with: magnification)
    }


    private func handleMagnificationEnd(_ value: MagnificationGesture.Value) {
        activeBubbleData = nil
        
        let oldScale = currentScale
        currentScale = min(max(currentScale * value, 1.0), 5.0)

        if currentScale == 1.0 {
            currentOffset = .zero
            return
        }
        
        let focalPoint = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let (origin, graphSize) = chartGeometry(for: canvasSize)

        let graphFocalX = (focalPoint.x - origin.x - currentOffset.width) / oldScale
        let graphFocalY = (focalPoint.y - (origin.y - graphSize.height) - currentOffset.height) / oldScale

        currentOffset.width -= graphFocalX * (currentScale - oldScale)
        currentOffset.height -= graphFocalY * (currentScale - oldScale)
        
        constrainOffset()
    }

    // MARK: - Bubble Logic
    @ViewBuilder
    private func bubble(for p: PlottableMetric) -> some View {
        let ageMonths = ageInMonths(from: profileBirthday, to: p.date)
        VStack(alignment: .leading, spacing: 4) {
            Text(p.date.formatted(.dateTime.day().month().year())).font(.caption)
            Divider()
            HStack { Text(p.metricName); Spacer(); Text("\(p.value.clean) \(yAxisLabel)").fontWeight(.bold) }
            HStack { Text("Age"); Spacer(); Text("\(ageMonths.clean) mo").fontWeight(.bold) }
            HStack { Text("Percentile"); Spacer(); Text(calculatePercentile(for: p.value, at: ageMonths)).fontWeight(.bold) }
        }
        .font(.caption)
        .padding(10)
        .frame(width: 140)
        .glassCardStyle(cornerRadius: 14)
        .foregroundStyle(effectManager.currentGlobalAccentColor)
    }

    private func bubblePosition(for pointPosition: CGPoint) -> CGPoint {
        let bubbleSize = CGSize(width: 140, height: 110)
        let (origin, graphSize) = chartGeometry(for: canvasSize)
        
        let graphTopY = origin.y - graphSize.height
        let spaceAbove = pointPosition.y - graphTopY
        let finalY = (spaceAbove > bubbleSize.height + 12)
            ? pointPosition.y - 12 - bubbleSize.height / 2
            : pointPosition.y + 12 + bubbleSize.height / 2
        
        let isLeft = pointPosition.x < canvasSize.width / 2
        let targetX = isLeft
            ? pointPosition.x + 12 + bubbleSize.width / 2
            : pointPosition.x - 12 - bubbleSize.width / 2
        
        return CGPoint(x: targetX, y: finalY)
    }

    private func updateBubbleForDrag(location: CGPoint) {
        guard !userData.isEmpty, canvasSize != .zero else { return }
        let (origin, graphSize) = chartGeometry(for: canvasSize)
        let yRange = self.yDomain
        let dragXInGraph = location.x - origin.x
        
        let pointsWithX = userData.map { metric -> (PlottableMetric, CGFloat) in
            let months = ageInMonths(from: profileBirthday, to: metric.date)
            let x = (months / 24.0) * graphSize.width
            return (metric, x)
        }
        
        guard let closest = pointsWithX.min(by: { abs($0.1 - dragXInGraph) < abs($1.1 - dragXInGraph) }) else { return }
        
        let yPosInGraph = yPositionInGraph(for: closest.0.value, inYRange: yRange, graphHeight: graphSize.height)
        let screenPos = CGPoint(
            x: origin.x + closest.1,
            y: origin.y - graphSize.height + yPosInGraph
        )
        
        self.activeBubbleData = (point: closest.0, position: screenPos)
    }
    
    // MARK: - Drawing & Caching

    // MODIFICATION 2: Update updateCachedPaths to populate cachedPercentileCurveData
    private func updateCachedPaths(for newSize: CGSize) {
        // Важно: Персентилните криви съществуват независимо от потребителските данни,
        // така че не трябва да зависим от `!userData.isEmpty` за тях.
        guard newSize != .zero else {
            self.cachedUserDataPath = nil
            self.cachedPercentileCurveData = nil
            return
        }
        let (_, graphSize) = chartGeometry(for: newSize)
        let yRange = self.yDomain

        // Потребителски данни: Използваме createStraightPath
        let userPoints = userData.map { metric -> CGPoint in
            let months = ageInMonths(from: profileBirthday, to: metric.date)
            let x = (months / 24.0) * graphSize.width
            let y = yPositionInGraph(for: metric.value, inYRange: yRange, graphHeight: graphSize.height)
            return CGPoint(x: x, y: y)
        }
        self.cachedUserDataPath = (createStraightPath(from: userPoints), userPoints) // <-- ПРОМЯНА ТУК

        // Персентилни криви: Използваме createStraightPath
        self.cachedPercentileCurveData = percentileData.map { curve in
            let points = curve.points.map { point -> CGPoint in
                let val = (chartMetricType == .weight)
                    ? (isImperial ? UnitConversion.kgToLbs(point.value) : point.value)
                    : (isImperial ? UnitConversion.cmToInches(point.value) : point.value)
                let x = (CGFloat(point.ageMonths) / 24.0) * graphSize.width
                let y = yPositionInGraph(for: val, inYRange: yRange, graphHeight: graphSize.height)
                return CGPoint(x: x, y: y)
            }
            return (createStraightPath(from: points), points, curve.percentile) // <-- ПРОМЯНА ТУК
        }
    }

    // MODIFICATION 3: Модифицираме drawCachedData, за да чертаем линиите и етикетите на персентила
    private func drawCachedData(context: inout GraphicsContext, scale: CGFloat, graphSize: CGSize) {
        let accent = effectManager.currentGlobalAccentColor // Използваме акцентиращия цвят за етикетите

        if let curvesData = cachedPercentileCurveData {
            for curveData in curvesData {
                // Чертаем пътя на кривата
                context.stroke(curveData.path, with: .color(lineColor.opacity(0.5)), lineWidth: 1.5 / scale)

                // Чертаем етикета на персентила в края на линията (при X-позиция за 24 месеца)
                let labelXPosition = graphSize.width // Това е x-координатата за 24 месеца в координатите на графиката
                
                // Интерполираме Y-стойността за тази X-позиция
                let interpolatedY = interpolateYValue(for: labelXPosition, curvePoints: curveData.points)

                // Уверяваме се, че точката е в разумни граници, преди да опитаме да начертаем етикет
                if interpolatedY >= 0 && interpolatedY <= graphSize.height {
                    let percentileText = Text(curveData.percentile)
                        .font(.system(size: 8 / scale)) // По-малък шрифт, който се мащабира със зуума
                        .foregroundColor(accent.opacity(0.8))

                    // Позиционираме етикета леко вляво от 24-месечната маркировка,
                    // вертикално центриран спрямо интерполираната позиция на линията.
                    // Използваме `anchor: .trailing`, за да подравним десния край на текста
                    // към `labelPosition`.
                    let labelOffsetFromEdge: CGFloat = 2.0 // Малък отместък вляво от линията на 24-тия месец
                    let labelPosition = CGPoint(x: labelXPosition - labelOffsetFromEdge, y: interpolatedY)
                    
                    context.draw(percentileText, at: labelPosition, anchor: .trailing)
                }
            }
        }
        
        // Чертаем потребителските данни (без промяна)
        if let (path, points) = cachedUserDataPath {
            context.stroke(path, with: .color(lineColor), style: StrokeStyle(lineWidth: 2.5 / scale, lineCap: .round, lineJoin: .round))
            for pt in points {
                context.fill(Path(ellipseIn: CGRect(center: pt, radius: 4.0 / scale)), with: .color(lineColor))
            }
        }
    }

    // MODIFICATION 4: drawGridAndLabels вече не чертае персентилни етикети
    private func drawGridAndLabels(context: inout GraphicsContext, origin: CGPoint, graphSize: CGSize, scale: CGFloat, offset: CGSize) {
        let accent = effectManager.currentGlobalAccentColor
        let yRange = self.yDomain
        
        for val in yAxisValues(yRange: yRange) {
            let yPos = yPositionOnCanvas(for: val, inYRange: yRange, graphHeight: graphSize.height, originY: origin.y, scale: scale, offset: offset)
            if yPos > origin.y - graphSize.height - 20 && yPos < origin.y + 20 {
                var path = Path(); path.move(to: CGPoint(x: origin.x, y: yPos)); path.addLine(to: CGPoint(x: origin.x + graphSize.width, y: yPos))
                context.stroke(path, with: .color(accent.opacity(0.2)), style: StrokeStyle(lineWidth: 0.5, dash: [4]))
                context.draw(Text(val.clean).font(.caption2).foregroundColor(accent.opacity(0.8)), at: CGPoint(x: origin.x + graphSize.width + 20, y: yPos), anchor: .center)
            }
        }
        
        for month in stride(from: 0, through: 24, by: 3) {
            let xPos = origin.x + ((CGFloat(month) / 24.0) * graphSize.width * scale) + offset.width
            if xPos > origin.x - 20 && xPos < origin.x + graphSize.width + 20 {
                var path = Path(); path.move(to: CGPoint(x: xPos, y: origin.y)); path.addLine(to: CGPoint(x: xPos, y: origin.y - graphSize.height))
                context.stroke(path, with: .color(accent.opacity(0.2)), style: StrokeStyle(lineWidth: 0.5, dash: [4]))
                context.draw(Text("\(month)").font(.caption2).foregroundColor(accent.opacity(0.8)), at: CGPoint(x: xPos, y: origin.y + 12), anchor: .center)
            }
        }
        context.draw(Text("Age (Months)").font(.caption).foregroundColor(accent.opacity(0.8)), at: CGPoint(x: origin.x + graphSize.width / 2, y: origin.y + 25), anchor: .center)
    }

    private let chartPadding = EdgeInsets(top: 20, leading: 10, bottom: 35, trailing: 40)
    
    private var yDomain: ClosedRange<Double> {
        let cdcVals = percentileData.flatMap { $0.points }.map { point in
            switch chartMetricType {
            case .length, .head: return isImperial ? UnitConversion.cmToInches(point.value) : point.value
            case .weight: return isImperial ? UnitConversion.kgToLbs(point.value) : point.value
            }
        }
        let all = cdcVals + userData.map(\.value)
        guard let minV = all.min(), let maxV = all.max() else { return 0...100 }
        let pad = (maxV - minV) * 0.1
        return max(0, minV - pad)...(maxV + pad)
    }

    private func chartGeometry(for size: CGSize) -> (origin: CGPoint, size: CGSize) {
        let origin = CGPoint(x: chartPadding.leading, y: size.height - chartPadding.bottom)
        let graphSize = CGSize(width: size.width - chartPadding.leading - chartPadding.trailing,
                               height: size.height - chartPadding.top - chartPadding.bottom)
        return (origin, graphSize)
    }
    
    private func yPositionInGraph(for value: Double, inYRange: ClosedRange<Double>, graphHeight: CGFloat) -> CGFloat {
        let domainSize = inYRange.upperBound - inYRange.lowerBound
        guard domainSize > 0, graphHeight > 0 else { return 0 }
        let normalizedY = (value - inYRange.lowerBound) / domainSize
        return graphHeight * (1 - normalizedY)
    }
    
    private func yPositionOnCanvas(for value: Double, inYRange: ClosedRange<Double>, graphHeight: CGFloat, originY: CGFloat, scale: CGFloat, offset: CGSize) -> CGFloat {
        let yInGraph = yPositionInGraph(for: value, inYRange: inYRange, graphHeight: graphHeight)
        return (originY - graphHeight) + (yInGraph * scale) + offset.height
    }

    private func constrainOffset() {
        let (_, graphSize) = chartGeometry(for: canvasSize)
        
        let extraWidth = graphSize.width * (currentScale - 1)
        let extraHeight = graphSize.height * (currentScale - 1)

        currentOffset.width = max(-extraWidth, min(0, currentOffset.width))
        currentOffset.height = max(-extraHeight, min(0, currentOffset.height))
    }
    
    private func ageInMonths(from birthDate: Date, to date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.month, .day], from: birthDate, to: date)
        let months = Double(comps.month ?? 0)
        let days = Double(comps.day ?? 0)
        return months + days/30.44
    }

    private func calculatePercentile(for value: Double, at ageMonths: Double) -> String {
        guard !percentileData.isEmpty else { return "N/A" }
        let actualVal: Double = {
            switch chartMetricType {
            case .length, .head: return isImperial ? UnitConversion.inchesToCm(value) : value
            case .weight: return isImperial ? UnitConversion.lbsToKg(value) : value
            }
        }()
        let interp = percentileData.compactMap { curve -> (percentile: Double, value: Double)? in
            guard let p = Double(curve.percentile) else { return nil }
            return (p, interpolate(curve: curve, at: ageMonths))
        }.sorted { $0.value < $1.value }
        guard let first = interp.first, let last = interp.last else { return "N/A" }
        if actualVal <= first.value { return "≤\(Int(first.percentile))th" }
        if actualVal >= last.value { return "≥\(Int(last.percentile))th" }
        for i in 0..<interp.count - 1 {
            let low = interp[i], high = interp[i + 1]
            if actualVal >= low.value && actualVal <= high.value {
                let range = high.value - low.value
                guard range > 0 else { return "~\(Int(low.percentile))th" }
                let t = (actualVal - low.value) / range
                return "~\(Int(round(low.percentile + t * (high.percentile - low.percentile))))th"
            }
        }
        return "N/A"
    }

    private func interpolate(curve: CDCPercentileCurve, at ageMonths: Double) -> Double {
        guard let p1 = curve.points.last(where: { $0.ageMonths <= ageMonths }),
              let p2 = curve.points.first(where: { $0.ageMonths >= ageMonths })
        else { return curve.points.first?.value ?? 0 }
        if p1.ageMonths == p2.ageMonths { return p1.value }
        let t = (ageMonths - p1.ageMonths) / (p2.ageMonths - p1.ageMonths)
        return p1.value + t * (p2.value - p1.value)
    }
    
    private func yAxisValues(yRange: ClosedRange<Double>) -> [Double] {
        let range = yRange.upperBound - yRange.lowerBound
        guard range > 0 else { return [] }
        let lines = 5.0
        let raw = range / lines
        let mag = pow(10, floor(log10(max(raw, .leastNonzeroMagnitude))))
        let candidates = [1, 2, 2.5, 5, 10].map { $0 * mag }
        let step = candidates.first { $0 >= raw } ?? raw
        guard step > 0 else { return [] }
        let start = floor(yRange.lowerBound / step) * step
        let end = ceil(yRange.upperBound / step) * step
        return stride(from: start, through: end, by: step).map { $0 }
    }

    // --- Нова/Възстановена функция за прави линии ---
    private func createStraightPath(from points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 1 else {
            if let first = points.first { path.move(to: first); path.addLine(to: first) }
            return path
        }
        path.move(to: points[0])
        for i in 1..<points.count {
            path.addLine(to: points[i]) // Добавяне на права линия до следващата точка
        }
        return path
    }
    // --- КРАЙ на новата/възстановена функция ---

    // Функцията createSmoothPath е премахната, защото вече не се използва.
    
    private func interpolateYValue(for targetX: CGFloat, curvePoints: [CGPoint]) -> CGFloat {
            guard !curvePoints.isEmpty else { return 0 }

            // Намираме двете точки, които обграждат targetX
            // Използвайки `last(where:)` и `first(where:)` с условия, гарантираме, че намираме
            // точките непосредствено преди и след (или точно на) targetX.
            guard let p1 = curvePoints.last(where: { $0.x <= targetX }),
                  let p2 = curvePoints.first(where: { $0.x >= targetX }) else {
                // Ако targetX е извън обхвата на съществуващите точки,
                // екстраполираме, използвайки най-близката крайна точка.
                // По-безопасно е да проверим за nil, преди да разгърнем опционала.
                if let firstPoint = curvePoints.first, targetX < firstPoint.x {
                    return firstPoint.y
                } else if let lastPoint = curvePoints.last, targetX > lastPoint.x {
                    return lastPoint.y
                }
                return 0 // Не би трябвало да се случи, предвид проверките
            }

            if p1.x == p2.x { return p1.y } // Избягваме деление на нула, ако точките имат еднаква X-координата

            // Линейна интерполация
            let t = (targetX - p1.x) / (p2.x - p1.x)
            return p1.y + t * (p2.y - p1.y)
        }
    
    private func clampedOffset(_ proposed: CGSize, graphSize: CGSize, scale: CGFloat) -> CGSize {
        let extraWidth  = graphSize.width  * (scale - 1)
        let extraHeight = graphSize.height * (scale - 1)

        return CGSize(
            width:  min(0, max(-extraWidth,  proposed.width)),
            height: min(0, max(-extraHeight, proposed.height))
        )
    }

    
}
