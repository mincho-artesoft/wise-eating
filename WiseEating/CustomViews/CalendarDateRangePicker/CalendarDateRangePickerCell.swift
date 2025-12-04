import UIKit
import SwiftUI

// =====================================================================
// MARK: - Клетка (UICollectionViewCell)
// =====================================================================
public class CalendarDateRangePickerCell: UICollectionViewCell {

    // --- ПРОМЯНА: Премахваме хардкоднатите цветове ---
    
    // --- ПРОМЯНА: Нови променливи, които се задават от ViewController ---
    var accentColor: UIColor!
    var secondaryAccentColor: UIColor!
    var selectedTextColor: UIColor!
    
    var selectedColor: UIColor!
    var date: Date?
    
    var lineView: UIView?
    var circleView: UIView?
    // +++ НАЧАЛО НА ПРОМЯНАТА (1/3) +++
    var eventIndicator: UIView?
    // +++ КРАЙ НА ПРОМЯНАТА (1/3) +++
    var label: UILabel!

    // MARK: - Инициализация
    override init(frame: CGRect) {
        super.init(frame: frame)
        initLabel()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initLabel()
    }

    func initLabel() {
        label = UILabel(frame: bounds)
        label.center = CGPoint(x: bounds.size.width / 2, y: bounds.size.height / 2)
        label.font = UIFont(name: "HelveticaNeue", size: 18.0)
        label.textAlignment = .center
        self.addSubview(label)
    }

    /// Изчиства предишни състояния (изтрива кръга/линията)
    func reset() {
        self.backgroundColor = .clear
        // --- ПРОМЯНА: Използваме цвета от темата ---
        label.textColor = accentColor
        
        lineView?.removeFromSuperview()
        lineView = nil
        
        circleView?.removeFromSuperview()
        circleView = nil
        
        // +++ НАЧАЛО НА ПРОМЯНАТА (2/3) +++
        eventIndicator?.removeFromSuperview()
        eventIndicator = nil
        // +++ КРАЙ НА ПРОМЯНАТА (2/3) +++
    }
    
    /// Чертае сива линия от xStart до xEnd.
    func addLine(from xStart: CGFloat, to xEnd: CGFloat) {
        let h = bounds.height
        let rect = CGRect(x: xStart, y: 0, width: xEnd - xStart, height: h)
        let v = UIView(frame: rect)
        // --- ПРОМЯНА: Използваме цвета от темата с прозрачност ---
        v.backgroundColor = accentColor.withAlphaComponent(0.2)

        self.addSubview(v)
        self.sendSubviewToBack(v)
        
        lineView = v
    }
    
    /// Чертай кръг зад датата (selectedColor)
    func addCircle() {
        let w = bounds.width
        let h = bounds.height
        let diameter = min(w, h)
        let circleX = (w - diameter) / 2
        let circleY = (h - diameter) / 2

        let circleRect = CGRect(x: circleX, y: circleY, width: diameter, height: diameter)
        let cView = UIView(frame: circleRect)
        cView.backgroundColor = selectedColor
        cView.layer.cornerRadius = diameter / 2
        
        self.insertSubview(cView, belowSubview: label)
        circleView = cView

        // --- ПРОМЯНА: Използваме адаптивен цвят за текста върху селекцията ---
        label.textColor = selectedTextColor
    }
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (3/3) +++
    /// Добавя малка оранжева точка под числото на датата.
    func addEventIndicator() {
        let diameter: CGFloat = 5
        let dotX = (bounds.width - diameter) / 2
        // Позиционираме точката под вертикалния център на клетката
        let dotY = (bounds.height / 2) + 12
        
        let v = UIView(frame: CGRect(x: dotX, y: dotY, width: diameter, height: diameter))
        v.backgroundColor = .orange
        v.layer.cornerRadius = diameter / 2
        
        self.addSubview(v)
        eventIndicator = v
    }
    // +++ КРАЙ НА ПРОМЯНАТА (3/3) +++
}
