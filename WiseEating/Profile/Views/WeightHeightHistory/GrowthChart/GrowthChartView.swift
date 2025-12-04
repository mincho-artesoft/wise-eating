import SwiftUI

struct GrowthChartView: View {
    let profile: Profile
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var effectManager = EffectManager.shared

    private enum ChartType: String, CaseIterable, Identifiable {
        case length = "Length"
        case weight = "Weight"
        case head = "Head"
        var id: Self { self }
    }

    @State private var selectedChart: ChartType = .length

    private var isImperial: Bool { GlobalState.measurementSystem == "Imperial" }
    private var heightUnit: String { isImperial ? "in" : "cm" }
    private var weightUnit: String { isImperial ? "lbs" : "kg" }

    private var userLengthData: [PlottableMetric] {
        profile.weightHeightHistory.map { record in
            let displayValue = isImperial ? UnitConversion.cmToInches(record.height) : record.height
            return PlottableMetric(date: record.date, metricName: "Height", value: displayValue)
        }
    }
    
    private var userWeightData: [PlottableMetric] {
        profile.weightHeightHistory.map { record in
            let displayValue = isImperial ? UnitConversion.kgToLbs(record.weight) : record.weight
            return PlottableMetric(date: record.date, metricName: "Weight", value: displayValue)
        }
    }
    
    private var userHeadData: [PlottableMetric] {
        profile.weightHeightHistory.compactMap { record in
            guard let hc = record.headCircumference else { return nil }
            let displayValue = isImperial ? UnitConversion.cmToInches(hc) : hc
            return PlottableMetric(date: record.date, metricName: "Head Circ.", value: displayValue)
        }
    }

    var body: some View {
        ZStack {
            ThemeBackgroundView().ignoresSafeArea()

            VStack(spacing: 0) {
                customToolbar
                
                if profile.age > 2 {
                    ContentUnavailableView(
                        "Age Not Applicable",
                        systemImage: "person.crop.circle.badge.xmark",
                        description: Text("These growth charts are intended for children up to 24 months of age.")
                    )
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .frame(maxHeight: .infinity)
                } else {
                    VStack {
                        picker
                        
                        if selectedChart == .length {
                            SingleGrowthChartView(
                                title: "Length-for-age Percentiles",
                                yAxisLabel: heightUnit,
                                percentileData: isMale ? CDCBoysLengthData.curves : CDCGirlsLengthData.curves,
                                userData: userLengthData,
                                lineColor: effectManager.currentGlobalAccentColor,
                                profileBirthday: profile.birthday
                            )
                        } else if selectedChart == .weight {
                            SingleGrowthChartView(
                                title: "Weight-for-age Percentiles",
                                yAxisLabel: weightUnit,
                                percentileData: isMale ? CDCBoysWeightData.curves : CDCGirlsWeightData.curves,
                                userData: userWeightData,
                                lineColor: effectManager.currentGlobalAccentColor,
                                profileBirthday: profile.birthday
                            )
                        } else { // This case is .head
                             SingleGrowthChartView(
                                 title: "Head Circumference-for-age Percentiles",
                                 yAxisLabel: heightUnit,
                                 percentileData: isMale ? CDCBoysHeadData.curves : CDCGirlsHeadData.curves,
                                 userData: userHeadData,
                                 lineColor: effectManager.currentGlobalAccentColor,
                                 profileBirthday: profile.birthday
                             )
                        }
                    }
                    .id(selectedChart)
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    private var isMale: Bool {
        profile.gender.lowercased() == "male"
    }
    
    private var picker: some View {
        WrappingSegmentedControl(selection: $selectedChart, layoutMode: .wrap)
              .frame(height: 36)
    }
    
    @ViewBuilder
    private var customToolbar: some View {
        HStack {
            HStack {
                Button { dismiss() } label: {
                    HStack {
                        Text("Back")
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20).foregroundStyle(effectManager.currentGlobalAccentColor)
            
            Spacer()
            
            Text("Growth Chart").font(.headline).foregroundStyle(effectManager.currentGlobalAccentColor)
            
            Spacer()
            
            HStack { Button("Back") {}.hidden() }
                .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .padding(.horizontal).padding(.top, 10).padding(.bottom, 8)
    }
}
