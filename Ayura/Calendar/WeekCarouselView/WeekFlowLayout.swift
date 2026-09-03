import UIKit

/// Прост хоризонтален flow-layout без spacing между страниците.
final class WeekFlowLayout: UICollectionViewFlowLayout {
    override func prepare() {
        super.prepare()
        scrollDirection      = .horizontal
        minimumLineSpacing   = 0
        minimumInteritemSpacing = 0
    }
}
