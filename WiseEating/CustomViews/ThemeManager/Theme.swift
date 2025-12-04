import SwiftUI

// 1. Помощна структура, която прави Color Codable
struct CodableColor: Codable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    init(color: Color) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.opacity = Double(a)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

// 2. Помощна структура за кодиране на UnitPoint
struct CodableUnitPoint: Codable {
    let x: CGFloat
    let y: CGFloat
    
    init(unitPoint: UnitPoint) {
        self.x = unitPoint.x
        self.y = unitPoint.y
    }
    
    var unitPoint: UnitPoint {
        UnitPoint(x: x, y: y)
    }
}

// 3. Актуализирана Theme структура
@MainActor
struct Theme: Identifiable, @preconcurrency Codable, @preconcurrency Equatable {
    let id: UUID
    let name: String
    let colors: [CodableColor]
    let startPoint: UnitPoint
    let endPoint: UnitPoint
    
    var screenGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: colors.map { $0.color }),
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
    
    var isDefaultTheme: Bool {
        Theme.defaultThemes.contains(where: { $0.id == self.id })
    }

    init(id: UUID = UUID(), name: String, colors: [Color], startPoint: UnitPoint = .topLeading, endPoint: UnitPoint = .bottomTrailing) {
        self.id = id
        self.name = name
        self.colors = colors.map { CodableColor(color: $0) }
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
    
    static func == (lhs: Theme, rhs: Theme) -> Bool {
        lhs.id == rhs.id
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, colors, startPoint, endPoint
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colors = try container.decode([CodableColor].self, forKey: .colors)
        let startPointCodable = try container.decode(CodableUnitPoint.self, forKey: .startPoint)
        startPoint = startPointCodable.unitPoint
        let endPointCodable = try container.decode(CodableUnitPoint.self, forKey: .endPoint)
        endPoint = endPointCodable.unitPoint
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(colors, forKey: .colors)
        try container.encode(CodableUnitPoint(unitPoint: startPoint), forKey: .startPoint)
        try container.encode(CodableUnitPoint(unitPoint: endPoint), forKey: .endPoint)
    }
}

// ==== ЗАМЕНЕТЕ ТОЗИ КОД ВЪВ ВАШИЯ ФАЙЛ ====

extension Theme {

    // MARK: - Оригинални теми
    static let pureWhite = Theme(id: UUID(uuidString: "C1EAEAEA-1A1A-4B2B-8C8C-FFFFFF000001")!, name: "Pure White", colors: [Color.white])
    static let darkNight = Theme(id: UUID(uuidString: "0D0D0D0D-0A0A-4E4E-9A9A-000000000001")!, name: "Dark Night", colors: [Color.black])
    static let pastelAurora = Theme(id: UUID(uuidString: "E6E8D8E8-1B8A-424A-934C-3F32C0EE4D5E")!, name: "Pastel Aurora", colors: [Color(red: 0.6, green: 0.7, blue: 1.0), Color(red: 0.8, green: 0.6, blue: 1.0), Color(red: 1.0, green: 0.7, blue: 0.9)])
    static let goldenHour = Theme(id: UUID(uuidString: "F8B18A53-3C8A-4A7C-BCF5-8C7D8F9A0F9E")!, name: "Golden Hour", colors: [Color(red: 88/255, green: 63/255, blue: 51/255), Color(red: 248/255, green: 221/255, blue: 85/255)])
    static let cosmicDawn = Theme(id: UUID(uuidString: "A0C0B8E1-8B8A-4B9A-8C1C-8F8D7E6F5C4B")!, name: "Cosmic Dawn", colors: [Color(red: 25/255, green: 25/255, blue: 112/255), Color(red: 138/255, green: 43/255, blue: 226/255), Color(red: 255/255, green: 105/255, blue: 180/255)], startPoint: .top, endPoint: .bottom)
    // MARK: - Нови теми (20)

    // Природни и спокойни
    static let oceanicBreeze = Theme(id: UUID(uuidString: "4A90E2A7-DDF5-4A90-8C8C-000000000001")!, name: "Oceanic Breeze", colors: [Color(red: 167/255, green: 221/255, blue: 245/255), Color(red: 74/255, green: 144/255, blue: 226/255)])
    static let desertDunes = Theme(id: UUID(uuidString: "FFC857E8-8C43-4C9C-8C8C-000000000004")!, name: "Desert Dunes", colors: [Color(red: 255/255, green: 200/255, blue: 87/255), Color(red: 232/255, green: 140/255, blue: 67/255)])
    
    // Ярки и енергични
    static let synthwaveSunset = Theme(id: UUID(uuidString: "FF33A88A-2BE2-4E9A-8C8C-000000000010")!, name: "Synthwave Sunset", colors: [Color(red: 255/255, green: 51/255, blue: 168/255), Color(red: 138/255, green: 43/255, blue: 226/255), Color(red: 52/255, green: 31/255, blue: 151/255)], startPoint: .top, endPoint: .bottom)
    static let cherryBlossom = Theme(id: UUID(uuidString: "FFB7C5FF-E5B4-4CAE-8C8C-000000000011")!, name: "Cherry Blossom", colors: [Color(red: 255/255, green: 183/255, blue: 197/255), Color(red: 255/255, green: 229/255, blue: 180/255)])

    // Елегантни и дълбоки
    static let royalVelvet = Theme(id: UUID(uuidString: "8E2DE24A-00E0-4D4F-8C8C-000000000012")!, name: "Royal Velvet", colors: [Color(red: 142/255, green: 45/255, blue: 226/255), Color(red: 74/255, green: 0/255, blue: 224/255)])
    static let deepSeaSerenity = Theme(id: UUID(uuidString: "0F202720-3A43-41A8-8C8C-000000000013")!, name: "Deep Sea Serenity", colors: [Color(red: 15/255, green: 32/255, blue: 39/255), Color(red: 32/255, green: 58/255, blue: 67/255), Color(red: 44/255, green: 83/255, blue: 100/255)], startPoint: .top, endPoint: .bottom)
    static let galacticVoid = Theme(id: UUID(uuidString: "141E3024-3B55-442C-8C8C-000000000015")!, name: "Galactic Void", colors: [Color(red: 20/255, green: 30/255, blue: 48/255), Color(red: 36/255, green: 59/255, blue: 85/255)])
    
    // Меки и пастелни
    static let cottonCandySky = Theme(id: UUID(uuidString: "A8E6CEF5-DBC4-486A-8C8C-000000000017")!, name: "Cotton Candy Sky", colors: [Color(red: 168/255, green: 230/255, blue: 206/255), Color(red: 245/255, green: 219/255, blue: 196/255)])
    static let frozenTundra = Theme(id: UUID(uuidString: "E0EAFC9F-F2FF-4DEE-8C8C-000000000020")!, name: "Frozen Tundra", colors: [Color(red: 224/255, green: 234/255, blue: 252/255), Color(red: 207/255, green: 216/255, blue: 255/255)], startPoint: .top, endPoint: .bottom)

    // MARK: - Списък с всички теми
    
    static let defaultThemes: [Theme] = [
        .galacticVoid,
        // Оригинални
        .pastelAurora, .goldenHour, .cosmicDawn,
        
        // Нови - Природни
        .oceanicBreeze, .desertDunes,
        
        // Нови - Ярки
        .synthwaveSunset, .cherryBlossom,
        
        // Нови - Елегантни
        .royalVelvet, .deepSeaSerenity,
        
        // Нови - Пастелни
        .cottonCandySky, .frozenTundra,
        
        // Монохромни
        .pureWhite, .darkNight
    ]
}
