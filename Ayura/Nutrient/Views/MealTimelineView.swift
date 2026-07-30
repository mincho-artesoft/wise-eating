import SwiftUI
import EventKit

// MARK: – PrefKey (width of the HStack with tabs)
private struct TabsWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: – Timeline view
struct MealTimelineView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Binding var meals: [Meal]
    @Binding var selectedMealID: Meal.ID?
    var showOnlySelected: Bool = false
    
    // Helpers
    private let calendar = Calendar.current
    private func secs(_ d: Date) -> Double {
        Double(calendar.dateComponents([.second],
                                       from: calendar.startOfDay(for: d),
                                       to:   d).second ?? 0)
    }
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    
    private static let palette: [Color] = [
        .orange, .pink, .green, .indigo, .purple, .blue, .red, Color(hex: "#00ffff")
    ]
    
    private var colorFor: [Meal.ID: Color] {
        let sorted = meals.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let n = Self.palette.count
        return Dictionary(uniqueKeysWithValues:
            sorted.enumerated().map { idx, meal in
                (meal.id, Self.palette[idx % n])
            })
    }

    
    @State private var initialStart: [Meal.ID : Date] = [:]
    
    // ----- 👇 НАЧАЛО НА ПРОМЯНАТА (1/3) 👇 -----
    // Добавяме състояние, което да пази продължителността на влаченото събитие.
    @State private var dragDuration: TimeInterval? = nil
    // ----- 👆 КРАЙ НА ПРОМЯНАТА (1/3) 👆 -----
    
    @State private var tabsWidth:      CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var grabOffset: [Meal.ID: CGFloat] = [:]
    
    private var uses12HourClock: Bool {
        let localeForDetection = Locale.autoupdatingCurrent
        let fmt = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: localeForDetection) ?? ""
        return fmt.contains("a")
    }

    private func hourString(_ hour: Int) -> String {
        let effectiveHour = hour % 24
        
        if uses12HourClock {
            let hrMod12 = effectiveHour % 12
            let displayHour = hrMod12 == 0 ? 12 : hrMod12
            let ampm: String
            if hour == 24 {
                ampm = "AM"
            } else {
                ampm = effectiveHour < 12 ? "AM" : "PM"
            }
            return "\(displayHour) \(ampm)"
        } else {
            if hour == 24 {
                return "24:00"
            }
            return String(format: "%02d:00", effectiveHour)
        }
    }
    
    //────────────────────────────────────────────
    // UI
    //────────────────────────────────────────────
    var body: some View {
        VStack(spacing: 0) {
            
            GeometryReader { geo in
                let px: (Double) -> CGFloat = { sec in
                    geo.size.width * CGFloat(sec / 86_400)
                }
                
                let arrowH: CGFloat = 4 // Малко по-висока за по-добър ефект
                let axisY : CGFloat = 11
                let lineY : CGFloat = axisY + arrowH // Позицията на балончетата и линията
                
                ZStack(alignment: .topLeading) {
                    
                    // 2.1 Timeline Axis
                    Path { p in
                        p.move(to: .init(x: 0, y: lineY))
                        p.addLine(to: .init(x: geo.size.width, y: lineY))
                    }
                    .stroke(effectManager.currentGlobalAccentColor.opacity(0.5), lineWidth: 0.5)
                    
                    // 2.2 Hour Markers
                    ForEach(Array(stride(from: 0, through: 24, by: 4)), id: \.self) { h in
                        let x = px(Double(h) * 3_600)
                        
                        let label = hourString(h)
                        
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                            .position(x: x, y: axisY - 8)
                        
                        Path { p in
                            p.move(to: .init(x: x, y: lineY - (arrowH / 2)))
                            p.addLine(to: .init(x: x, y: lineY + (arrowH / 2)))
                        }
                        .stroke(effectManager.currentGlobalAccentColor.opacity(0.5), lineWidth: 1)
                    }
                    
                    // 2.3 Meal Bubbles
                    ForEach($meals) { $meal in
                        if !showOnlySelected || meal.id == selectedMealID {
                            let dayNumberLabelColor = effectManager.isLightRowTextColor ?  Color.black : Color.white
                            let base = colorFor[meal.id] ?? dayNumberLabelColor
                            let sel  = meal.id == selectedMealID
                            
                            let startSec = secs(meal.startTime)
                            
                            let xCenter = px(startSec)
                            
                            let bubbleHeight: CGFloat = 30
                            
                            RoundedRectangle(cornerRadius: 8)
                                .fill(sel ? base.opacity(0.3) : base.opacity(0.25))
                                .glassCardStyle(cornerRadius: 20)
                                .frame(width: 70, height: bubbleHeight)
                                .overlay(
                                    Text(Self.timeFormatter.string(from: meal.startTime))
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(sel ? effectManager.currentGlobalAccentColor : base)
                                )
                                .position(x: xCenter, y: lineY)
                                .highPriorityGesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { g in
                                            if !sel { selectedMealID = meal.id }
                                            
                                            // ----- 👇 НАЧАЛО НА ПРОМЯНАТА (2/3) 👇 -----
                                            // 1. Запазваме оригиналната продължителност САМО веднъж в началото на жеста.
                                            if dragDuration == nil {
                                                dragDuration = meal.endTime.timeIntervalSince(meal.startTime)
                                            }
                                            guard let capturedDuration = dragDuration else { return }
                                            // ----- 👆 КРАЙ НА ПРОМЯНАТА (2/3) 👆 -----

                                            let fingerPx = max(0, min(g.location.x, geo.size.width))
                                            
                                            if grabOffset[meal.id] == nil {
                                                grabOffset[meal.id] = fingerPx - px(startSec)
                                            }
                                            let offsetPx = grabOffset[meal.id] ?? 0
                                            
                                            var anchorPx = fingerPx - offsetPx
                                            
                                            let maxStartSecRaw: Double = 86_340
                                            let stepSec:      Double = 300
                                            let maxStartSec:  Double = floor(maxStartSecRaw / stepSec) * stepSec
                                            let maxAnchorPx   = px(maxStartSec)
                                            anchorPx = min(max(anchorPx, 0), maxAnchorPx)
                                            
                                            var newStart = Double(anchorPx / geo.size.width) * 86_400
                                            newStart = (newStart / stepSec).rounded() * stepSec
                                            newStart = min(max(0, newStart), maxStartSec)
                                            
                                            let day0 = calendar.startOfDay(for: meal.startTime)
                                            meal.startTime = day0.addingTimeInterval(newStart)

                                            // ----- 👇 НАЧАЛО НА ПРОМЯНАТА (3/3) 👇 -----
                                            // 2. Изчисляваме новия край, като добавим запазената продължителност.
                                            meal.endTime = meal.startTime.addingTimeInterval(capturedDuration)
                                            // ----- 👆 КРАЙ НА ПРОМЯНАТА (3/3) 👆 -----
                                        }
                                        .onEnded { _ in
                                            grabOffset[meal.id] = nil
                                            // 3. Нулираме запазената продължителност след края на жеста.
                                            dragDuration = nil
                                        }
                                )
                        }
                    }
                }
            }
            .padding(.top, -30)
            
            
            // 1. Horizontal Tab Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let sortedByDBTime = meals.sorted {
                        (initialStart[$0.id] ?? $0.startTime) <
                        (initialStart[$1.id] ?? $1.startTime)
                    }
                    
                    ForEach(sortedByDBTime, id: \.id) { meal in
                        let dayNumberLabelColor = effectManager.isLightRowTextColor ?  Color.black : Color.white
                        let base = colorFor[meal.id] ?? dayNumberLabelColor
                        let sel  = selectedMealID == meal.id
                        
                        Button {
                            withAnimation { selectedMealID = meal.id }
                        } label: {
                            Text(meal.name)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical,   6)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(sel ? base.opacity(0.8) : base.opacity(0.3))
                                    }
                                )
                                .glassCardStyle(cornerRadius: 20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(base, lineWidth: sel ? 2 : 0)
                                )
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: TabsWidthKey.self,
                                        value: geo.size.width)
                    }
                )
            }
            .padding(.top, -80)
            .frame(maxWidth: .infinity)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {    availableWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in
                            availableWidth = w
                        }
                }
            )
            .scrollDisabled(tabsWidth <= availableWidth)
            .onPreferenceChange(TabsWidthKey.self) { tabsWidth = $0 }
            .onAppear {
                if initialStart.isEmpty {
                    initialStart = Dictionary(uniqueKeysWithValues:
                        meals.map { ($0.id, $0.startTime) })
                }
            }
        }
    }
}
