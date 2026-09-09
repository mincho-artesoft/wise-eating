import UIKit

// =====================================================================
// MARK: - MonthYearPickerView (за избор на месец/година)
// =====================================================================
public class MonthYearPickerView: UIPickerView, UIPickerViewDataSource, UIPickerViewDelegate {

    private let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    public var years: [Int] = []
    private let monthRowsMultiplier = 10_000
    private let yearRowsMultiplier = 1_000

    private(set) var selectedMonthIndex = 0
    private(set) var selectedYearIndex = 0

    public var onDateChanged: ((Int, Int) -> Void)?
    
    // --- ПРОМЯНА: Добавяме свойство за цвят на текста ---
    public var textColor: UIColor = .label {
        didSet {
            reloadAllComponents()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        self.dataSource = self
        self.delegate = self
        
        self.years = Array(1970...3000)
    }

    public func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 2
    }

    public func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        if component == 0 {
            return months.count * monthRowsMultiplier
        } else {
            return years.count * yearRowsMultiplier
        }
    }

    // --- ПРОМЯНА: Използваме viewForRow вместо titleForRow, за да можем да зададем цвят ---
    public func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        var label: UILabel
        if let existingLabel = view as? UILabel {
            label = existingLabel
        } else {
            label = UILabel()
        }
        
        label.font = .systemFont(ofSize: 20, weight: .regular)
        label.textColor = self.textColor
        label.textAlignment = .center
        
        if component == 0 {
            label.text = months[row % months.count]
        } else {
            label.text = "\(years[row % years.count])"
        }
        
        return label
    }

    public func pickerView(_ pickerView: UIPickerView,
                           didSelectRow row: Int,
                           inComponent component: Int) {
        if component == 0 {
            selectedMonthIndex = row % months.count
        } else {
            selectedYearIndex = row % years.count
        }
        let selectedMonth = selectedMonthIndex + 1
        let selectedYear = years[selectedYearIndex]
        onDateChanged?(selectedMonth, selectedYear)
    }

    public func select(month: Int, year: Int, animated: Bool = false) {
        guard let yearPos = years.firstIndex(of: year) else { return }

        let middleMonths = months.count * (monthRowsMultiplier / 2)
        let middleYears = years.count * (yearRowsMultiplier / 2)

        let monthRow = middleMonths + (month - 1)
        let yearRow = middleYears + yearPos

        self.selectRow(monthRow, inComponent: 0, animated: animated)
        self.selectRow(yearRow, inComponent: 1, animated: animated)

        selectedMonthIndex = month - 1
        selectedYearIndex = yearPos
    }
}
