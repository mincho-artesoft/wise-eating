import SwiftUI

struct WrappingSegmentedControl<T: Hashable & Identifiable & CaseIterable & RawRepresentable>: View where T.AllCases == [T], T.RawValue == String {
    
    enum LayoutMode {
        case wrap
        case scrollable
    }
    
    @Binding private var selection: T?
    let layoutMode: LayoutMode
    private let allowsEmptySelection: Bool
    private let selectionTint: ((T) -> Color)?
    private let systemImage: (T) -> String?
    
    @ObservedObject private var effectManager = EffectManager.shared
    @Namespace private var animation
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    // --- НАЧАЛО НА ПРОМЯНАТА (1/3): Добавяме State за контрол на анимацията ---
    @State private var isAnimatingSelection = false
    // --- КРАЙ НА ПРОМЯНАТА (1/3) ---

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }
    
    init(
        selection: Binding<T>,
        layoutMode: LayoutMode = .wrap,
        selectionTint: ((T) -> Color)? = nil,
        systemImage: @escaping (T) -> String? = { _ in nil }
    ) {
        self._selection = Binding<T?>(
            get: { selection.wrappedValue },
            set: { newValue in
                if let newValue {
                    selection.wrappedValue = newValue
                }
            }
        )
        self.layoutMode = layoutMode
        self.allowsEmptySelection = false
        self.selectionTint = selectionTint
        self.systemImage = systemImage
    }

    init(
        selection: Binding<T?>,
        layoutMode: LayoutMode = .wrap,
        selectionTint: ((T) -> Color)? = nil,
        systemImage: @escaping (T) -> String? = { _ in nil }
    ) {
        self._selection = selection
        self.layoutMode = layoutMode
        self.allowsEmptySelection = true
        self.selectionTint = selectionTint
        self.systemImage = systemImage
    }
    
    var body: some View {
        VStack{
            if isPadLayout {
                ipadLayout
            } else {
                iphoneLayout
            }
        }
    }
    
    @ViewBuilder
    private var ipadLayout: some View {
        wrappingLayout
    }
    
    @ViewBuilder
    private var iphoneLayout: some View {
        switch layoutMode {
        case .wrap:
            wrappingLayout
        case .scrollable:
            scrollableLayout
        }
    }
    
    private var wrappingLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(T.allCases) { item in
                    segmentButton(for: item)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)

            CustomFlowLayout(horizontalSpacing: 0, verticalSpacing: 8) {
                ForEach(T.allCases) { item in
                    segmentButton(for: item)
                }
            }
        }
        .padding(.horizontal, 2)
    }
    
    private var scrollableLayout: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(T.allCases) { item in
                    segmentButton(for: item)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 38)
    }
    
    @ViewBuilder
    private func segmentButton(for item: T) -> some View {
        let isSelected = selection == item
        let itemTint = selectionTint?(item)

        Button(action: {
            // Анимация за местене на фона
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selection = allowsEmptySelection && selection == item ? nil : item
            }
            
            // --- НАЧАЛО НА ПРОМЯНАТА (2/3): Задействаме "bubble" анимацията ---
            // 1. Задаваме състоянието, за да се уголеми бутонът
            isAnimatingSelection = true
            // 2. С леко забавяне и друга пружинна анимация, връщаме състоянието,
            // за да се смали бутонът обратно.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.35).delay(0.15)) {
                isAnimatingSelection = false
            }
            // --- КРАЙ НА ПРОМЯНАТА (2/3) ---
        }) {
            HStack(spacing: 5) {
                if let systemImage = systemImage(item) {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(item.rawValue)
            }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .foregroundColor(
                    isSelected
                        ? (itemTint ?? effectManager.currentGlobalAccentColor)
                        : effectManager.currentGlobalAccentColor
                )
                .background(
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(itemTint?.opacity(0.18) ?? Color.clear)
                                .glassCardStyle(cornerRadius: 20)
                                .matchedGeometryEffect(id: "selection_pill", in: animation)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("segment-\(item.rawValue)")
        .accessibilityLabel(item.rawValue)
        // --- НАЧАЛО НА ПРОМЯНАТА (3/3): Прилагаме ефекта за мащабиране ---
        .scaleEffect(isSelected && isAnimatingSelection ? 1.2 : 1.0)
        // --- КРАЙ НА ПРОМЯНАТА (3/3) ---
    }
}
