import SwiftData
import Foundation

@Model
public final class LipidsData: Identifiable {

    // MARK: – Основни данни
    @Attribute(.unique) public var id = UUID()

    // MARK: – Общи стойности (lipids_main)
    public var totalSaturated:        Nutrient?   // Fatty acids, total saturated (G)
    public var totalMonounsaturated:  Nutrient?   // Fatty acids, total monounsaturated (G)
    public var totalPolyunsaturated:  Nutrient?   // Fatty acids, total polyunsaturated (G)
    public var totalTrans:            Nutrient?   // Fatty acids, total trans (G)
    public var totalTransMonoenoic:   Nutrient?   // Fatty acids, total trans-monoenoic (G)
    public var totalTransPolyenoic:   Nutrient?   // Fatty acids, total trans-polyenoic (G)

    // MARK: – Наситени мастни киселини (SFA)
    public var sfa4_0:  Nutrient?     // SFA 4:0 (G)
    public var sfa6_0:  Nutrient?     // SFA 6:0 (G)
    public var sfa8_0:  Nutrient?     // SFA 8:0 (G)
    public var sfa10_0: Nutrient?     // SFA 10:0 (G)
    public var sfa12_0: Nutrient?     // SFA 12:0 (G)
    public var sfa13_0: Nutrient?     // SFA 13:0 (G)
    public var sfa14_0: Nutrient?     // SFA 14:0 (G)
    public var sfa15_0: Nutrient?     // SFA 15:0 (G)
    public var sfa16_0: Nutrient?     // SFA 16:0 (G)
    public var sfa17_0: Nutrient?     // SFA 17:0 (G)
    public var sfa18_0: Nutrient?     // SFA 18:0 (G)
    public var sfa20_0: Nutrient?     // SFA 20:0 (G)
    public var sfa22_0: Nutrient?     // SFA 22:0 (G)
    public var sfa24_0: Nutrient?     // SFA 24:0 (G)

    // MARK: – Мононенаситени (MUFA)
    public var mufa14_1: Nutrient?    // MUFA 14:1 (G)
    public var mufa15_1: Nutrient?    // MUFA 15:1 (G)
    public var mufa16_1: Nutrient?    // MUFA 16:1 (G)
    public var mufa17_1: Nutrient?    // MUFA 17:1 (G)
    public var mufa18_1: Nutrient?    // MUFA 18:1 (G)
    public var mufa20_1: Nutrient?    // MUFA 20:1 (G)
    public var mufa22_1: Nutrient?    // MUFA 22:1 (G)
    public var mufa24_1: Nutrient?    // MUFA 24:1 (G)

    // MARK: – Транс-мастни (TFA ... t)
    public var tfa16_1_t: Nutrient?   // TFA 16:1 t (G)
    public var tfa18_1_t: Nutrient?   // TFA 18:1 t (G)
    public var tfa22_1_t: Nutrient?   // TFA 22:1 t (G)
    public var tfa18_2_t: Nutrient?   // TFA 18:2 t (G)

    // MARK: – Полиненаситени (PUFA)
    public var pufa18_2: Nutrient?    // PUFA 18:2 (G)
    public var pufa18_3: Nutrient?    // PUFA 18:3 (G)
    public var pufa18_4: Nutrient?    // PUFA 18:4 (G)
    public var pufa20_2: Nutrient?    // PUFA 20:2 (G)
    public var pufa20_3: Nutrient?    // PUFA 20:3 (G)
    public var pufa20_4: Nutrient?    // PUFA 20:4 (G)
    public var pufa20_5: Nutrient?    // PUFA 20:5 (G)
    public var pufa21_5: Nutrient?    // PUFA 21:5 (G)
    public var pufa22_4: Nutrient?    // PUFA 22:4 (G)
    public var pufa22_5: Nutrient?    // PUFA 22:5 (G)
    public var pufa22_6: Nutrient?    // PUFA 22:6 (G)
    public var pufa2_4:  Nutrient?    // PUFA 2:4 (G) – „странната“ колона, ако присъства

    // MARK: – Връзки
    @Relationship(inverse: \FoodItem.lipids) public var foodItem: FoodItem?

    // MARK: – Инициализатор
    public init(
        totalSaturated:        Nutrient? = nil,
        totalMonounsaturated:  Nutrient? = nil,
        totalPolyunsaturated:  Nutrient? = nil,
        totalTrans:            Nutrient? = nil,
        totalTransMonoenoic:   Nutrient? = nil,
        totalTransPolyenoic:   Nutrient? = nil,

        sfa4_0:  Nutrient? = nil,
        sfa6_0:  Nutrient? = nil,
        sfa8_0:  Nutrient? = nil,
        sfa10_0: Nutrient? = nil,
        sfa12_0: Nutrient? = nil,
        sfa13_0: Nutrient? = nil,
        sfa14_0: Nutrient? = nil,
        sfa15_0: Nutrient? = nil,
        sfa16_0: Nutrient? = nil,
        sfa17_0: Nutrient? = nil,
        sfa18_0: Nutrient? = nil,
        sfa20_0: Nutrient? = nil,
        sfa22_0: Nutrient? = nil,
        sfa24_0: Nutrient? = nil,

        mufa14_1: Nutrient? = nil,
        mufa15_1: Nutrient? = nil,
        mufa16_1: Nutrient? = nil,
        mufa17_1: Nutrient? = nil,
        mufa18_1: Nutrient? = nil,
        mufa20_1: Nutrient? = nil,
        mufa22_1: Nutrient? = nil,
        mufa24_1: Nutrient? = nil,

        tfa16_1_t: Nutrient? = nil,
        tfa18_1_t: Nutrient? = nil,
        tfa22_1_t: Nutrient? = nil,
        tfa18_2_t: Nutrient? = nil,

        pufa18_2: Nutrient? = nil,
        pufa18_3: Nutrient? = nil,
        pufa18_4: Nutrient? = nil,
        pufa20_2: Nutrient? = nil,
        pufa20_3: Nutrient? = nil,
        pufa20_4: Nutrient? = nil,
        pufa20_5: Nutrient? = nil,
        pufa21_5: Nutrient? = nil,
        pufa22_4: Nutrient? = nil,
        pufa22_5: Nutrient? = nil,
        pufa22_6: Nutrient? = nil,
        pufa2_4:  Nutrient? = nil
    ) {
        self.totalSaturated       = totalSaturated
        self.totalMonounsaturated = totalMonounsaturated
        self.totalPolyunsaturated = totalPolyunsaturated
        self.totalTrans           = totalTrans
        self.totalTransMonoenoic  = totalTransMonoenoic
        self.totalTransPolyenoic  = totalTransPolyenoic

        self.sfa4_0  = sfa4_0
        self.sfa6_0  = sfa6_0
        self.sfa8_0  = sfa8_0
        self.sfa10_0 = sfa10_0
        self.sfa12_0 = sfa12_0
        self.sfa13_0 = sfa13_0
        self.sfa14_0 = sfa14_0
        self.sfa15_0 = sfa15_0
        self.sfa16_0 = sfa16_0
        self.sfa17_0 = sfa17_0
        self.sfa18_0 = sfa18_0
        self.sfa20_0 = sfa20_0
        self.sfa22_0 = sfa22_0
        self.sfa24_0 = sfa24_0

        self.mufa14_1 = mufa14_1
        self.mufa15_1 = mufa15_1
        self.mufa16_1 = mufa16_1
        self.mufa17_1 = mufa17_1
        self.mufa18_1 = mufa18_1
        self.mufa20_1 = mufa20_1
        self.mufa22_1 = mufa22_1
        self.mufa24_1 = mufa24_1

        self.tfa16_1_t = tfa16_1_t
        self.tfa18_1_t = tfa18_1_t
        self.tfa22_1_t = tfa22_1_t
        self.tfa18_2_t = tfa18_2_t

        self.pufa18_2 = pufa18_2
        self.pufa18_3 = pufa18_3
        self.pufa18_4 = pufa18_4
        self.pufa20_2 = pufa20_2
        self.pufa20_3 = pufa20_3
        self.pufa20_4 = pufa20_4
        self.pufa20_5 = pufa20_5
        self.pufa21_5 = pufa21_5
        self.pufa22_4 = pufa22_4
        self.pufa22_5 = pufa22_5
        self.pufa22_6 = pufa22_6
        self.pufa2_4  = pufa2_4
    }
}
