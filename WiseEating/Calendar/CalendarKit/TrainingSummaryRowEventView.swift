//
//  TrainingSummaryRowEventView.swift
//  WiseEating
//
//  Created by Aleksandar Svinarov on 17/9/25.
//


// FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth/WiseEating/Fitness/Views/TrainingSummaryRowEventView.swift
import SwiftUI
import UIKit

struct TrainingSummaryRowEventView: View {
    let exercises: [(ExerciseItem, Double)]
    let profile: Profile
    @ObservedObject private var effectManager = EffectManager.shared

    private var totalDuration: Double {
        exercises.reduce(0) { $0 + $1.1 }
    }

    private var totalCaloriesBurned: Double {
        exercises.reduce(0.0) { acc, pair in
            let (ex, dur) = pair
            guard let met = ex.metValue, met > 0, dur > 0 else { return acc }
            let cpm = (met * 3.5 * profile.weight) / 200.0
            return acc + cpm * dur
        }
    }
    
    private let chartCentralContentSize: CGFloat = 40
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: chartCentralContentSize))
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
            .frame(width: chartCentralContentSize + 16, height: chartCentralContentSize + 16)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Workout Summary")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(effectManager.currentGlobalAccentColor)

                    Spacer()
                    
                    Text("\(Int(totalDuration)) min total")
                        .font(.caption2)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("\(totalCaloriesBurned, specifier: "%.0f") kcal burned")
                        .font(.caption2)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
            }
            .layoutPriority(1)
        }
    }
}