import SwiftUI
import EventKit

// MARK: – PrefKey (width of the HStack with tabs)
private struct TrainingTabsWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: – Timeline view
struct TrainingTimelineView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Binding var trainings: [Training]
    @Binding var selectedTrainingID: Training.ID?
    var showOnlySelected: Bool = false
    var onTimeChanged: (() -> Void)?
    
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
    
    // Използваме различна палитра за тренировките, за да се отличават
    private static let palette: [Color] = [
        .cyan, .green, .indigo, .orange, .pink, .purple, .blue, .red
    ]
    
    private var colorFor: [Training.ID: Color] {
        let sorted = trainings.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let n = Self.palette.count
        return Dictionary(uniqueKeysWithValues:
            sorted.enumerated().map { idx, training in
                (training.id, Self.palette[idx % n])
            })
    }

    @State private var initialStart: [Training.ID : Date] = [:]
    @State private var dragDuration: TimeInterval? = nil
    
    @State private var tabsWidth:      CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var grabOffset: [Training.ID: CGFloat] = [:]
    
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
    
    var body: some View {
        VStack(spacing: 0) {
            
            GeometryReader { geo in
                let px: (Double) -> CGFloat = { sec in
                    geo.size.width * CGFloat(sec / 86_400)
                }
                
                let arrowH: CGFloat = 4
                let axisY : CGFloat = 11
                let lineY : CGFloat = axisY + arrowH
                
                ZStack(alignment: .topLeading) {
                    
                    Path { p in
                        p.move(to: .init(x: 0, y: lineY))
                        p.addLine(to: .init(x: geo.size.width, y: lineY))
                    }
                    .stroke(effectManager.currentGlobalAccentColor.opacity(0.5), lineWidth: 0.5)
                    
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
                    
                    ForEach($trainings) { $training in
                        if !showOnlySelected || training.id == selectedTrainingID {
                            let dayNumberLabelColor = effectManager.isLightRowTextColor ? Color.black : Color.white
                            let base = colorFor[training.id] ?? dayNumberLabelColor
                            let sel  = training.id == selectedTrainingID
                            
                            let startSec = secs(training.startTime)
                            let xCenter = px(startSec)
                            
                            let bubbleHeight: CGFloat = 30
                            
                            RoundedRectangle(cornerRadius: 8)
                                .fill(sel ? base.opacity(0.3) : base.opacity(0.25))
                                .glassCardStyle(cornerRadius: 20)
                                .frame(width: 70, height: bubbleHeight)
                                .overlay(
                                    Text(Self.timeFormatter.string(from: training.startTime))
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(sel ? effectManager.currentGlobalAccentColor : base)
                                )
                                .position(x: xCenter, y: lineY)
                                .highPriorityGesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { g in
                                            if !sel { selectedTrainingID = training.id }
                                            
                                            if dragDuration == nil {
                                                dragDuration = training.endTime.timeIntervalSince(training.startTime)
                                            }
                                            guard let capturedDuration = dragDuration else { return }

                                            let fingerPx = max(0, min(g.location.x, geo.size.width))
                                            
                                            if grabOffset[training.id] == nil {
                                                grabOffset[training.id] = fingerPx - px(startSec)
                                            }
                                            let offsetPx = grabOffset[training.id] ?? 0
                                            
                                            var anchorPx = fingerPx - offsetPx
                                            
                                            let maxStartSecRaw: Double = 86_340
                                            let stepSec:      Double = 300
                                            let maxStartSec:  Double = floor(maxStartSecRaw / stepSec) * stepSec
                                            let maxAnchorPx   = px(maxStartSec)
                                            anchorPx = min(max(anchorPx, 0), maxAnchorPx)
                                            
                                            var newStart = Double(anchorPx / geo.size.width) * 86_400
                                            newStart = (newStart / stepSec).rounded() * stepSec
                                            newStart = min(max(0, newStart), maxStartSec)
                                            
                                            let day0 = calendar.startOfDay(for: training.startTime)
                                            training.startTime = day0.addingTimeInterval(newStart)
                                            training.endTime = training.startTime.addingTimeInterval(capturedDuration)
                                        }
                                        .onEnded { _ in
                                            grabOffset[training.id] = nil
                                            dragDuration = nil
                                            onTimeChanged?()
                                        }
                                )
                        }
                    }
                }
            }
            .padding(.top, -30)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let sortedByDBTime = trainings.sorted {
                        (initialStart[$0.id] ?? $0.startTime) <
                        (initialStart[$1.id] ?? $1.startTime)
                    }
                    
                    ForEach(sortedByDBTime, id: \.id) { training in
                        let dayNumberLabelColor = effectManager.isLightRowTextColor ? Color.black : Color.white
                        let base = colorFor[training.id] ?? dayNumberLabelColor
                        let sel  = selectedTrainingID == training.id
                        
                        Button {
                            withAnimation { selectedTrainingID = training.id }
                        } label: {
                            Text(training.name)
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
                            .preference(key: TrainingTabsWidthKey.self,
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
            .onPreferenceChange(TrainingTabsWidthKey.self) { tabsWidth = $0 }
            .onAppear {
                if initialStart.isEmpty {
                    initialStart = Dictionary(uniqueKeysWithValues:
                        trainings.map { ($0.id, $0.startTime) })
                }
            }
        }
    }
}
