import SwiftUI
import UIKit

struct WaterTrackerView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    @Binding var consumed: Int
    let goal: Int
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    // Настройка: колко пиксела драг = 1 единица вода
    private let pointsPerUnit: CGFloat = 24

    // Вътрешно за дръпването
    @State private var dragBuffer: CGFloat = 0
    @State private var lastTranslationY: CGFloat = 0

    var body: some View {
        // Само чашата – жестовете са върху нея
        WaterGlassGauge(
            consumed: consumed,
            goal: goal,
            accent: effectManager.currentGlobalAccentColor
        )
        .frame(width: 60, height: 60)
        .animation(.easeInOut(duration: 0.25), value: consumed)
        .contentShape(Rectangle()) // цялата зона да хваща жестове
        // Тап = +1
        .highPriorityGesture(
            TapGesture()
                .onEnded {
                    onIncrement()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
        )
        // Драг = +/- по стъпки
        .highPriorityGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    let delta = value.translation.height - lastTranslationY
                    lastTranslationY = value.translation.height
                    dragBuffer += delta

                    // Надолу (положителен delta) => намаляване
                    // Нагоре (отрицателен delta)    => увеличаване
                    while dragBuffer <= -pointsPerUnit {
                        onIncrement()
                        dragBuffer += pointsPerUnit
                    }
                    while dragBuffer >= pointsPerUnit {
                        onDecrement()
                        dragBuffer -= pointsPerUnit
                    }
                }
                .onEnded { _ in
                    dragBuffer = 0
                    lastTranslationY = 0
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Water intake")
        .accessibilityValue("\(consumed) of \(goal)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onIncrement()
            case .decrement: onDecrement()
            default: break
            }
        }
    }
}

private struct WaterGlassGauge: View {
    let consumed: Int
    let goal: Int
    let accent: Color

    // --- НАЧАЛО НА ПРОМЯНА 1: Премахваме първоначалната стойност = 0 ---
    @State private var displayProgress: CGFloat
    // --- КРАЙ НА ПРОМЯНА 1 ---
    @State private var amplitude: CGFloat = 0.018

    private var targetProgress: CGFloat {
        guard goal > 0 else { return 0 }
        return CGFloat(min(max(Double(consumed) / Double(goal), 0), 1))
    }
    
    // --- НАЧАЛО НА ПРОМЯНА 2: Добавяме init, за да зададем началното състояние ---
    init(consumed: Int, goal: Int, accent: Color) {
        self.consumed = consumed
        self.goal = goal
        self.accent = accent
        
        let initialTarget = (goal > 0) ? CGFloat(min(max(Double(consumed) / Double(goal), 0), 1)) : 0
        self._displayProgress = State(initialValue: initialTarget)
    }
    // --- КРАЙ НА ПРОМЯНА 2 ---

    private var spring: Animation {
        if #available(iOS 17.0, *) {
            return .snappy(duration: 0.6, extraBounce: 0.1)
        } else {
            return .interpolatingSpring(stiffness: 140, damping: 18)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
            GeometryReader { geo in
                let size = geo.size
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = CGFloat(t * 1.6)

                ZStack {
                    Canvas { context, size in
                        let w = size.width
                        let h = size.height

                        // Геометрия на чашата (трапец)
                        let topInset: CGFloat = w * 0.12
                        let bottomInset: CGFloat = w * 0.28
                        let topY: CGFloat = h * 0.10
                        let bottomY: CGFloat = h * 0.90

                        let topLeft     = CGPoint(x: topInset,           y: topY)
                        let topRight    = CGPoint(x: w - topInset,       y: topY)
                        let bottomRight = CGPoint(x: w - bottomInset,    y: bottomY)
                        let bottomLeft  = CGPoint(x: bottomInset,        y: bottomY)

                        // ЗАТВОРЕН клип за вътрешността
                        var glassClip = Path()
                        glassClip.move(to: topLeft)
                        glassClip.addLine(to: topRight)
                        glassClip.addLine(to: bottomRight)
                        glassClip.addLine(to: bottomLeft)
                        glassClip.closeSubpath()

                        // ОЧЕРТАНИЕ без горна линия (ляв → долу → десен)
                        var glassOutline = Path()
                        glassOutline.move(to: topLeft)
                        glassOutline.addLine(to: bottomLeft)   // ляв ръб
                        glassOutline.addLine(to: bottomRight)  // дъно
                        glassOutline.addLine(to: topRight)     // десен ръб
                        context.stroke(glassOutline, with: .color(accent.opacity(0.95)), lineWidth: 2)

                        // Рисуване вътре в чашата
                        context.drawLayer { layer in
                            layer.clip(to: glassClip)

                            // Ниво на водата
                            let glassHeight = bottomY - topY
                            let baseY = bottomY - glassHeight * displayProgress

                            // Вълни
                            let ampPix = h * amplitude
                            let wavelength = w * 0.9

                            func waterPath(phase: CGFloat, lift: CGFloat = 0) -> Path {
                                var p = Path()
                                p.move(to: CGPoint(x: 0, y: bottomY))
                                p.addLine(to: CGPoint(x: 0, y: baseY))
                                var x: CGFloat = 0
                                while x <= w {
                                    let y = baseY
                                        + sin((x / wavelength) * .pi * 2 + phase) * ampPix
                                        + lift
                                    p.addLine(to: CGPoint(x: x, y: y))
                                    x += 1.0
                                }
                                p.addLine(to: CGPoint(x: w, y: bottomY))
                                p.closeSubpath()
                                return p
                            }

                            // Градиент за водата
                            let waterGradient = Gradient(colors: [
                                Color.blue.opacity(0.45),
                                Color.blue.opacity(0.85)
                            ])

                            // Долна маса
                            layer.fill(
                                waterPath(phase: phase),
                                with: .linearGradient(
                                    waterGradient,
                                    startPoint: CGPoint(x: 0, y: baseY),
                                    endPoint: CGPoint(x: 0, y: bottomY)
                                )
                            )

                            // Втора вълна за дълбочина
                            layer.fill(
                                waterPath(phase: phase + .pi/2, lift: ampPix * 0.1),
                                with: .linearGradient(
                                    waterGradient,
                                    startPoint: CGPoint(x: 0, y: baseY - ampPix * 0.2),
                                    endPoint: CGPoint(x: 0, y: bottomY)
                                )
                            )

                            // Подчертаване на повърхността
                            if displayProgress > 0 && displayProgress < 1 {
                                var crest = Path()
                                var x: CGFloat = 0
                                while x <= w {
                                    let y = baseY + sin((x / wavelength) * .pi * 2 + phase) * ampPix
                                    if x == 0 { crest.move(to: CGPoint(x: x, y: y)) }
                                    else { crest.addLine(to: CGPoint(x: x, y: y)) }
                                    x += 1.0
                                }
                                layer.stroke(crest, with: .color(Color.blue.opacity(0.55)), lineWidth: 1)
                            }
                        }

                        // === „Гърло“ на чашата – елипса (ръб) ===
                        let rimWidth  = topRight.x - topLeft.x
                        let rimHeight = w * 0.14  // визуална перспектива
                        let rimRect = CGRect(
                            x: topLeft.x,
                            y: topY - rimHeight * 0.45, // малко над topY, за да се вижда овал
                            width: rimWidth,
                            height: rimHeight
                        )

                        let rimPath = Path(ellipseIn: rimRect)
                        context.stroke(rimPath, with: .color(accent.opacity(0.95)), lineWidth: 1.0)

                        // лек „блясък“ на горната част на елипсата
                        var gloss = Path()
                        gloss.addArc(
                            center: CGPoint(x: rimRect.midX, y: rimRect.midY),
                            radius: rimRect.width / 2,
                            startAngle: .degrees(200),
                            endAngle: .degrees(340),
                            clockwise: false
                        )
                        context.stroke(gloss, with: .color(.white.opacity(0.25)), lineWidth: 0.8)
                    }

                    // Текст вътре в чашата
                    VStack(spacing: 0) {
                        Text("\(consumed)")
                            .font(.system(size: size.width * 0.33, weight: .bold))
                            .foregroundStyle(accent)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .contentTransition(.numericText())

                        Text("of \(max(goal, 0))")
                            .font(.system(size: size.width * 0.17, weight: .semibold))
                            .foregroundStyle(accent.opacity(0.85))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .padding(.top, size.height * 0.16)
                    .padding(.bottom, size.height * 0.12)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // --- НАЧАЛО НА ПРОМЯНА 3: Премахваме .onAppear ---
        // .onAppear { displayProgress = targetProgress }
        // --- КРАЙ НА ПРОМЯНА 3 ---
        .onChange(of: targetProgress) { _, new in
            let delta = abs(new - displayProgress)
            let spike = min(0.065, 0.018 + delta * 0.20)
            withAnimation(spring) {
                displayProgress = new
                amplitude = spike
            }
            withAnimation(.easeOut(duration: 0.9)) {
                amplitude = 0.018
            }
        }
    }
}
