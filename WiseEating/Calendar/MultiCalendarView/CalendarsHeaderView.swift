import UIKit
import EventKit

final class CalendarsHeaderView: UIView {
    /// Данни за всеки календар: [calendarID: (title, color, selected)]
    var calendarsDict: [String: (title: String, color: UIColor, selected: Bool, calendar: EKCalendar)] = [:] {
        didSet {
            rebuildSubviews()
        }
    }
    
    /// Базова (минимална) ширина на колона, ползва се ако имаме >= 4 колони
    var defaultColumnWidth: CGFloat = 100
    
    // Масив от UILabel за визуализация
    private var labelViews: [UILabel] = []
    
    // Инициализатори
    override init(frame: CGRect) {
        super.init(frame: frame)
        // ✅ CHANGED: isOpaque must be false for transparency to work.
        isOpaque = false
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        // ✅ CHANGED: isOpaque must be false for transparency to work.
        isOpaque = false
        backgroundColor = .clear
    }

    private func rebuildSubviews() {
        // 1) Премахваме старите labels
        labelViews.forEach { $0.removeFromSuperview() }
        labelViews = []

        // 2) Избираме календарите, които трябва да се покажат
        let selectedCals = calendarsDict.filter { $0.value.selected }
        let calsToDraw: [(String, (title: String, color: UIColor, selected: Bool, calendar: EKCalendar))]
        if selectedCals.isEmpty {
            // ако няма селектирани -> показваме всички
            calsToDraw = Array(calendarsDict)
        } else {
            calsToDraw = Array(selectedCals)
        }

        // 3) Сортираме ги по .title
        let sortedCals = calsToDraw.sorted { $0.1.title < $1.1.title }

        // 4) Създаваме UILabel за всеки, в сортиран ред
        for (_, info) in sortedCals {
            let label = UILabel()
            label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            label.text = info.title
            label.textAlignment = .center
            label.textColor = info.color
            label.backgroundColor = .clear
            addSubview(label)
            labelViews.append(label)
        }

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        let count = labelViews.count
        guard count > 0 else { return }
        
        let totalWidth = bounds.width
        let isLandscape = bounds.width > bounds.height

        let actualColumnWidth: CGFloat
        if isLandscape {
            if count < 7 {
                actualColumnWidth = totalWidth / CGFloat(count)
            } else {
                actualColumnWidth = defaultColumnWidth
            }
        } else {
            if count < 4 {
                actualColumnWidth = totalWidth / CGFloat(count)
            } else {
                actualColumnWidth = defaultColumnWidth
            }
        }
        
        for (index, lbl) in labelViews.enumerated() {
            let xPos = CGFloat(index) * actualColumnWidth
            lbl.frame = CGRect(
                x: xPos,
                y: 0,
                width: actualColumnWidth,
                height: bounds.height
            )
        }
        
        if let scrollView = superview as? UIScrollView {
            let contentW = CGFloat(count) * actualColumnWidth
            scrollView.contentSize = CGSize(width: contentW, height: bounds.height)
        }
        
        // We need to trigger a redraw after layout to correctly place the separator lines.
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        // We don't call super.draw(rect) as we are custom drawing everything.
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        // ✅ CHANGED: The two lines that filled the background are removed.
        // The view is now transparent, and we only draw the separator lines.
        
        // (1) Задаваме тънка (1 px) линия и цвят, който изглежда добре на градиентен фон.
        ctx.setLineWidth(1.0 / UIScreen.main.scale)
        UIColor.white.withAlphaComponent(0.4).setStroke() // A subtle white line
        
        // (2) Чертаем линия в началото на всеки (без първия) label
        if labelViews.count > 1 {
            for i in 1..<labelViews.count {
                // Ensure pixel-perfect drawing to avoid anti-aliasing blur
                let xPos = round(labelViews[i].frame.minX * UIScreen.main.scale) / UIScreen.main.scale
                ctx.move(to: CGPoint(x: xPos, y: 5)) // Add some inset from top/bottom
                ctx.addLine(to: CGPoint(x: xPos, y: bounds.height - 5))
                ctx.strokePath()
            }
        }
    }
}
