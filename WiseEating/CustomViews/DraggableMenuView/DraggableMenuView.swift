import SwiftUI

/// A draggable bottom sheet menu with a glass effect that fades in and out.
struct DraggableMenuView<
    HorizontalContent: View,
    VerticalContent: View
>: View {

    // MARK: — Dependencies
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: — Config
    private let collapsedPeekExtra: CGFloat = 10
    private let fixedBottomBarHeight: CGFloat = 80
    private let handleHeight: CGFloat = 26
    private let defaultTopGapWhenExpanded: CGFloat = UIScreen.main.bounds.height * 0.2

    // Позволява да зададем custom отстояние отгоре при .full
    private let customTopGap: CGFloat?

    // MARK: — External bindings & callbacks
    @Binding var menuState: MenuState
    @State var removeBottomPading: Bool = false

    let onStateChange: (MenuState) -> Void
    let onWillExpand: () -> Void

    // MARK: — Customizable slots
    let horizontalScrollContent: HorizontalContent
    let verticalScrollContent: VerticalContent

    // MARK: — Internal state for dragging
    // Важно: правим го optional, за да можем да използваме правилната начална стойност още в първия кадър
    @State private var currentOffsetY: CGFloat? = nil
    @GestureState private var dragGestureTranslationY: CGFloat = 0

    // MARK: — Init
    init(
        menuState: Binding<MenuState>,
        removeBottomPading: Bool? = false,
        customTopGap: CGFloat? = nil,
        @ViewBuilder horizontalContent: () -> HorizontalContent,
        @ViewBuilder verticalContent: () -> VerticalContent,
        onStateChange: @escaping (MenuState) -> Void = { _ in },
        onWillExpand: @escaping () -> Void = {}
    ) {
        self._menuState = menuState
        self.removeBottomPading = removeBottomPading ?? false
        self.customTopGap = customTopGap
        self.onStateChange = onStateChange
        self.onWillExpand = onWillExpand
        self.horizontalScrollContent = horizontalContent()
        self.verticalScrollContent = verticalContent()
    }

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            
            // Използваме custom стойността, ако е дадена
            let fullOffsetY = customTopGap ?? defaultTopGapWhenExpanded
            
            let clippingHeight   = screenHeight - fixedBottomBarHeight
            let collapsedOffsetY = max(fullOffsetY, clippingHeight - handleHeight + collapsedPeekExtra)

            // Начална стойност още в първия кадър (без да чакаме onAppear)
            let initialOffsetY = (menuState == .full) ? fullOffsetY : collapsedOffsetY
            let baseOffsetY = currentOffsetY ?? initialOffsetY

            let dragY      = baseOffsetY + dragGestureTranslationY
            let effectiveY = max(fullOffsetY, min(collapsedOffsetY, dragY))

            let contentOpacity: CGFloat = {
                let totalDragDistance = collapsedOffsetY - fullOffsetY
                guard totalDragDistance > 0 else { return menuState == .full ? 1 : 0 }
                let currentDragFromBottom = collapsedOffsetY - effectiveY
                return pow(min(max(currentDragFromBottom / totalDragDistance, 0), 1), 2)
            }()

            slidingContentView(
                fullOffsetY: fullOffsetY,
                collapsedOffsetY: collapsedOffsetY,
                contentOpacity: contentOpacity
            )
            .contentShape(Rectangle())
            .offset(y: effectiveY)
            // В тези анимации използваме baseOffsetY (fall-back към initial), за да няма “премигване” при старта
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: baseOffsetY)
            .animation(.interactiveSpring, value: dragGestureTranslationY)
            .onAppear {
                // Първоначално задаваме стойността без анимация, ако още е nil
                if currentOffsetY == nil {
                    var txn = Transaction()
                    txn.animation = nil
                    withTransaction(txn) {
                        currentOffsetY = initialOffsetY
                    }
                }
            }
            .onChange(of: menuState) { _, newState in
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentOffsetY = (newState == .full) ? fullOffsetY : collapsedOffsetY
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }

    @ViewBuilder
    private func slidingContentView(
        fullOffsetY: CGFloat,
        collapsedOffsetY: CGFloat,
        contentOpacity: CGFloat
    ) -> some View {
        let handleColor = effectManager.currentGlobalAccentColor.opacity(0.6)
        
        ZStack {
            Color.clear

            VStack(spacing: 0) {
                handle(color: handleColor, fullOffset: fullOffsetY, collapsedOffset: collapsedOffsetY)
                mainContent()
            }
            .glassCardStyle(cornerRadius: 20)
            .opacity(contentOpacity)

            VStack(spacing: 0) {
                handle(color: handleColor, fullOffset: fullOffsetY, collapsedOffset: collapsedOffsetY)
                Spacer()
            }
            .opacity(1.0 - contentOpacity)
        }
    }
    
    @ViewBuilder
    private func handle(color: Color, fullOffset: CGFloat, collapsedOffset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 60, height: 6)
            .padding(.vertical, (handleHeight - 6) / 2)
            .contentShape(Rectangle())
            .gesture(
                dragGesture(fullOffset: fullOffset, collapsedOffset: collapsedOffset)
            )
    }
    
    @ViewBuilder
    private func mainContent() -> some View {
        VStack(spacing: 0) {
            horizontalScrollContent
                .frame(maxWidth: .infinity)
            
            verticalScrollContent
                .padding(.bottom, removeBottomPading ? 0 : fixedBottomBarHeight + handleHeight + 40)
               
        }
    }
    
    // MARK: — Drag gesture logic
    private func dragGesture(
        fullOffset: CGFloat,
        collapsedOffset: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .updating($dragGestureTranslationY) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                // Ако currentOffsetY още е nil, fallback към правилната начална стойност
                let current = currentOffsetY ?? ((menuState == .full) ? fullOffset : collapsedOffset)
                let predicted = current + value.predictedEndTranslation.height
                let snapPoints = [collapsedOffset, fullOffset]
                let closest = snapPoints.min(by: { abs($0 - predicted) < abs($1 - predicted) }) ?? collapsedOffset

                currentOffsetY = max(fullOffset, min(collapsedOffset, closest))

                let newState: MenuState = abs(closest - fullOffset) < 1 ? .full : .collapsed
                
                if newState == .full && menuState != .full {
                    self.onWillExpand()
                }

                if newState != menuState {
                    menuState = newState
                    onStateChange(newState)
                }
            }
    }
}
