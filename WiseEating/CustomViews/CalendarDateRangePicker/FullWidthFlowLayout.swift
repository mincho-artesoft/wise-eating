import UIKit

/// UICollectionViewFlowLayout, който гарантира, че клетките на един ред
/// запълват цялата ширина без процепи, причинени от грешки при закръгляване.
class FullWidthFlowLayout: UICollectionViewFlowLayout {

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        // 1. Взимаме стандартните атрибути, изчислени от супер класа
        guard let attributes = super.layoutAttributesForElements(in: rect) else {
            return nil
        }

        // 2. Създаваме копие, което можем да променяме
        guard let copiedAttributes = NSArray(array: attributes, copyItems: true) as? [UICollectionViewLayoutAttributes] else {
            return nil
        }

        // 3. Групираме атрибутите по ред (всички с еднаква y-координата са на един ред)
        let attributesByRow = Dictionary(grouping: copiedAttributes, by: { $0.frame.origin.y })

        // 4. Итерираме през всеки ред и коригираме рамките на клетките
        for (_, rowAttributes) in attributesByRow {
            // Пропускаме редове с по-малко от 2 елемента, тъй като там няма процепи
            guard rowAttributes.count > 1 else { continue }
            
            // Сортираме клетките отляво надясно
            let sortedRowAttributes = rowAttributes.sorted { $0.frame.origin.x < $1.frame.origin.x }

            // Изчисляваме общата ширина, която заемат клетките според FlowLayout
            let totalWidthOfCells = sortedRowAttributes.reduce(0) { $0 + $1.frame.width }
            
            // Взимаме ширината на самия CollectionView
            guard let collectionViewWidth = collectionView?.bounds.width else { continue }

            // Изчисляваме оставащото празно пространство (обикновено 1-2 пиксела)
            let remainingSpace = collectionViewWidth - sectionInset.left - sectionInset.right - totalWidthOfCells - (minimumInteritemSpacing * CGFloat(sortedRowAttributes.count - 1))
            
            // Разпределяме остатъка равномерно между клетките
            let extraWidthPerCell = remainingSpace / CGFloat(sortedRowAttributes.count)

            var currentX: CGFloat = sectionInset.left
            for attribute in sortedRowAttributes {
                var newFrame = attribute.frame
                newFrame.origin.x = currentX
                newFrame.size.width += extraWidthPerCell // Добавяме част от остатъка
                attribute.frame = newFrame
                currentX += newFrame.width + minimumInteritemSpacing
            }
        }

        return copiedAttributes
    }
}
