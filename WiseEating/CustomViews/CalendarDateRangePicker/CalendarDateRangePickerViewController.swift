import UIKit
import SwiftUI
import Combine

// =====================================================================
// MARK: - ViewController с календар (UICollectionView)
// =====================================================================
public class CalendarDateRangePickerViewController: UIViewController {

    // ... (всички пропъртита остават същите) ...
    @ObservedObject private var effectManager = EffectManager.shared
    private var cancellables = Set<AnyCancellable>()

    // == UI ==
    private var collectionView: UICollectionView!
    private var monthYearPickerView = MonthYearPickerView()
    
    // Navigation Bar: надпис + стрелка
    private var monthLabel = UILabel()
    private var arrowImageView = UIImageView()
    private var arrowIsDown = false

    // == Параметри/настройки ==
    public var delegate: CalendarDateRangePickerViewControllerDelegate?

    public var currentMonth: Date = Date()
    public var minimumDate: Date?
    public var maximumDate: Date?
    public var selectedStartDate: Date?
    public var selectedEndDate: Date?
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (3/3) +++
    /// Сет от дати, които трябва да имат индикатор.
    public var datesWithEvents: Set<Date>?
    // +++ КРАЙ НА ПРОМЯНАТА (3/3) +++

    private var selectedColor = UIColor.systemBlue

    // Layout за UICollectionView
    private let itemsPerRow = 7
    private let itemHeight: CGFloat = 40
    
    private let collectionViewInsets = UIEdgeInsets.zero

    private var isPickerVisible = false


    // MARK: - viewDidLoad
    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        
        view.layer.cornerRadius = 12
        view.layer.masksToBounds = true

        // --- НАЧАЛО НА ПРОМЯНА 1: Използваме нашия нов layout ---
        let layout = FullWidthFlowLayout() // ПРОМЯНА ТУК
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        // --- КРАЙ НА ПРОМЯНА 1 ---

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        
        // ... (останалата част от viewDidLoad остава същата) ...
        collectionView.register(
            CalendarDateRangePickerCell.self,
            forCellWithReuseIdentifier: "CalendarDateRangePickerCell"
        )

        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        monthYearPickerView.translatesAutoresizingMaskIntoConstraints = false
        monthYearPickerView.isHidden = true
        view.addSubview(monthYearPickerView)
        
        monthYearPickerView.onDateChanged = { [weak self] (newMonth, newYear) in
            guard let self = self else { return }
            var comps = DateComponents()
            comps.day = 1
            comps.month = newMonth
            comps.year = newYear
            if let newDate = Calendar.current.date(from: comps) {
                self.currentMonth = newDate
                self.monthLabel.text = self.getMonthLabel(date: newDate)
                self.monthLabel.sizeToFit()
                self.collectionView.reloadData()
            }
        }

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            monthYearPickerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            monthYearPickerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            monthYearPickerView.widthAnchor.constraint(equalToConstant: 300),
            monthYearPickerView.heightAnchor.constraint(equalToConstant: 200),
        ])

        let today = Date()
        if minimumDate == nil {
            minimumDate = Calendar.current.date(byAdding: .year, value: -5, to: today)
        }
        if maximumDate == nil {
            maximumDate = Calendar.current.date(byAdding: .year, value: 3, to: today)
        }

        if let start = selectedStartDate {
            currentMonth = makeFirstDayOfMonth(from: start)
        } else {
            currentMonth = makeFirstDayOfMonth(from: today)
        }

        monthLabel.text = getMonthLabel(date: currentMonth)
        monthLabel.font = UIFont.boldSystemFont(ofSize: 17)
        monthLabel.sizeToFit()

        arrowImageView.image = UIImage(systemName: "chevron.right")
        arrowImageView.contentMode = .scaleAspectFit

        let leftStack = UIStackView(arrangedSubviews: [monthLabel, arrowImageView])
        leftStack.axis = .horizontal
        leftStack.spacing = 4
        leftStack.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        leftStack.isLayoutMarginsRelativeArrangement = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(monthLabelTapped))
        leftStack.isUserInteractionEnabled = true
        leftStack.addGestureRecognizer(tapGesture)

        let labelItem = UIBarButtonItem(customView: leftStack)
        navigationItem.leftBarButtonItem = labelItem

        let prevMonthButton = UIButton(type: .system)
        prevMonthButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        prevMonthButton.addTarget(self, action: #selector(didTapPrevMonth), for: .touchUpInside)

        let nextMonthButton = UIButton(type: .system)
        nextMonthButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        nextMonthButton.addTarget(self, action: #selector(didTapNextMonth), for: .touchUpInside)

        let rightStack = UIStackView(arrangedSubviews: [prevMonthButton, nextMonthButton])
        rightStack.axis = .horizontal
        rightStack.spacing = 16
        rightStack.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        rightStack.isLayoutMarginsRelativeArrangement = true

        let rightBarButtonItem = UIBarButtonItem(customView: rightStack)
        navigationItem.rightBarButtonItem = rightBarButtonItem

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        collectionView.addGestureRecognizer(panGesture)
        
        updateThemeColors()
        effectManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateThemeColors() }
            .store(in: &cancellables)
    }

    // ... (всички други методи като updateThemeColors, viewWillAppear, monthLabelTapped и т.н. остават непроменени) ...
    private func updateThemeColors() {
        let accentUIColor = UIColor(effectManager.currentGlobalAccentColor)
        
        self.selectedColor = accentUIColor
        
        monthLabel.textColor = accentUIColor
        arrowImageView.tintColor = accentUIColor
        monthYearPickerView.textColor = accentUIColor
        
        if let rightStack = navigationItem.rightBarButtonItem?.customView as? UIStackView {
            rightStack.arrangedSubviews.forEach { ($0 as? UIButton)?.tintColor = accentUIColor }
        }
        
        collectionView.reloadData()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collectionView.reloadData()
    }

    @objc func monthLabelTapped() {
        arrowIsDown.toggle()
        let rotationAngle: CGFloat = arrowIsDown ? .pi / 2 : 0

        UIView.animate(withDuration: 0.25) {
            self.arrowImageView.transform = CGAffineTransform(rotationAngle: rotationAngle)
            self.monthLabel.textColor =  UIColor(self.effectManager.currentGlobalAccentColor)
        }

        isPickerVisible.toggle()

        if isPickerVisible {
            monthYearPickerView.alpha = 0
            monthYearPickerView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            monthYearPickerView.isHidden = false
            self.collectionView.isHidden = true
            UIView.animate(withDuration: 0.25,
                           animations: {
                self.monthYearPickerView.alpha = 1
                self.monthYearPickerView.transform = .identity
            }, completion: { _ in
                let comps = Calendar.current.dateComponents([.month, .year], from: self.currentMonth)
                let curMonth = comps.month ?? 1
                let curYear = comps.year ?? 2025
                self.monthYearPickerView.select(month: curMonth, year: curYear)
            })
        } else {
            UIView.animate(withDuration: 0.25,
                           animations: {
                self.monthYearPickerView.alpha = 0
                self.monthYearPickerView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            }, completion: { _ in
                self.monthYearPickerView.isHidden = true
                self.collectionView.isHidden = false
            })
        }
    }

    @objc func didTapPrevMonth() {
        if let newMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newMonth
            monthLabel.text = getMonthLabel(date: currentMonth)
            monthLabel.sizeToFit()
            collectionView.reloadData()
        }
    }

    @objc func didTapNextMonth() {
        if let newMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newMonth
            monthLabel.text = getMonthLabel(date: currentMonth)
            monthLabel.sizeToFit()
            collectionView.reloadData()
        }
    }
}

// =====================================================================
// MARK: - UICollectionViewDataSource, UICollectionViewDelegateFlowLayout
// =====================================================================
extension CalendarDateRangePickerViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    public func collectionView(_ collectionView: UICollectionView,
                                  numberOfItemsInSection section: Int) -> Int {
           let weekdayRowItems = 7
           let firstWeekday = GlobalState.firstWeekday
           let weekdayOfFirst = getWeekday(date: currentMonth)
           let blankItems = (weekdayOfFirst - firstWeekday + 7) % 7
           let daysInMonth = getNumberOfDaysInMonth(date: currentMonth)
           return weekdayRowItems + blankItems + daysInMonth
       }

    public func collectionView(_ collectionView: UICollectionView,
                                     cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
           let cell = collectionView.dequeueReusableCell(
               withReuseIdentifier: "CalendarDateRangePickerCell",
               for: indexPath
           ) as! CalendarDateRangePickerCell

           let accentUIColor = UIColor(effectManager.currentGlobalAccentColor)
           cell.accentColor = accentUIColor
           cell.secondaryAccentColor = accentUIColor.withAlphaComponent(0.6)
           cell.selectedTextColor = UIColor(effectManager.isLightRowTextColor ? .black : .white)
           
           // Поставяме цвета по подразбиране. Ще го променим на червен, ако е нужно.
           cell.selectedColor = self.selectedColor

           cell.reset()

           let firstWeekday = GlobalState.firstWeekday
           let weekdayOfFirst = getWeekday(date: currentMonth)
           let blankItems = (weekdayOfFirst - firstWeekday + 7) % 7

           if indexPath.item < 7 {
               let weekdayIndex = ((firstWeekday - 1 + indexPath.item) % 7) + 1
               cell.label.text = getWeekdayLabel(weekday: weekdayIndex)
               cell.label.textColor = cell.secondaryAccentColor
               return cell
           }

           if indexPath.item < 7 + blankItems {
               cell.label.text = ""
               return cell
           }

           let dayOfMonth = indexPath.item - (7 + blankItems) + 1
           let date = getDate(dayOfMonth: dayOfMonth, baseMonth: currentMonth)
           cell.date = date
           cell.label.text = "\(dayOfMonth)"
           
           if let eventDates = self.datesWithEvents, eventDates.contains(where: { self.areSameDay(dateA: $0, dateB: date) }) {
               cell.addEventIndicator()
           }

           let isToday = areSameDay(dateA: date, dateB: Date())

           // --- НАЧАЛО НА ПРОМЯНА: Логика за цвета на селекцията ---
           
           if let start = selectedStartDate {
               // Определяме дали текущата клетка е избрана
               let isSelectedStart = areSameDay(dateA: date, dateB: start)
               var isSelectedEnd = false
               var isBetween = false
               
               if let end = selectedEndDate {
                   isSelectedEnd = areSameDay(dateA: date, dateB: end)
                   // Клетката е "между" само ако не е нито начална, нито крайна
                   if !isSelectedStart && !isSelectedEnd {
                       isBetween = isBefore(dateA: start, dateB: date) && isBefore(dateA: date, dateB: end)
                   }
               }
               
               // 1. Рисуваме кръгчетата (за начална, крайна или единична дата)
               let isEndpointOrSingleSelection = isSelectedStart || isSelectedEnd || (isSelectedStart && selectedEndDate == nil)
               
               if isEndpointOrSingleSelection {
                   // АКО клетката е днешната дата, правим кръга червен
                   if isToday {
                       cell.selectedColor = .systemRed
                   }
                   cell.addCircle()
               }
               
               // 2. Рисуваме линиите, ако имаме избран период
               if let end = selectedEndDate, !areSameDay(dateA: start, dateB: end) {
                   if isSelectedStart {
                       cell.addLine(from: cell.bounds.width / 2, to: cell.bounds.width)
                   } else if isSelectedEnd {
                       cell.addLine(from: 0, to: cell.bounds.width / 2)
                   } else if isBetween {
                       cell.addLine(from: 0, to: cell.bounds.width)
                   }
               }
           }
           
           // --- КРАЙ НА ПРОМЯНАТА ---
           
           // Ако клетката е днешна, но НЕ Е избрана (няма кръг), правим текста червен
           if isToday && cell.circleView == nil {
               cell.label.textColor = .systemRed
           }

           return cell
       }
    
    // ... (didSelectItemAt и sizeForItemAt остават същите) ...
    public func collectionView(_ collectionView: UICollectionView,
                               didSelectItemAt indexPath: IndexPath) {
        
        guard let cell = collectionView.cellForItem(at: indexPath) as? CalendarDateRangePickerCell,
              let cellDate = cell.date else {
            return
        }

        if selectedStartDate == nil {
            selectedStartDate = cellDate
        }
        else if selectedEndDate == nil {
            if let start = selectedStartDate, isBefore(dateA: start, dateB: cellDate) {
                selectedEndDate = cellDate
            } else {
                selectedStartDate = cellDate
            }
            if let s = selectedStartDate, let e = selectedEndDate {
                delegate?.didPickDateRange(startDate: s, endDate: e)
            }
        }
        else {
            selectedStartDate = cellDate
            selectedEndDate = nil
        }

        collectionView.reloadData()
    }

    public func collectionView(_ collectionView: UICollectionView,
                               layout collectionViewLayout: UICollectionViewLayout,
                               sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        let w = collectionView.bounds.width
        let itemWidth = w / CGFloat(itemsPerRow)
        return CGSize(width: itemWidth, height: itemHeight)
    }
}

extension CalendarDateRangePickerViewController {
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: collectionView)

        guard let indexPath = collectionView.indexPathForItem(at: location),
              let cell = collectionView.cellForItem(at: indexPath) as? CalendarDateRangePickerCell,
              let cellDate = cell.date else {
            return
        }
        
        if indexPath.item < 7 {
            return
        }
        
        switch gesture.state {
        case .began:
            selectedStartDate = cellDate
            selectedEndDate = nil
            collectionView.reloadData()
            
        case .changed:
            if let start = selectedStartDate {
                if isBefore(dateA: start, dateB: cellDate) {
                    selectedEndDate = cellDate
                } else {
                    selectedStartDate = cellDate
                }
                collectionView.reloadData()
            }
            
        case .ended, .cancelled, .failed:
            if let s = selectedStartDate, let e = selectedEndDate {
                delegate?.didPickDateRange(startDate: s, endDate: e)
            }
            
        default:
            break
        }
    }
}

// =====================================================================
// MARK: - Помощни функции
// =====================================================================
extension CalendarDateRangePickerViewController {

    func makeFirstDayOfMonth(from date: Date) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month], from: date)
        comps.day = 1
        return Calendar.current.date(from: comps)!
    }

    func getMonthLabel(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    func getWeekdayLabel(weekday: Int) -> String {
        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.weekday = weekday

        guard let date = Calendar.current.nextDate(
            after: Date(),
            matching: comps,
            matchingPolicy: .strict
        ) else {
            return "???"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    func getWeekday(date: Date) -> Int {
        return Calendar.current.component(.weekday, from: date)
    }

    func getNumberOfDaysInMonth(date: Date) -> Int {
        return Calendar.current.range(of: .day, in: .month, for: date)!.count
    }

    func getDate(dayOfMonth: Int, baseMonth: Date) -> Date {
        var comps = Calendar.current.dateComponents([.month, .year], from: baseMonth)
        comps.day = dayOfMonth
        return Calendar.current.date(from: comps)!
    }

    func areSameDay(dateA: Date, dateB: Date) -> Bool {
        return Calendar.current.compare(dateA, to: dateB, toGranularity: .day) == .orderedSame
    }

    func isBefore(dateA: Date, dateB: Date) -> Bool {
        return Calendar.current.compare(dateA, to: dateB, toGranularity: .day) == .orderedAscending
    }
}
