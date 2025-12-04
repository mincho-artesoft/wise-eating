import SwiftUI

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}


extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
    
    func capsuleInput(
        height: CGFloat = 44,
        cornerRadius: CGFloat = 16,
        fontSize: CGFloat = 16,
        background: AnyShapeStyle = .init(Color.clear),
        isFixedHeight: Bool = true
    ) -> some View {
        modifier(
            CapsuleInputStyle(
                height: height,
                cornerRadius: cornerRadius,
                isFixedHeight: isFixedHeight
            )
        )
    }
    
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
    }
    
    func renderAsImage(size: CGSize) -> UIImage? {
        let controller = UIHostingController(rootView: self.edgesIgnoringSafeArea(.all))
        guard let view = controller.view else { return nil }

        view.bounds = CGRect(origin: .zero, size: size)
        view.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: size)
        view.layoutIfNeeded()

        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }
    
    func glassCardStyle(cornerRadius: CGFloat = 20.0, useSnapShot: Int? = 1) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius, useSpanShot: useSnapShot!))
            .shadow(color: .black.opacity(0.15), radius: cornerRadius, y: 10)
    }
    
    func intelligentContrast() -> some View {
        self.modifier(IntelligentContrastModifier())
    }
    
    @inlinable
    func onChangeDebounced<Value: Equatable>(
        of value: Value,
        debounce seconds: TimeInterval = 0.15,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        modifier(OnChangeDebouncedModifier(of: value, debounce: seconds, action: action))
    }
    
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool,
                             transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
    
    @ViewBuilder
    func `if`<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        if ifTransform: (Self) -> TrueContent,
        else elseTransform: (Self) -> FalseContent
    ) -> some View {
        if condition {
            ifTransform(self)
        } else {
            elseTransform(self)
        }
    }
}
