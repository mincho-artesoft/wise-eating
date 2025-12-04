import SwiftUI

struct Trapezoid: Shape {
    enum SkewType { case top, bottom, left, right }
    var type: SkewType
    var amount: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var p1 = CGPoint(x: rect.minX, y: rect.minY), p2 = CGPoint(x: rect.maxX, y: rect.minY),
            p3 = CGPoint(x: rect.maxX, y: rect.maxY), p4 = CGPoint(x: rect.minX, y: rect.maxY)

        switch type {
        case .top:      p1.x -= amount; p2.x += amount
        case .bottom:   p4.x -= amount; p3.x += amount
        case .left:     p1.y -= amount; p4.y += amount
        case .right:    p2.y -= amount; p3.y += amount
        }
        path.move(to: p1); path.addLine(to: p2); path.addLine(to: p3); path.addLine(to: p4); path.closeSubpath()
        return path
    }
}
