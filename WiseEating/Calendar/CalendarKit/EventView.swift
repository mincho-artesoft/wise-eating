import UIKit
import SwiftUI
import EventKit
import SwiftData

// MARK: – EventView
open class EventView: UIView {
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: – Public API
    public var descriptor: EventDescriptor?
    public var color = SystemColors.label
    public var profile: Profile?

    public var modelContext: ModelContext? {
        didSet {
            if let d = descriptor { updateWithDescriptor(event: d) }
        }
    }
    
    private lazy var mealTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 1
        return l
    }()

    // MARK: – Private
    private var viewModel: CalendarViewModel = .shared
    
    private var mealHost: UIHostingController<MealRowsView>?
    private var shoppingListHost: UIHostingController<ShoppingListRowsView>?
    // +++ НОВО: Добавляем хост для тренировок +++
    private var trainingHost: UIHostingController<TrainingRowsView>?
    
    private var pageIndicatorHost: UIHostingController<PageIndicatorView>?
    private var pageState = PageState()
    
    private var currentShoppingPayload: ShoppingListPayload?

    private lazy var contentContainerView: UIView = {
        let view = UIView()
        view.clipsToBounds = true
        view.backgroundColor = .clear
        return view
    }()
    
    private var backgroundHost: UIHostingController<GlassBackgroundView>?
    
    public private(set) lazy var textView: UITextView = {
        let v = UITextView()
        v.isUserInteractionEnabled = false
        v.backgroundColor          = .clear
        v.isScrollEnabled          = false
        v.clipsToBounds            = true
        return v
    }()

    public private(set) lazy var eventResizeHandles = [
        EventResizeHandleView(), EventResizeHandleView()
    ]

    // MARK: – Init & Configure
    override public init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configure()
    }

    private func configure() {
        clipsToBounds = false
        color = tintColor
        addSubview(contentContainerView)
        
        let initialRadius: CGFloat = 15
        let backgroundView = GlassBackgroundView(cornerRadius: initialRadius)
        let host = UIHostingController(rootView: backgroundView)
        host.view.backgroundColor = .clear
        contentContainerView.insertSubview(host.view, at: 0)
        self.backgroundHost = host
        
        contentContainerView.addSubview(textView)
        contentContainerView.addSubview(mealTitleLabel)
        
        for (i, h) in eventResizeHandles.enumerated() {
            h.tag = i
            addSubview(h)
        }
    }

    // MARK: – Main update
    public func updateWithDescriptor(event: EventDescriptor) {
        descriptor = event
        guard let wrap = event as? EKMultiDayWrapper else { return }

        if let shoppingPayload = shoppingListPayload(from: wrap.realEvent) {
            configureForShoppingList(payload: shoppingPayload, wrapper: wrap)
        } else if isTrainingEvent(wrap.realEvent) {
            configureForTraining(wrapper: wrap)
        } else {
            let ctx = modelContext ?? GlobalState.modelContext
            var rows: [(FoodItem, Double)] = []
            if let ctx {
                let meal = Meal(event: wrap.realEvent)
                rows = meal.foods(using: ctx).sorted { $0.key.name < $1.key.name }
            } else {
                rows = legacyRows(from: wrap.realEvent)
            }
            configureForMeal(with: rows, wrapper: wrap)
        }
        
        self.backgroundColor = .clear
        contentContainerView.backgroundColor = .clear
        
        let cornerRadius: CGFloat = 20.0
        contentContainerView.layer.cornerRadius = cornerRadius
        backgroundHost?.rootView = GlassBackgroundView(cornerRadius: cornerRadius)
        
        color = event.color
        eventResizeHandles.forEach {
            $0.borderColor = event.color
            $0.isHidden = event.editedEvent == nil
        }

        setNeedsDisplay()
        setNeedsLayout()
    }

    // --- НАЧАЛО НА КОРЕКЦИЯТА ---
    private func isTrainingEvent(_ event: EKEvent) -> Bool {
        guard let profile = self.profile else {
            return false
        }
        let eventTitle = event.title ?? ""
    
        // Правило 1: Проверяваме payload-а ПЪРВО. Ако започва с маркера, ВИНАГИ е тренировка.
        if let notes = event.notes, let decoded = OptimizedInvisibleCoder.decode(from: notes) {
            if decoded.starts(with: "#TRAINING#") {
                return true
            }
        }
        
        // Правило 2: Ако няма маркер, проверяваме по име. Ако съвпада с шаблон за тренировка, е тренировка.
        if profile.trainings.contains(where: { $0.name == eventTitle }) {
            return true
        }
    
        // Правило 3: Ако името съвпада с шаблон за хранене, ВИНАГИ НЕ е тренировка.
        if profile.meals.contains(where: { $0.name == eventTitle }) {
            return false
        }
        
        // Всичко останало не е тренировка.
        return false
    }
    // --- КРАЙ НА КОРЕКЦИЯТА ---

    // MARK: – Layout
    override open func layoutSubviews() {
        super.layoutSubviews()
        
        contentContainerView.frame = self.bounds
        backgroundHost?.view.frame = contentContainerView.bounds

        let leftPad:  CGFloat  = (descriptor?.isAllDay == true) ? -3 : 8
        let extraRight: CGFloat = 6
        let extraDown:  CGFloat = 6
        let titleHeight: CGFloat = 18

        mealTitleLabel.frame = CGRect(
            x: bounds.minX + leftPad + extraRight,
            y: bounds.minY + extraDown,
            width: bounds.width - (leftPad + extraRight) * 2,
            height: titleHeight
        )

        let currentY = mealTitleLabel.frame.maxY + 4
        let availableWidth = mealTitleLabel.frame.width

        if let host = mealHost {
            host.view.frame = CGRect(
                x: mealTitleLabel.frame.minX,
                y: currentY,
                width: availableWidth,
                height: bounds.height - currentY
            )
        }
        
        if let host = shoppingListHost {
            let bottomPadding: CGFloat = 8
            let availableHeight = bounds.height - currentY - bottomPadding
            host.view.frame = CGRect(
                x: mealTitleLabel.frame.minX,
                y: currentY,
                width: availableWidth,
                height: max(0, availableHeight)
            )
        }
        
        if let host = trainingHost {
            let bottomPadding: CGFloat = 8
            let availableHeight = bounds.height - currentY - bottomPadding
            host.view.frame = CGRect(
                x: mealTitleLabel.frame.minX,
                y: currentY,
                width: availableWidth,
                height: max(0, availableHeight)
            )
        }
        
        if let indicatorHost = pageIndicatorHost {
            let indicatorHeight: CGFloat = 10
            let bottomPadding: CGFloat = 4
            let indicatorY = self.bounds.height - indicatorHeight - bottomPadding
            indicatorHost.view.frame = CGRect(
                x: mealTitleLabel.frame.minX,
                y: indicatorY,
                width: mealTitleLabel.frame.width,
                height: indicatorHeight
            )
        }

        let topPad: CGFloat = (descriptor?.isAllDay == true) ? -6 : 0
        textView.frame = CGRect(
            x: bounds.minX + leftPad,
            y: bounds.minY + topPad,
            width: bounds.width - 6,
            height: bounds.height - topPad
        )
        
        let r: Double = 40
        let yPad = -r / 2
        eventResizeHandles.first?.frame = CGRect(
            origin: CGPoint(x: bounds.width - r - layoutMargins.right, y: yPad),
            size: CGSize(width: r, height: r)
        )
        eventResizeHandles.last?.frame = CGRect(
            origin: CGPoint(x: layoutMargins.left,
                            y: bounds.height - yPad - r),
            size: CGSize(width: r, height: r)
        )
    }

    override open func draw(_ rect: CGRect) {
        super.draw(rect)
    }

    // MARK: - UI Configuration & Commit Logic
    
    private func configureForShoppingList(
        payload: ShoppingListPayload,
        wrapper w: EKMultiDayWrapper
    ) {
        self.currentShoppingPayload = payload
        
        mealHost?.view.removeFromSuperview(); mealHost = nil
        trainingHost?.view.removeFromSuperview(); trainingHost = nil
        pageIndicatorHost?.view.removeFromSuperview(); pageIndicatorHost = nil
        
        mealTitleLabel.text = w.realEvent.title
        mealTitleLabel.textColor = UIColor(effectManager.currentGlobalAccentColor)
        
        let showList = !payload.items.isEmpty && bounds.height >= 80

        mealTitleLabel.isHidden = !showList

        if showList {
            textView.removeFromSuperview()
            
            var shoppingListRootView = ShoppingListRowsView(items: payload.items)
            
            shoppingListRootView.onCommit = { [weak self] committedItems in
                Task { @MainActor in
                    await self?.commitPurchases(items: committedItems)
                }
            }
            
            if let host = shoppingListHost {
                host.rootView = shoppingListRootView
            } else {
                let host = UIHostingController(rootView: shoppingListRootView)
                host.view.backgroundColor = .clear
                contentContainerView.addSubview(host.view)
                shoppingListHost = host
            }
            return
        }

        if textView.superview == nil { contentContainerView.addSubview(textView) }
        textView.attributedText = makeFallbackStringForShoppingList(for: w, payload: payload)
        textView.isHidden = false
        shoppingListHost?.view.removeFromSuperview(); shoppingListHost = nil
    }

    @MainActor
    private func commitPurchases(items: [ShoppingListItemPayload]) async {
        guard let context = modelContext ?? GlobalState.modelContext,
              let currentPayload = currentShoppingPayload,
              let realEvent = (descriptor as? EKMultiDayWrapper)?.realEvent,
              let _ = self.profile else {
            print("Commit failed: missing context, payload, or profile.")
            return
        }
        
        let listID = currentPayload.id
        let pendingIDs = Set(items.map { $0.id })
        
        do {
            let descriptor = FetchDescriptor<ShoppingListModel>(predicate: #Predicate { $0.id == listID })
            guard let listToUpdate = try context.fetch(descriptor).first else {
                print("Commit failed: ShoppingListModel not found.")
                return
            }
            
            let initiallyBoughtIDs = Set(currentPayload.items.filter { $0.isBought }.map { $0.id })

            for i in listToUpdate.items.indices {
                if pendingIDs.contains(listToUpdate.items[i].id) {
                    listToUpdate.items[i].isBought = true
                }
            }
            
            listToUpdate.isCompleted = listToUpdate.items.allSatisfy { $0.isBought }
            
            try listToUpdate.processCompletedItems(initiallyBoughtIDs: initiallyBoughtIDs, context: context)
            
            let newPayload = ShoppingListPayload(from: listToUpdate)
            let jsonData = try JSONEncoder().encode(newPayload)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                realEvent.notes = OptimizedInvisibleCoder.encode(from: jsonString)
            }
            
            if context.hasChanges { try context.save() }
            try viewModel.eventStore.save(realEvent, span: .thisEvent, commit: true)
            
            if let wrapper = self.descriptor as? EKMultiDayWrapper {
                 configureForShoppingList(payload: newPayload, wrapper: wrapper)
                 setNeedsLayout()
                 UIView.animate(withDuration: 0.3) { self.layoutIfNeeded() }
            }
            
        } catch {
            print("Error committing purchases: \(error)")
        }
    }

    private func configureForMeal(
        with rows: [(FoodItem, Double)],
        wrapper w: EKMultiDayWrapper
    ) {
        shoppingListHost?.view.removeFromSuperview(); shoppingListHost = nil
        trainingHost?.view.removeFromSuperview(); trainingHost = nil

        mealTitleLabel.text      = w.realEvent.title
        mealTitleLabel.textColor = w.color

        let showList = !rows.isEmpty && bounds.height >= 80
        mealTitleLabel.isHidden = !showList
        
        DispatchQueue.main.async {
            self.pageState.pageIndex = 0
        }

        if showList {
            textView.removeFromSuperview()

            let mealRowsRootView = MealRowsView(rows: rows, pageState: pageState)
            
            if let host = mealHost {
                host.rootView = mealRowsRootView
            } else {
                let host = UIHostingController(rootView: mealRowsRootView)
                host.view.backgroundColor = .clear
                contentContainerView.addSubview(host.view)
                mealHost = host
            }
            
            let pageCount = rows.count > 1 ? rows.count + 1 : rows.count
            setupPageIndicator(pageCount: pageCount)
            
            return
        }

        if textView.superview == nil { contentContainerView.addSubview(textView) }
        
        if !rows.isEmpty {
            textView.attributedText = makeCompactString(
                title: w.realEvent.title,
                titleColor: w.color,
                rows: rows
            )
        } else {
            textView.attributedText = makeFallbackStringForMeal(for: w)
        }
        
        textView.isHidden = false
        mealHost?.view.removeFromSuperview(); mealHost = nil
        pageIndicatorHost?.view.removeFromSuperview(); pageIndicatorHost = nil
    }

    private func configureForTraining(wrapper w: EKMultiDayWrapper) {
        // Почистваме хостовете от другите типове съдържание
        mealHost?.view.removeFromSuperview(); mealHost = nil
        shoppingListHost?.view.removeFromSuperview(); shoppingListHost = nil
        pageIndicatorHost?.view.removeFromSuperview(); pageIndicatorHost = nil
        
        // Задаваме заглавието и цвета
        mealTitleLabel.text = w.realEvent.title
        mealTitleLabel.textColor = w.color
    
        // Взимаме упражненията от payload-а
        let training = Training(event: w.realEvent)
        let exercises = training.exercises(using: self.modelContext ?? GlobalState.modelContext!)
            .map { ($0.key, $0.value) }
            .sorted { $0.0.name < $1.0.name }
    
        // Проверяваме дали имаме упражнения и достатъчно място, за да ги покажем
        let showList = !exercises.isEmpty && bounds.height >= 80
    
        mealTitleLabel.isHidden = !showList
    
        if showList {
            // Ако има упражнения, показваме TrainingRowsView
            if textView.superview != nil {
                textView.removeFromSuperview()
            }
            
            let trainingRowsRootView = TrainingRowsView(exercises: exercises, profile: self.profile!, pageState: pageState)
    
            if let host = trainingHost {
                host.rootView = trainingRowsRootView
            } else {
                let host = UIHostingController(rootView: trainingRowsRootView)
                host.view.backgroundColor = .clear
                contentContainerView.addSubview(host.view)
                trainingHost = host
            }
            
            let pageCount = exercises.count > 1 ? exercises.count + 1 : exercises.count
            setupPageIndicator(pageCount: pageCount)
    
        } else {
            // Ако няма упражнения (новосъздадена тренировка) или няма място,
            // показваме само заглавието в textView.
            if trainingHost != nil {
                trainingHost?.view.removeFromSuperview()
                trainingHost = nil
            }
            if textView.superview == nil {
                contentContainerView.addSubview(textView)
            }
            
            // ИЗПОЛЗВАМЕ НОВИЯ FALLBACK МЕТОД
            textView.attributedText = makeFallbackStringForTraining(for: w)
            textView.isHidden = false
        }
    }

    private func setupPageIndicator(pageCount: Int) {
        guard pageCount > 1 else {
            pageIndicatorHost?.view.removeFromSuperview()
            pageIndicatorHost = nil
            return
        }

        let indicatorView = PageIndicatorView(pageCount: pageCount, pageState: pageState)
        
        if let host = pageIndicatorHost {
            host.rootView = indicatorView
        } else {
            let host = UIHostingController(rootView: indicatorView)
            host.view.backgroundColor = .clear
            contentContainerView.addSubview(host.view)
            pageIndicatorHost = host
        }
    }
    
    // MARK: – Fallback & Data Logic
    
    private func shoppingListPayload(from ev: EKEvent) -> ShoppingListPayload? {
        guard let notes = ev.notes,
              let jsonString = OptimizedInvisibleCoder.decode(from: notes),
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        do {
            let payload = try JSONDecoder().decode(ShoppingListPayload.self, from: jsonData)
            return payload
        } catch {
            return nil
        }
    }

    private func legacyRows(from ev: EKEvent) -> [(FoodItem, Double)] {
        guard let payload = mealPayload(from: ev) else { return [] }
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"(?i)^Copy of\s+"#, with: "", options: .regularExpression) }
        return payload.compactMap { raw, g in
            guard let ctx = modelContext else { return nil }
            let target = clean(raw)
            var fetch = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.name.localizedStandardContains(target) })
            fetch.fetchLimit = 8
            guard let item = try? ctx.fetch(fetch).first(where: { $0.name.compare(target, options: .caseInsensitive) == .orderedSame }) else { return nil }
            return (item, g)
        }
    }
    
    // --- НАЧАЛО НА ПРОМЯНАТА: Опростяваме makeFallbackStringForMeal ---
    private func makeFallbackStringForMeal(for w: EKMultiDayWrapper) -> NSAttributedString {
        let attr: [NSAttributedString.Key: Any] = [.font: w.font, .foregroundColor: w.color]
        // Просто връщаме заглавието, без да се опитваме да парсваме съставки.
        // `makeCompactString` се грижи за случаите със съставки в малко пространство.
        return NSAttributedString(string: w.text, attributes: attr)
    }
    // --- КРАЙ НА ПРОМЯНАТА ---
    
    private func makeFallbackStringForTraining(for w: EKMultiDayWrapper) -> NSAttributedString {
        let attr: [NSAttributedString.Key: Any] = [.font: w.font, .foregroundColor: w.color]
        return NSAttributedString(string: w.text, attributes: attr)
    }
    
    private func makeFallbackStringForShoppingList(for w: EKMultiDayWrapper, payload: ShoppingListPayload) -> NSAttributedString {
        let titleColor = UIColor(effectManager.currentGlobalAccentColor)
        let titleAttr: [NSAttributedString.Key: Any] = [.font: w.font, .foregroundColor: titleColor]
        let str = NSMutableAttributedString(string: w.text, attributes: titleAttr)
        return str
    }
    
    private func mealPayload(from ev: EKEvent) -> [(String, Double)]? {
        let inv = ev.url?.absoluteString ?? (ev.notes?.first { !$0.unicodeScalars.allSatisfy(\.isASCII) }.map { _ in ev.notes! })
        guard let invis = inv, let decoded = OptimizedInvisibleCoder.decode(from: invis) else { return nil }
        
        guard !decoded.trimmingCharacters(in: .whitespaces).starts(with: "{") else {
            return nil
        }
        
        return decoded.split(separator: "|").compactMap { p in
            let pair = p.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, let g = Double(pair[1]) else { return nil }
            return (pair[0], g)
        }
    }

    private func makeCompactString(title: String, titleColor: UIColor, rows: [(FoodItem, Double)]) -> NSAttributedString {
          let result = NSMutableAttributedString()
          result.append(NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: titleColor]))
          let foodAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor(effectManager.currentGlobalAccentColor)]
          for (item, _) in rows {
              result.append(NSAttributedString(string: "  \(item.name)", attributes: foodAttrs))
          }
          return result
      }
}

// MARK: – Ghost styles
extension EventView {

    func applyGhostStyle(cornerRadius: CGFloat = 5) {
        layer.cornerRadius = cornerRadius
        clipsToBounds      = true

        if let first = viewModel.firstLocalCalendarColor {
            color = first
            backgroundColor = first.withAlphaComponent(0.3)
        } else {
            color = .systemBlue
            backgroundColor = .systemBlue.withAlphaComponent(0.3)
        }

        textView.text      = "New Meal/Training"
        textView.font      = .systemFont(ofSize: 12, weight: .semibold)
        textView.textColor = color
        eventResizeHandles.forEach { $0.isHidden = true }
    }
    func applyGhostStyleSopingList(cornerRadius: CGFloat = 5) {
        layer.cornerRadius = cornerRadius
        clipsToBounds      = true

        if let first = viewModel.firstLocalCalendarColor {
            color = first
            backgroundColor = first.withAlphaComponent(0.3)
        } else {
            color = .systemBlue
            backgroundColor = .systemBlue.withAlphaComponent(0.3)
        }

        textView.text      = "New Shopping List"
        textView.font      = .systemFont(ofSize: 12, weight: .semibold)
        textView.textColor = color
        eventResizeHandles.forEach { $0.isHidden = true }
    }

    func applyGhostColor(newColor: UIColor) {
        color = newColor
        backgroundColor = newColor.withAlphaComponent(0)
        textView.textColor = color
    }

    public func applyGhostStyleAllDay(event: EventDescriptor) {
        layer.cornerRadius = 5
        clipsToBounds      = true
        color = event.color
        backgroundColor = event.color.withAlphaComponent(0)

        textView.text      = event.text
        textView.font      = .systemFont(ofSize: 12, weight: .semibold)
        textView.textColor = color
        eventResizeHandles.forEach { $0.isHidden = true }
    }

    public func applyGhostStyleNoAllDay(event: EventDescriptor) {
        layer.cornerRadius = 9
        clipsToBounds      = true
        color              = event.color
        backgroundColor    = color.withAlphaComponent(0)

        let icon = NSTextAttachment()
        icon.image = UIImage(systemName: "calendar.circle.fill")?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        icon.bounds = CGRect(x: 0, y: -2, width: 14, height: 14)

        let att = NSMutableAttributedString(attachment: icon)
        att.append(NSAttributedString(string: " \(event.text)"))

        textView.attributedText = att
        textView.font           = .systemFont(ofSize: 12, weight: .semibold)
        textView.textColor      = color
        eventResizeHandles.forEach { $0.isHidden = true }
    }
}

