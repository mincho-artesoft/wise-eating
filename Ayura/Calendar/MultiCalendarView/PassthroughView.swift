import UIKit
import SwiftUI
import EventKit
import EventKitUI

// Нов клас, който позволява докосванията да "минават" през него към децата му,
// дори ако са извън собствените му граници.
class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews.reversed() {
            let subPoint = subview.convert(point, from: self)
            if let result = subview.hitTest(subPoint, with: event) {
                return result
            }
        }
        return super.hitTest(point, with: event)
    }
}
