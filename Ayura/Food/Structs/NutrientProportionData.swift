import SwiftUI
// import UIKit // Не е нужен тук, ако UIImage се подава директно

// MARK: - Donut Chart Data Structure
struct NutrientProportionData: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
}

// NEW: Define ChartDisplayData here as a top-level struct
struct ChartDisplayData {
    let proportions: [NutrientProportionData]
    let centralKcalDisplay: Double?
    let totalReferenceForChart: Double?
}


// MARK: - Donut Chart View
struct NutrientProportionDonutChartView: View {
    let proportions: [NutrientProportionData]
    let centralImageUIImage: UIImage?
    let imagePlaceholderSystemName: String
    
    let centralContentDiameter: CGFloat
    let donutRingThickness: CGFloat
    let canalRingThickness: CGFloat
    
    let adaptiveTextColor: Color

    let ringTrackColor: Color
    
    let totalEnergyKcal: Double?
    let totalReferenceValue: Double?
    let totalWeightInGrams: Double? = nil

    private var centralContentFillColorBasedOnText: Color {
        adaptiveTextColor.opacity(0.05)
    }

    private var centralImageView: Image {
        if let uiImg = centralImageUIImage {
            return Image(uiImage: uiImg)
        } else {
            return Image(systemName: imagePlaceholderSystemName)
        }
    }
    
    // ----- 👇 НАЧАЛО НА КОРЕКЦИЯТА (1/2) 👇 -----
    // Тази променлива вече е по-проста: показваме текст ВИНАГИ, когато няма снимка.
    private var showCentralText: Bool {
        return centralImageUIImage == nil
    }
    // ----- 👆 КРАЙ НА КОРЕКЦИЯТА (1/2) 👆 -----

    private var canalRingPathDiameter: CGFloat {
        centralContentDiameter + canalRingThickness
    }
    
    private var canalRingOuterDiameter: CGFloat {
        centralContentDiameter + (2 * canalRingThickness)
    }
    
    private var arcDrawingRadius: CGFloat {
        (canalRingOuterDiameter / 2) + (donutRingThickness / 2)
    }
    
    private var totalDiameter: CGFloat {
        canalRingOuterDiameter + (2 * donutRingThickness)
    }
    
    private var arcCenter: CGPoint {
        CGPoint(x: totalDiameter / 2, y: totalDiameter / 2)
    }

    var body: some View {
        // ... (тази част остава без промяна)
        let effectiveTotalForNormalization: Double = {
            if let weight = totalWeightInGrams, weight > 0 {
                return weight
            } else if let refTotal = totalReferenceValue, refTotal > 0 {
                return refTotal
            } else {
                let sumOfProportions = proportions.reduce(0) { $0 + $1.value }
                return sumOfProportions > 0 ? sumOfProportions : 1.0
            }
        }()

        var allSegmentsIncludingGap: [NutrientProportionData] {
            let usedTotal = proportions.reduce(0) { $0 + $1.value }
            let remaining = max(effectiveTotalForNormalization - usedTotal, 0)
            
            var currentProportions = proportions
            if remaining > 0.00001 {
                 currentProportions.append(NutrientProportionData(name: "Remaining",
                                                        value: remaining,
                                                        color: .clear))
            }
            return currentProportions
        }
        
        ZStack {
            // ... (всички кръгове и сегменти остават без промяна)
            Circle()
                .strokeBorder(.clear, lineWidth: canalRingThickness)
                .frame(width: canalRingPathDiameter, height: canalRingPathDiameter)

            TubularRingStroke(
                shape: Circle(),
                style: ringTrackColor,
                strokeStyle: StrokeStyle(lineWidth: donutRingThickness),
                role: .track
            )
                .frame(width: arcDrawingRadius * 2,
                       height: arcDrawingRadius * 2)

            ArcSegmentsView(
                proportions: allSegmentsIncludingGap,
                effectiveTotalForNormalization: effectiveTotalForNormalization,
                arcCenter: arcCenter,
                arcDrawingRadius: arcDrawingRadius,
                donutRingThickness: donutRingThickness
            )

            Circle()
                .fill(centralContentFillColorBasedOnText)
                .frame(width: centralContentDiameter, height: centralContentDiameter)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .black.opacity(0.3), location: 0),
                                    .init(color: .clear, location: 0.4)
                                ]),
                                startPoint: .bottomTrailing,
                                endPoint: .topLeading
                            ),
                            lineWidth: 1
                        )
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .white.opacity(0.8), location: 0),
                                    .init(color: .clear, location: 0.5)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )

            Group {
                // ----- 👇 НАЧАЛО НА КОРЕКЦИЯТА (2/2) 👇 -----
                // Проверяваме с 'showCentralText'. Ако е true, ВИНАГИ показваме VStack-а,
                // като използваме 'totalEnergyKcal ?? 0', за да се справим с nil и 0 стойности.
                if showCentralText {
                    VStack(spacing: centralContentDiameter * 0.03) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: centralContentDiameter * 0.22))
                            .foregroundColor(.orange)
                        Text(String(format: "%.0f", totalEnergyKcal ?? 0)) // <-- Тук е промяната
                            .font(.system(size: centralContentDiameter * 0.28, weight: .bold))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .foregroundColor(adaptiveTextColor)
                        Text("kcal")
                            .font(.system(size: centralContentDiameter * 0.16))
                            .foregroundColor(adaptiveTextColor.opacity(0.7))
                    }
                    .frame(width: centralContentDiameter * 0.95, height: centralContentDiameter * 0.95)
                    .ringCenterDepth(scale: centralContentDiameter / 60)
                } else {
                     centralImageView
                        .resizable()
                        .scaledToFill()
                        .frame(width: centralContentDiameter, height: centralContentDiameter)
                        .clipShape(Circle())
                        .foregroundColor(centralImageUIImage == nil ? adaptiveTextColor.opacity(0.6) : adaptiveTextColor)
                }
                // ----- 👆 КРАЙ НА КОРЕКЦИЯТА (2/2) 👆 -----
            }
            .frame(width: centralContentDiameter, height: centralContentDiameter)
        }
        .frame(width: totalDiameter, height: totalDiameter)
        .drawingGroup()
    }
}
// ArcSegmentsView остава без промяна, тъй като не съдържа текст директно.
// Ако в бъдеще добавите текст там, ще трябва да му подадете adaptiveTextColor.
struct ArcSegmentsView: View {
    let proportions: [NutrientProportionData]
    let effectiveTotalForNormalization: Double
    let arcCenter: CGPoint
    let arcDrawingRadius: CGFloat
    let donutRingThickness: CGFloat

    private struct ProcessedSegmentData: Identifiable {
        let id = UUID()
        let originalData: NutrientProportionData
        let displayStartAngle: Angle
        let displayEndAngle: Angle
        let trueStartAngleRadians: Double
        let trueEndAngleRadians: Double
    }

    private func calculateAllSegmentData() -> [ProcessedSegmentData] {
        var segments: [ProcessedSegmentData] = []
        var accumulatedAngleDegrees: Double = -90 // Започваме отгоре
        let normalizationDenominator = max(0.00001, effectiveTotalForNormalization) // Предпазваме от делене на нула

        for proportion in proportions {
            let positiveValue = max(0, proportion.value) // Гарантираме, че стойностите не са отрицателни
            let proportionValueNormalized = positiveValue / normalizationDenominator
            let segmentAngleDegrees = proportionValueNormalized.isFinite ? proportionValueNormalized * 360.0 : 0.0

            // Само ако сегментът е достатъчно голям, за да се вижда
            if segmentAngleDegrees > 0.001 {
                let currentStartAngleDegrees = accumulatedAngleDegrees
                let currentEndAngleDegrees = accumulatedAngleDegrees + segmentAngleDegrees

                segments.append(ProcessedSegmentData(
                    originalData: proportion,
                    displayStartAngle: Angle.degrees(currentStartAngleDegrees),
                    displayEndAngle: Angle.degrees(currentEndAngleDegrees),
                    trueStartAngleRadians: Angle.degrees(currentStartAngleDegrees).radians,
                    trueEndAngleRadians: Angle.degrees(currentEndAngleDegrees).radians
                ))
                accumulatedAngleDegrees = currentEndAngleDegrees
            }
        }
        return segments
    }


    var body: some View {
        // Ако няма данни или общата сума е нула, не рисуваме нищо
        if effectiveTotalForNormalization <= 0.00001 && proportions.allSatisfy({ $0.value <= 0.00001 }) {
            return AnyView(EmptyView())
        }
        
        let allProcessedSegments = calculateAllSegmentData()
        // Филтрираме сегментите, които са действителни данни (не са "Remaining" с цвят .clear)
        let actualDataSegments = allProcessedSegments.filter { $0.originalData.color != .clear }


        return AnyView(
            ZStack {
                ForEach(actualDataSegments) { segmentData in
                    TubularRingStroke(
                        shape: Path { path in
                            path.addArc(
                                center: arcCenter,
                                radius: arcDrawingRadius,
                                startAngle: segmentData.displayStartAngle,
                                endAngle: segmentData.displayEndAngle,
                                clockwise: false // Рисуваме по посока на часовниковата стрелка
                            )
                        },
                        style: segmentData.originalData.color,
                        strokeStyle: StrokeStyle(lineWidth: donutRingThickness, lineCap: .butt)
                    )
                }
            }
        )
    }
}

let defaultCanalRingGradient = AngularGradient(
    gradient: Gradient(stops: [
        .init(color: .white.opacity(0.9), location: 0.0),             // Stronger highlight
        .init(color: Color(.systemGray5).opacity(0.9), location: 0.25),
        .init(color: Color(.systemGray4).opacity(0.9), location: 0.5),
        .init(color: .black.opacity(0.35), location: 0.625),          // Stronger shadow
        .init(color: Color(.systemGray4).opacity(0.9), location: 0.75),
        .init(color: Color(.systemGray5).opacity(0.9), location: 0.875),
        .init(color: .white.opacity(0.9), location: 1.0)
    ]),
    center: .center,
    angle: .degrees(135) // Light from top-left
)
