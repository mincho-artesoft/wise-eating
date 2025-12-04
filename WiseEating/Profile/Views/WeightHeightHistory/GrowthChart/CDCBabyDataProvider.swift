//
//  CDCBabyDataProvider.swift
//  WiseEating
//
//  Created by Mincho Milev on 11.11.25.
//

import SwiftUI

// MARK: - Enums

enum BabySex: String, CaseIterable, Identifiable {
    case boy = "Boy", girl = "Girl"
    var id: String { rawValue }
}

enum BabyMetric: String, CaseIterable, Identifiable {
    case length = "Length"
    case weight = "Weight"
    case head   = "Head"
    var id: String { rawValue }
    
    var unit: String {
        switch self {
        case .weight: return "kg"
        case .length, .head: return "cm"
        }
    }
}

// MARK: - Data Router

struct CDCBabyDataProvider {
    static func curves(for sex: BabySex, metric: BabyMetric) -> [CDCPercentileCurve] {
        switch (sex, metric) {
        case (.boy, .length): return CDCBoysLengthData.curves
        case (.boy, .weight): return CDCBoysWeightData.curves
        case (.boy, .head):   return CDCBoysHeadData.curves
        case (.girl, .length): return CDCGirlsLengthData.curves
        case (.girl, .weight): return CDCGirlsWeightData.curves
        case (.girl, .head):   return CDCGirlsHeadData.curves
        }
    }
    
    /// Handy defaults for y-axis ranges or slider bounds
    static func suggestedRange(for metric: BabyMetric) -> ClosedRange<Double> {
        switch metric {
        case .length: return 43...98     // cm (approx from your tables)
        case .weight: return 2...18      // kg
        case .head:   return 30...53     // cm
        }
    }
}

// MARK: - Picker Row (add "Head" here)

struct BabyGrowthPickerRow: View {
    @Binding var sex: BabySex
    @Binding var metric: BabyMetric
    
    var body: some View {
        VStack(spacing: 12) {
            Picker("Baby Sex", selection: $sex) {
                ForEach(BabySex.allCases) { s in Text(s.rawValue).tag(s) }
            }
            .pickerStyle(.segmented)
            
            Picker("Measure", selection: $metric) {
                ForEach(BabyMetric.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented) // <- now includes "Head"
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Example Parent View

struct BabyGrowthScreen: View {
    @State private var sex: BabySex = .boy
    @State private var metric: BabyMetric = .head   // default to Head if you want
    @State private var ageMonths: Double = 6        // example control value
    @State private var measuredValue: Double = 43.0 // e.g. head cm
    
    private var curves: [CDCPercentileCurve] {
        CDCBabyDataProvider.curves(for: sex, metric: metric)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                BabyGrowthPickerRow(sex: $sex, metric: $metric)
                
                // Example: Controls for age/value (optional)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Age: \(Int(ageMonths)) months")
                    Slider(value: $ageMonths, in: 0...24, step: 1)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Measured \(metric.rawValue): \(String(format: "%.1f", measuredValue)) \(metric.unit)")
                    Slider(value: $measuredValue, in: CDCBabyDataProvider.suggestedRange(for: metric), step: 0.1)
                }
                
                // Use `curves` below in your chart view
                // Example stub if you render elsewhere:
                GrowthChart(curves: curves, sex: sex, metric: metric)
                    .frame(height: 280)
            }
            .padding()
        }
        .navigationTitle("Baby Growth")
    }
}

// MARK: - Minimal Chart Stub
// Replace with your actual charting (Swift Charts or custom).
struct GrowthChart: View {
    let curves: [CDCPercentileCurve]
    let sex: BabySex
    let metric: BabyMetric
    
    var body: some View {
        // Draw your lines here using `curves`.
        // This placeholder makes the example compile without Charts.
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08))
            VStack {
                Text("\(sex.rawValue) \(metric.rawValue) Percentiles")
                    .font(.headline)
                Text("Provide your existing chart here using the routed curves.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
