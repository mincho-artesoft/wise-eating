import UIKit
import SwiftUI

/// Хоризонтален (безкраен) календар по седмици.
public final class WeekCarouselView: UIView,
                                     UICollectionViewDataSource,
                                     UICollectionViewDelegateFlowLayout,
                                     UIScrollViewDelegate {
    
    // MARK: - Public API
    public var onDaySelected:        ((Date) -> Void)?
    public var goalProgressProvider: ((Date) -> Double?)?
    
    public var selectedDate: Date {
        get {
            guard !dates.isEmpty, dates.indices.contains(selectedIndex) else {
                return Date()
            }
            return dates[selectedIndex]
        }
        set {
            if let i = dates.firstIndex(where: { isSameDay($0, newValue) }) {
                self.selectedIndex = i
            } else {
                isPerformingDataReload = true
                loadWeeksAround(newValue, range: 2)
                if let i = dates.firstIndex(where: { isSameDay($0, newValue) }) {
                    self.selectedIndex = i
                }
                collectionView.reloadData()
                isPerformingDataReload = false
                DispatchQueue.main.async {
                    self.scrollToSelected(animated: false)
                    self.updatePillPosition(animated: false)
                }
            }
        }
    }
    
    // MARK: - Private state
    private var dates: [Date] = []
    private var isPerformingDataReload = false

    private var selectionPillView = UIView()
    private var pillHostController: UIHostingController<SelectedDayBackgroundView>?

    private var selectedIndex = 0 {
        didSet {
            guard !isPerformingDataReload, oldValue != selectedIndex else { return }

            updatePillPosition(animated: true)

            let oldIP = IndexPath(item: oldValue, section: 0)
            let newIP = IndexPath(item: selectedIndex, section: 0)
            
            collectionView.performBatchUpdates({
                if collectionView.numberOfItems(inSection: 0) > oldIP.item {
                     collectionView.reloadItems(at: [oldIP])
                }
                if collectionView.numberOfItems(inSection: 0) > newIP.item {
                     collectionView.reloadItems(at: [newIP])
                }
            }, completion: nil)

            scrollToSelected(animated: true)
        }
    }
    
    private let chunkWeeks = 2
    
    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero,
                                  collectionViewLayout: WeekFlowLayout())
        cv.isPagingEnabled = true
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.dataSource = self
        cv.delegate   = self
        cv.register(DayCell.self, forCellWithReuseIdentifier: "DayCell")
        return cv
    }()
    
    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = GlobalState.firstWeekday
        return c
    }
    
    // MARK: - Init
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    private func setup() {
        addSubview(collectionView)
        
        let host = UIHostingController(rootView: SelectedDayBackgroundView(isToday: false))
        host.view.backgroundColor = .clear
        self.pillHostController = host
        self.selectionPillView = host.view

        collectionView.addSubview(selectionPillView)
        selectionPillView.layer.zPosition = -1

        loadWeeksAround(Date(), range: 2)
        if let i = dates.firstIndex(where: { isSameDay($0, Date()) }) {
            selectedIndex = i
        }
    }
    
    // MARK: - Layout
    public override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = bounds
        collectionView.collectionViewLayout.invalidateLayout()
        scrollToSelected(animated: false)
        updatePillPosition(animated: false)
    }
    
    // MARK: - Data buffering (Unchanged)
    private func loadWeeksAround(_ center: Date, range r: Int) {
        let start = align(center)
        var tmp: [Date] = []
        for w in -r...r {
            if let week = cal.date(byAdding: .day, value: w * 7, to: start) {
                for i in 0..<7 {
                    if let d = cal.date(byAdding: .day, value: i, to: week) {
                        tmp.append(d)
                    }
                }
            }
        }
        if dates.isEmpty {
            dates = tmp.sorted()
        } else {
            let set = Set(dates)
            dates += tmp.filter { !set.contains($0) }
            dates.sort()
        }
    }
    private func prepend(_ n: Int) {
        guard let first = dates.first else { return }
        let start = align(first)
        var add: [Date] = []
        for w in 1...n {
            if let week = cal.date(byAdding: .day, value: -w * 7, to: start) {
                for i in 0..<7 {
                    if let d = cal.date(byAdding: .day, value: i, to: week) {
                        add.append(d)
                    }
                }
            }
        }
        dates.insert(contentsOf: add.sorted(), at: 0)
    }
    private func append(_ n: Int) {
        guard let last = dates.last else { return }
        let start = align(last)
        var add: [Date] = []
        for w in 1...n {
            if let week = cal.date(byAdding: .day, value: w * 7, to: start) {
                for i in 0..<7 {
                    if let d = cal.date(byAdding: .day, value: i, to: week) {
                        add.append(d)
                    }
                }
            }
        }
        dates += add.sorted()
    }
    
    // MARK: - UICollectionViewDataSource (Unchanged)
    public func collectionView(_ cv: UICollectionView,
                               numberOfItemsInSection _: Int) -> Int {
        dates.count
    }
    
    public func collectionView(_ cv: UICollectionView,
                               cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "DayCell",
                                          for: ip) as! DayCell
        let date = dates[ip.item]
        let prog = goalProgressProvider?(date)
        cell.configure(with: date,
                       isSelected: ip.item == selectedIndex,
                       progress: prog)
        return cell
    }
    
    // MARK: - UICollectionViewDelegateFlowLayout (Unchanged)
    public func collectionView(_ cv: UICollectionView,
                               layout _: UICollectionViewLayout,
                               sizeForItemAt _: IndexPath) -> CGSize {
        CGSize(width: bounds.width / 7, height: bounds.height)
    }
    
    public func collectionView(_ cv: UICollectionView,
                               didSelectItemAt ip: IndexPath) {
        selectedIndex = ip.item
        onDaySelected?(dates[ip.item])
    }
    
    // MARK: - UIScrollViewDelegate
    public func scrollViewDidEndDecelerating(_ sv: UIScrollView) {
        let page = Int(round(sv.contentOffset.x / bounds.width))
        let start = page * 7
        let pos   = selectedIndex % 7
        var idx   = start + pos
        
        if page < 2 {
            let before = dates.count
            prepend(chunkWeeks)
            let diff = dates.count - before
            idx += diff
            collectionView.reloadData()
            sv.contentOffset.x += CGFloat(diff) * (bounds.width / 7)
        }
        let totalPages = Int(ceil(Double(dates.count) / 7))
        if page > totalPages - 3 {
            append(chunkWeeks)
            collectionView.reloadData()
        }
        
        idx = max(0, min(idx, dates.count - 1))
        selectedIndex = idx
        onDaySelected?(dates[idx])
        
        updatePillPosition(animated: false)
    }
    
    // MARK: - Helpers
    private func scrollToSelected(animated: Bool) {
        guard selectedIndex < dates.count, selectedIndex >= 0 else { return }
        
        let pageIndex = floor(Double(selectedIndex) / 7.0)
        let xOffset = CGFloat(pageIndex) * bounds.width
        
        if abs(collectionView.contentOffset.x - xOffset) > 1 {
            collectionView.setContentOffset(CGPoint(x: xOffset, y: 0), animated: animated)
        }
    }
    private func align(_ d: Date) -> Date {
        let wd = cal.component(.weekday, from: d)
        let diff = cal.firstWeekday - wd
        let ref = cal.date(byAdding: .day, value: diff, to: d) ?? d
        return cal.startOfDay(for: ref)
    }
    private func isSameDay(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, inSameDayAs: b)
    }
    
    private func updatePillPosition(animated: Bool) {
        guard selectedIndex < dates.count,
              let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: selectedIndex, section: 0))
        else {
            selectionPillView.frame = .zero
            return
        }

        let isToday = isSameDay(dates[selectedIndex], Date())
        self.pillHostController?.rootView.isToday = isToday
        
        // --- START OF CORRECTION ---
        let side: CGFloat = 35
        let spacing: CGFloat = 10.0 
        // --- END OF CORRECTION ---

        let dayOfWeekLabelHeight = UIFont.systemFont(ofSize: 12).lineHeight

        let totalContentHeight = dayOfWeekLabelHeight + spacing + side
        var startY = (self.bounds.height - totalContentHeight) / 2
        startY += 5.0
        
        let pillY = startY + dayOfWeekLabelHeight + spacing

        let cellWidth = self.bounds.width / 7
        let pillX = attributes.frame.origin.x + (cellWidth - side) / 2
        
        let pillFrame = CGRect(
            x: pillX,
            y: pillY,
            width: side,
            height: side
        )

        if animated {
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.selectionPillView.frame = pillFrame
            }
        } else {
            self.selectionPillView.frame = pillFrame
        }
    }
    
    // MARK: - External API
    public func reload() {
        collectionView.reloadData()
    }
    
    func reloadVisibleCellsWithoutAnimation() {
          guard let provider = goalProgressProvider else { return }

          CATransaction.begin()
          CATransaction.setDisableActions(true)

          for case let cell as DayCell in collectionView.visibleCells {
              if let ip = collectionView.indexPath(for: cell) {
                  let date     = dates[ip.item]
                  let progress = provider(date)
                  cell.configure(with: date,
                                 isSelected: ip.item == selectedIndex,
                                 progress: progress,
                                 animate: false)
              }
          }
          CATransaction.commit()
    }
}
