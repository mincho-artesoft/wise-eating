//
//  ContentView.swift
//  WiseEating
//
//  Created by Aleksandar Svinarov on 6/11/25.
//


import SwiftUI

/// Помощна функция: нормализира датата до начало на деня (за ключ в речник).
private func startOfDay(_ d: Date) -> Date {
    Calendar.current.startOfDay(for: d)
}

struct ContentView: View {
    @State private var selectedDate = Date()
    /// Примерни прогреси по дни (0…1). Ключът е нормализирана дата (startOfDay).
    @State private var progressByDay: [Date: Double] = [:]

    var body: some View {
        VStack(spacing: 16) {
            // MARK: WeekCarousel
            WeekCarouselRepresentable(
                selectedDate: $selectedDate,
                progressProvider: { date in
                    // Върни стойност 0…1 или nil ако няма данни за този ден
                    progressByDay[startOfDay(date)]
                },
                onDaySelected: { date in
                    // Тук си хендълваш навигация/логика при избор на ден
                    print("Selected day:", date)
                }
            )
            .frame(height: 80) // дай му височина, за да се вижда правилно

            // MARK: Demo UI
            VStack(spacing: 8) {
                Text("Selected:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.title3).bold()

                // Показваме текущия прогрес за избрания ден
                if let p = progressByDay[startOfDay(selectedDate)] {
                    Text("Progress: \(Int(p * 100))%")
                        .font(.subheadline)
                } else {
                    Text("No progress data")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
        .onAppear(perform: seedMockProgress)
    }

    /// Попълваме примерни стойности за текущата седмица (само за демо).
    private func seedMockProgress() {
        let cal = Calendar.current
        let today = startOfDay(Date())
        progressByDay[today] = 0.35

        if let d1 = cal.date(byAdding: .day, value: -1, to: today) {
            progressByDay[startOfDay(d1)] = 0.8
        }
        if let d2 = cal.date(byAdding: .day, value: -2, to: today) {
            progressByDay[startOfDay(d2)] = 1.0
        }
        if let d3 = cal.date(byAdding: .day, value: 1, to: today) {
            progressByDay[startOfDay(d3)] = 0.1
        }
        if let d4 = cal.date(byAdding: .day, value: 2, to: today) {
            progressByDay[startOfDay(d4)] = 0.55
        }
    }
}
