import UIKit
import SwiftUI

struct SelectedDayBackgroundView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    var isToday: Bool

    var body: some View {
        let tintColor = isToday ? Color.red : effectManager.currentGlobalAccentColor
        
        Circle()
            .fill(Color.clear)
            .glassCardStyle(cornerRadius: 17.5)
            .overlay(
                Circle().fill(tintColor.opacity(0.7))
            )
    }
}


/// Една клетка от седмичния календар.
final class DayCell: UICollectionViewCell {
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: Subviews
    private let dayOfWeekLabel = UILabel()
    private let dayNumberLabel = UILabel()
    private let ringLayer      = CAShapeLayer()
    private var previousProgress: CGFloat?

    // MARK: Init
    override init(frame: CGRect) {
        super.init(frame: frame)

        dayOfWeekLabel.font          = .systemFont(ofSize: 12)
        dayOfWeekLabel.textAlignment = .center
        dayOfWeekLabel.textColor     = UIColor(effectManager.currentGlobalAccentColor.opacity(0.8))

        dayNumberLabel.font          = .systemFont(ofSize: 18, weight: .semibold)
        dayNumberLabel.textAlignment = .center
        dayNumberLabel.textColor     = .label
        dayNumberLabel.clipsToBounds = true
        
        contentView.addSubview(dayOfWeekLabel)
        contentView.addSubview(dayNumberLabel)

        ringLayer.fillColor   = UIColor.clear.cgColor
        ringLayer.strokeColor = UIColor.systemGreen.cgColor
        ringLayer.lineWidth   = 3
        ringLayer.strokeEnd   = 0
        contentView.layer.insertSublayer(ringLayer, below: dayNumberLabel.layer)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // --- START OF CORRECTION ---
        let side: CGFloat = 35
        let spacing: CGFloat = 10.0 
        // --- END OF CORRECTION ---
        
        let dayOfWeekLabelHeight = dayOfWeekLabel.font.lineHeight

        let totalContentHeight = dayOfWeekLabelHeight + spacing + side
        
        var startY = (contentView.bounds.height - totalContentHeight) / 2
        startY += 5.0

        dayOfWeekLabel.frame = CGRect(
            x: 0,
            y: startY,
            width: contentView.bounds.width,
            height: dayOfWeekLabelHeight
        )

        let dayNumberLabelY = startY + dayOfWeekLabelHeight + spacing
        let dayNumberLabelX = (contentView.bounds.width - side) / 2
        dayNumberLabel.frame = CGRect(
            x: dayNumberLabelX,
            y: dayNumberLabelY,
            width: side,
            height: side
        )
        dayNumberLabel.layer.cornerRadius = side / 2

        let ringPadding: CGFloat = 2.0
        let totalInset = -(ringPadding + ringLayer.lineWidth / 2)
        let ringFrame = dayNumberLabel.frame.insetBy(dx: totalInset, dy: totalInset)
        let center = CGPoint(x: ringFrame.midX, y: ringFrame.midY)
        let radius = ringFrame.width / 2
        ringLayer.path = UIBezierPath(arcCenter: center,
                                      radius: radius,
                                      startAngle: -.pi / 2,
                                      endAngle: 1.5 * .pi,
                                      clockwise: true).cgPath
    }

    // MARK: Configure (Unchanged)
    func configure(with date: Date,
                   isSelected: Bool,
                   progress: Double?,
                   animate: Bool = true)
    {
        let eFmt = DateFormatter(); eFmt.dateFormat = "EEEEE"
        let dFmt = DateFormatter(); dFmt.dateFormat = "d"
        dayOfWeekLabel.text = eFmt.string(from: date).uppercased()
        dayNumberLabel.text = dFmt.string(from: date)

        let isToday = Calendar.current.isDateInToday(date)

        if isSelected {
            let dayNumberLabelColor = effectManager.isLightRowTextColor ? Color.black : Color.white
            dayNumberLabel.textColor = UIColor(dayNumberLabelColor)
            dayOfWeekLabel.textColor = isToday ? .systemRed : UIColor(effectManager.currentGlobalAccentColor)
        } else {
            if isToday {
                dayOfWeekLabel.textColor = .systemRed
                dayNumberLabel.textColor = .systemRed
            } else {
                dayOfWeekLabel.textColor = UIColor(effectManager.currentGlobalAccentColor).withAlphaComponent(0.8)
                dayNumberLabel.textColor = UIColor(effectManager.currentGlobalAccentColor)
            }
        }
        dayNumberLabel.backgroundColor = .clear

        if let p = progress {
            let clamped = CGFloat(min(max(p, 0), 1))
            let ringColor: UIColor = clamped < 1 ? .systemRed : .systemGreen
            if ringLayer.strokeColor != ringColor.cgColor {
                ringLayer.strokeColor = ringColor.cgColor
            }
            let changed = (previousProgress ?? -1) != clamped
            previousProgress = clamped
            CATransaction.begin()
            CATransaction.setDisableActions(!isSelected)
            ringLayer.strokeEnd = clamped
            ringLayer.isHidden  = false
            if isSelected && changed && animate {
                let anim = CABasicAnimation(keyPath: "strokeEnd")
                anim.fromValue      = 0
                anim.toValue        = clamped
                anim.duration       = 0.35
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ringLayer.add(anim, forKey: "progress")
            } else {
                ringLayer.removeAllAnimations()
            }
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ringLayer.isHidden = true
            CATransaction.commit()
            previousProgress = nil
        }
    }

    // MARK: Reuse (Unchanged)
    override func prepareForReuse() {
        super.prepareForReuse()
        ringLayer.removeAllAnimations()
        previousProgress = nil
    }
}
