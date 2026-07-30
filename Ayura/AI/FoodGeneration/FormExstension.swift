// DTO → Form мапъри
extension MacroForm {
    @available(iOS 26.0, *)
    init(from dto: MacronutrientsDTO?) {
        self.init()
        guard let d = dto else { return }
        self.carbohydrates = d.carbohydrates
        self.protein       = d.protein
        self.fat           = d.fat
        self.fiber         = d.fiber
        self.totalSugars   = d.totalSugars
    }
}

extension OtherForm {
    @available(iOS 26.0, *)
    init(from dto: OtherDTO?) {
        self.init()
        guard let d = dto else { return }
        self.alcoholEthyl = d.alcoholEthyl
        self.caffeine     = d.caffeine
        self.theobromine  = d.theobromine
        self.cholesterol  = d.cholesterol
        self.energyKcal   = d.energyKcal
        self.water        = d.water
        self.weightG      = d.weightG
        self.ash          = d.ash
        self.betaine      = d.betaine
        self.alkalinityPH = d.alkalinityPH 
    }
}

extension VitaminForm {
    @available(iOS 26.0, *)
    init(from dto: VitaminsDTO?) {
        self.init()
        guard let d = dto else { return }
        self.vitaminA_RAE = d.vitaminA_RAE
        self.retinol = d.retinol
        self.caroteneAlpha = d.caroteneAlpha
        self.caroteneBeta = d.caroteneBeta
        self.cryptoxanthinBeta = d.cryptoxanthinBeta
        self.luteinZeaxanthin  = d.luteinZeaxanthin
        self.lycopene          = d.lycopene
        self.vitaminB1_Thiamin = d.vitaminB1_Thiamin
        self.vitaminB2_Riboflavin = d.vitaminB2_Riboflavin
        self.vitaminB3_Niacin = d.vitaminB3_Niacin
        self.vitaminB5_PantothenicAcid = d.vitaminB5_PantothenicAcid
        self.vitaminB6 = d.vitaminB6
        self.folateDFE = d.folateDFE
        self.folateFood = d.folateFood
        self.folateTotal = d.folateTotal
        self.folicAcid = d.folicAcid
        self.vitaminB12 = d.vitaminB12
        self.vitaminC = d.vitaminC
        self.vitaminD = d.vitaminD
        self.vitaminE = d.vitaminE
        self.vitaminK = d.vitaminK
        self.choline  = d.choline
    }
}

extension MineralForm {
    @available(iOS 26.0, *)
    init(from dto: MineralsDTO?) {
        self.init()
        guard let d = dto else { return }
        self.calcium    = d.calcium
        self.iron       = d.iron
        self.magnesium  = d.magnesium
        self.phosphorus = d.phosphorus
        self.potassium  = d.potassium
        self.sodium     = d.sodium
        self.selenium   = d.selenium
        self.zinc       = d.zinc
        self.copper     = d.copper
        self.manganese  = d.manganese
        self.fluoride   = d.fluoride
    }
}

extension LipidForm {
    @available(iOS 26.0, *)
    init(from dto: LipidsDTO?) {
        self.init()
        guard let d = dto else { return }
        self.totalSaturated       = d.totalSaturated
        self.totalMonounsaturated = d.totalMonounsaturated
        self.totalPolyunsaturated = d.totalPolyunsaturated
        self.totalTrans           = d.totalTrans
        self.totalTransMonoenoic  = d.totalTransMonoenoic
        self.totalTransPolyenoic  = d.totalTransPolyenoic

        self.sfa4_0  = d.sfa4_0
        self.sfa6_0  = d.sfa6_0
        self.sfa8_0  = d.sfa8_0
        self.sfa10_0 = d.sfa10_0
        self.sfa12_0 = d.sfa12_0
        self.sfa13_0 = d.sfa13_0
        self.sfa14_0 = d.sfa14_0
        self.sfa15_0 = d.sfa15_0
        self.sfa16_0 = d.sfa16_0
        self.sfa17_0 = d.sfa17_0
        self.sfa18_0 = d.sfa18_0
        self.sfa20_0 = d.sfa20_0
        self.sfa22_0 = d.sfa22_0
        self.sfa24_0 = d.sfa24_0

        self.mufa14_1 = d.mufa14_1
        self.mufa15_1 = d.mufa15_1
        self.mufa16_1 = d.mufa16_1
        self.mufa17_1 = d.mufa17_1
        self.mufa18_1 = d.mufa18_1
        self.mufa20_1 = d.mufa20_1
        self.mufa22_1 = d.mufa22_1
        self.mufa24_1 = d.mufa24_1

        self.tfa16_1_t = d.tfa16_1_t
        self.tfa18_1_t = d.tfa18_1_t
        self.tfa22_1_t = d.tfa22_1_t
        self.tfa18_2_t = d.tfa18_2_t

        self.pufa18_2 = d.pufa18_2
        self.pufa18_3 = d.pufa18_3
        self.pufa18_4 = d.pufa18_4
        self.pufa20_2 = d.pufa20_2
        self.pufa20_3 = d.pufa20_3
        self.pufa20_4 = d.pufa20_4
        self.pufa20_5 = d.pufa20_5
        self.pufa21_5 = d.pufa21_5
        self.pufa22_4 = d.pufa22_4
        self.pufa22_5 = d.pufa22_5
        self.pufa22_6 = d.pufa22_6
        self.pufa2_4  = d.pufa2_4
    }
}

extension AminoAcidsForm {
    @available(iOS 26.0, *)
    init(from dto: AminoAcidsDTO?) {
        self.init()
        guard let d = dto else { return }
        self.alanine        = d.alanine
        self.arginine       = d.arginine
        self.asparticAcid   = d.asparticAcid
        self.cystine        = d.cystine
        self.glutamicAcid   = d.glutamicAcid
        self.glycine        = d.glycine
        self.histidine      = d.histidine
        self.isoleucine     = d.isoleucine
        self.leucine        = d.leucine
        self.lysine         = d.lysine
        self.methionine     = d.methionine
        self.phenylalanine  = d.phenylalanine
        self.proline        = d.proline
        self.threonine      = d.threonine
        self.tryptophan     = d.tryptophan
        self.tyrosine       = d.tyrosine
        self.valine         = d.valine
        self.serine         = d.serine
        self.hydroxyproline = d.hydroxyproline
    }
}

extension CarbDetailsForm {
    @available(iOS 26.0, *)
    init(from dto: CarbDetailsDTO?) {
        self.init()
        guard let d = dto else { return }
        self.starch    = d.starch
        self.sucrose   = d.sucrose
        self.glucose   = d.glucose
        self.fructose  = d.fructose
        self.lactose   = d.lactose
        self.maltose   = d.maltose
        self.galactose = d.galactose
    }
}

extension SterolsForm {
    @available(iOS 26.0, *)
    init(from dto: SterolsDTO?) {
        self.init()
        guard let d = dto else { return }
        self.phytosterols   = d.phytosterols
        self.betaSitosterol = d.betaSitosterol
        self.campesterol    = d.campesterol
        self.stigmasterol   = d.stigmasterol
    }
}

extension Nutrient {
    @available(iOS 26.0, *)
    init?(from aiNutrient: AINutrient?) {
        guard let value = aiNutrient?.value, let unit = aiNutrient?.unit else { return nil }
        self.init(value: value, unit: unit)
    }
}
