import Foundation
import SwiftData

@Model
public final class ShoppingListModel: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var creationDate: Date
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (1/2): Добавяме ново поле +++
    /// Началната дата на събитието в календара. Това е датата, която ще се използва за анализи.
    /// Правим го non-optional с default стойност, за да улесним заявките.
    public var eventStartDate: Date
    // +++ КРАЙ НА ПРОМЯНАТА (1/2) +++
    
    public var isCompleted: Bool
    public var calendarEventID: String? = nil
    
    // --- НАСТРОЙКИ ЗА НАПОМНЯНЕ ---
    
    /// Колко минути преди 'creationDate' да се покаже напомняне.
    /// Ако е 'nil' или 0, няма напомняне.
    public var reminderMinutes: Int? = nil
    
    /// Уникалното ID на планираната локална нотификация в UNUserNotificationCenter.
    /// Използва се за отмяна на нотификацията при промяна или изтриване.
    public var notificationID: String? = nil

    // --- ВРЪЗКИ ---
    
    @Relationship(deleteRule: .cascade, inverse: \DismissedFoodID.list)
    public var dismissedSuggestions: [DismissedFoodID] = []

    @Relationship(deleteRule: .cascade, inverse: \ShoppingListItem.list)
    public var items: [ShoppingListItem] = []

    @Relationship(inverse: \Profile.shoppingLists)
    public var profile: Profile?

    // --- ИНИЦИАЛИЗАТОР ---
    
    public init(profile: Profile?, name: String? = nil, reminderMinutes: Int? = nil) {
        self.id = UUID()
        let now = Date()
        self.creationDate = now
        // +++ НАЧАЛО НА ПРОМЯНАТА (2/2): Инициализираме новото поле +++
        self.eventStartDate = now // По подразбиране е датата на създаване
        // +++ КРАЙ НА ПРОМЯНАТА (2/2) +++
        self.name = name ?? NSLocalizedString("New Shopping List", comment: "Default name")
        self.isCompleted = false
        self.profile = profile
        self.reminderMinutes = reminderMinutes
        // 'notificationID' е nil по подразбиране и се задава по-късно.
    }
    
    // --- ИЗЧИСЛЯЕМИ СВОЙСТВА ---
    
    var totalPrice: Double {
        items.reduce(0) { $0 + ($1.price ?? 0) }
    }

    var purchasedPrice: Double {
        items.filter(\.isBought).reduce(0) { $0 + ($1.price ?? 0) }
    }

    var formattedCreationDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: creationDate)
    }

    // --- МЕТОДИ ---
    
    func addDismissedSuggestion(foodID: Int, context: ModelContext? = nil) {
        if !dismissedSuggestions.contains(where: { $0.foodID == foodID }) {
            let newDismissedID = DismissedFoodID(foodID: foodID)
            dismissedSuggestions.append(newDismissedID)
        }
    }

    func isSuggestionDismissed(foodID: Int) -> Bool {
        dismissedSuggestions.contains { $0.foodID == foodID }
    }
    
    @MainActor
    func processCompletedItems(initiallyBoughtIDs: Set<UUID>, context: ModelContext) throws {
        let newlyBoughtItems = self.items.filter {
            $0.isBought && !initiallyBoughtIDs.contains($0.id) && $0.foodItem != nil
        }
        
        guard !newlyBoughtItems.isEmpty else { return }

        let ownerProfile = self.profile
        let ownerID = ownerProfile?.persistentModelID
        let foodItemIDs = newlyBoughtItems.compactMap { $0.foodItem?.persistentModelID }
        
        let predicate = #Predicate<StorageItem> { $0.owner?.persistentModelID == ownerID }
        let storageDescriptor = FetchDescriptor<StorageItem>(predicate: predicate)
        
        let allUserStorageItems = try context.fetch(storageDescriptor)
        let existingStorageItems = allUserStorageItems.filter { storageItem in
            guard let foodID = storageItem.food?.persistentModelID else { return false }
            return foodItemIDs.contains(foodID)
        }

        var storageItemsMap: [PersistentIdentifier: StorageItem] = [:]
        for storage in existingStorageItems {
            if let foodID = storage.food?.persistentModelID {
                storageItemsMap[foodID] = storage
            }
        }

        for item in newlyBoughtItems {
            guard let foodItem = item.foodItem else { continue }
            let foodID = foodItem.persistentModelID

            if let storageToUpdate = storageItemsMap[foodID] {
                storageToUpdate.batches.append(Batch(quantity: item.quantity))
            } else {
                let newStorage = StorageItem(owner: ownerProfile, food: foodItem, batches: [Batch(quantity: item.quantity)])
                context.insert(newStorage)
            }
            
            let tx = StorageTransaction(
                date: Date(),
                type: .shoppingAddition,
                quantityChange: item.quantity,
                profile: ownerProfile,
                food: foodItem
            )
            context.insert(tx)
        }
    }
}
