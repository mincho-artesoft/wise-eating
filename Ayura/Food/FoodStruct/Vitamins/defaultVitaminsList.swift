import Foundation

nonisolated(unsafe) let defaultVitaminsList: [Vitamin] = [

    Vitamin(
        id: "vitA",
        name: "Vitamin A (RAE)",
        unit: "µg",
        abbreviation: "Vit A",
        colorHex: "#F6DDCC",
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 400, upperLimit: 600),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 500, upperLimit: 600),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 300, upperLimit: 600),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 400, upperLimit: 900),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 600, upperLimit: 1700),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 700, upperLimit: 2800),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 900, upperLimit: 2800),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 700, upperLimit: 3000),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 900, upperLimit: 3000),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 700, upperLimit: 3000),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 900, upperLimit: 3000),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 770, upperLimit: 3000), // Коректна стойност
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 1300, upperLimit: 3000) // Коректна стойност
        ]
    ),
    Vitamin(
        id: "retinol",
        name: "Retinol",
        unit: "µg",
        abbreviation: "Retinol",
        colorHex: "#FDEBD0",
        requirements: [
            // DailyNeed е 0, защото няма отделна дневна нужда от ретинол.
            // Нуждата е за общ Vitamin A (RAE).
            // UpperLimit е за предварително формиран Vitamin A (ретинол) и е коректен.
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 0, upperLimit: 600),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0, upperLimit: 600),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0, upperLimit: 600),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 0, upperLimit: 900),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 0, upperLimit: 1700),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 0, upperLimit: 2800),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 0, upperLimit: 2800),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 0, upperLimit: 3000),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 0, upperLimit: 3000),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 0, upperLimit: 3000),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 0, upperLimit: 3000),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 0, upperLimit: 3000),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 0, upperLimit: 3000)
        ]
    ),
    Vitamin(
        id: "caroteneAlpha",
        name: "Carotene, alpha",
        unit: "µg",
        abbreviation: "α-Carotene",
        colorHex: "#FFF5BA",
        requirements: [
            // Няма установена дневна нужда или горна граница за алфа-каротин
            // за никоя демографска група.
            Requirement(demographic: Demographic.babies0_6m, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentMales14_18y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen19_50y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen51plusY, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.pregnantWomen, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.lactatingWomen, dailyNeed: 0, upperLimit: nil)
        ]
    ),
    Vitamin(
        id: "caroteneBeta",
        name: "Carotene, beta",
        unit: "µg",
        abbreviation: "β-Carotene",
        colorHex: "#FCF3CF",
        requirements: [
            // Няма установена дневна нужда или горна граница за бета-каротин
            // за никоя демографска група, когато се приема от храна.
            Requirement(demographic: Demographic.babies0_6m, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentMales14_18y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen19_50y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen51plusY, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.pregnantWomen, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.lactatingWomen, dailyNeed: 0, upperLimit: nil)
        ]
    ),
    Vitamin(
        id: "cryptoxanthinBeta",
        name: "Cryptoxanthin, beta",
        unit: "µg",
        abbreviation: "β-Cryptoxanthin",
        colorHex: "#F9E79F",
        requirements: [
            // Няма установена дневна нужда или горна граница за бета-криптоксантин
            // за никоя демографска група.
            Requirement(demographic: Demographic.babies0_6m, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentMales14_18y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen19_50y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen51plusY, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.pregnantWomen, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.lactatingWomen, dailyNeed: 0, upperLimit: nil)
        ]
    ),
    Vitamin(
        id: "luteinZeaxanthin",
        name: "Lutein + Zeaxanthin",
        unit: "µg",
        abbreviation: "Lutein/Zea",
        colorHex: "#FADBD8",
        requirements: [
            // Няма официално установена дневна нужда или горна граница
            // за лутеин и зеаксантин за никоя демографска група.
            Requirement(demographic: Demographic.babies0_6m, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentMales14_18y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen19_50y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen51plusY, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.pregnantWomen, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.lactatingWomen, dailyNeed: 0, upperLimit: nil)
        ]
    ),
    Vitamin(
        id: "lycopene",
        name: "Lycopene",
        unit: "µg", // Уверете се, че данните, които въвеждате, са в микрограми. 10 mg = 10,000 µg
        abbreviation: "Lycopene",
        colorHex: "#FDEDEC",
        requirements: [
            // Няма официално установена дневна нужда или горна граница
            // за ликопен за никоя демографска група.
            Requirement(demographic: Demographic.babies0_6m, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentMales14_18y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen19_50y, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen51plusY, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.pregnantWomen, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.lactatingWomen, dailyNeed: 0, upperLimit: nil)
        ]
    ),
    Vitamin(
        id: "vitB1",
        name: "Vitamin B1 (Thiamin)",
        unit: "mg",
        abbreviation: "Vit B1",
        colorHex: "#D6ECFF",
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 0.2, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0.3, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0.5, upperLimit: nil),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 0.6, upperLimit: nil),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 0.9, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 1.0, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 1.2, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 1.1, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 1.2, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 1.1, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 1.2, upperLimit: nil),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 1.4, upperLimit: nil),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 1.4, upperLimit: nil)
        ]
    ),
    Vitamin(
        id: "vitB2",
        name: "Vitamin B2 (Riboflavin)",
        unit: "mg",
        abbreviation: "Vit B2",
        colorHex: "#CCE5FF",
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 0.3, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0.4, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0.5, upperLimit: nil),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 0.6, upperLimit: nil),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 0.9, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 1.0, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 1.3, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 1.1, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 1.3, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 1.1, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 1.3, upperLimit: nil),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 1.4, upperLimit: nil),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 1.6, upperLimit: nil)
        ]
    ),
    Vitamin(
        id: "vitB3",
        name: "Vitamin B3 (Niacin)",
        unit: "mg",
        abbreviation: "Vit B3",
        colorHex: "#D5F5FA",
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 2,  upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 4,  upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 6,  upperLimit: 10),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 8,  upperLimit: 15),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 12, upperLimit: 20),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 14, upperLimit: 30),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 16, upperLimit: 30),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 14, upperLimit: 35),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 16, upperLimit: 35),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 14, upperLimit: 35),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 16, upperLimit: 35),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 18, upperLimit: 30), // има грешка тук
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 17, upperLimit: 30) // има грешка тук
        ]
    ),
    Vitamin(
        id: "vitB5",
        name: "Vitamin B5 (Pantothenic Acid)",
        unit: "mg",
        abbreviation: "Vit B5",
        colorHex: "#D1F2EB",
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 1.7, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 1.8, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 2,   upperLimit: nil),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 3,   upperLimit: nil),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 4,   upperLimit: nil),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 5, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 5, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 5, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 5, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 5, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 5, upperLimit: nil),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 6, upperLimit: nil),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 7, upperLimit: nil)
        ]
    ),
    Vitamin(
        id: "vitB6",
        name: "Vitamin B6 (Pyridoxine)",
        unit: "mg",
        abbreviation: "Vit B6",
        colorHex: "#EAF2F8",
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 0.1, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0.3, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0.5, upperLimit: 30),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 0.6, upperLimit: 40),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 1.0, upperLimit: 60),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 1.2, upperLimit: 80),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 1.3, upperLimit: 80),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 1.3, upperLimit: 100),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 1.3, upperLimit: 100),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 1.5, upperLimit: 100),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 1.7, upperLimit: 100),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 1.9, upperLimit: 100),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 2.0, upperLimit: 100)
        ]
    ),
    Vitamin(
        id: "folateFood",
        name: "Folate, food",
        unit: "µg",
        abbreviation: "Food Folate",
        colorHex: "#E8F8F5",
        requirements: [
            // DailyNeed е в µg DFE (Dietary Folate Equivalents).
            // За фолат от храна, 1 µg = 1 µg DFE.
            // Няма установена горна граница (UL) за фолат от хранителни източници.
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 65,  upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 80,  upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 150, upperLimit: nil),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 200, upperLimit: nil),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 300, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 400, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 400, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 400, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 400, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 400, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 400, upperLimit: nil),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 600, upperLimit: nil),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 500, upperLimit: nil)
        ]
    ),
    Vitamin(
        id: "folateTotal",
        name: "Total Folate",
        unit: "µg", // Технически, това е µg DFE
        abbreviation: "Total Folate",
        colorHex: "#D5F5E3",
        requirements: [
            // DailyNeed е в µg DFE.
            // UpperLimit се отнася за синтетичната фолиева киселина, но се прилага към общия прием.
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 65,  upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 80,  upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 150, upperLimit: 300),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 200, upperLimit: 400),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 300, upperLimit: 600),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 400, upperLimit: 800),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 400, upperLimit: 800),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 400, upperLimit: 1000),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 400, upperLimit: 1000),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 400, upperLimit: 1000),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 400, upperLimit: 1000),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 600, upperLimit: 1000),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 500, upperLimit: 1000)
        ]
    ),
    Vitamin(
        id: "folicAcid",
        name: "Folic acid",
        unit: "µg",
        abbreviation: "Folic Acid",
        colorHex: "#D5F5E3", // Може да изберете различен цвят, за да го отличите от Total Folate
        requirements: [
            // DailyNeed е 0, тъй като няма специфична нужда от тази синтетична форма.
            // Нуждата е за общ фолат (DFE).
            // UpperLimit е ключов тук и се отнася САМО за фолиева киселина.
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0, upperLimit: 300),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 0, upperLimit: 400),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 0, upperLimit: 600),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 0, upperLimit: 800),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 0, upperLimit: 800),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 0, upperLimit: 1000),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 0, upperLimit: 1000),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 0, upperLimit: 1000),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 0, upperLimit: 1000),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 0, upperLimit: 1000),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 0, upperLimit: 1000)
        ]
    ),
    Vitamin(
        id: "vitB12",
        name: "Vitamin B-12",
        unit: "µg",
        abbreviation: "Vit B12",
        colorHex: "#E6E0F8",
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 0.4, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0.5, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0.9, upperLimit: nil),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 1.2, upperLimit: nil),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 1.8, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 2.4, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 2.4, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 2.4, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 2.4, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 2.4, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 2.4, upperLimit: nil),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 2.6, upperLimit: nil),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 2.8, upperLimit: nil)
        ]
    ),
    Vitamin(
        id: "vitC",
        name: "Vitamin C, total ascorbic acid",
        unit: "mg",
        abbreviation: "Vit C",
        colorHex: "#FFE5CC",
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 40, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 50, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 15, upperLimit: 400),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 25, upperLimit: 650),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 45, upperLimit: 1200),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 65, upperLimit: 1800),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 75, upperLimit: 1800),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 75, upperLimit: 2000),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 90, upperLimit: 2000),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 75, upperLimit: 2000),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 90, upperLimit: 2000),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 85, upperLimit: 2000),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 120, upperLimit: 2000)
        ]
    ),
    Vitamin(
        id: "vitD",
        name: "Vitamin D (D2 + D3)",
        unit: "µg",
        abbreviation: "Vit D",
        colorHex: "#FFF9E3",
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 10,  upperLimit: 25),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 10,  upperLimit: 38),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 15,  upperLimit: 63),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 15,  upperLimit: 75),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 15,  upperLimit: 100),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 15, upperLimit: 100),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 15, upperLimit: 100),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 15, upperLimit: 100),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 15, upperLimit: 100),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 20, upperLimit: 100),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 20, upperLimit: 100),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 15, upperLimit: 100),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 15, upperLimit: 100)
        ]
    ),
    Vitamin(
        id: "vitE",
        name: "Vitamin E (alpha-tocopherol)",
        unit: "mg",
        abbreviation: "Vit E",
        colorHex: "#FDF2E9",
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 4,  upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 5,  upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 6,  upperLimit: 200),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 7,  upperLimit: 300),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 11, upperLimit: 600),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 15, upperLimit: 800),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 15, upperLimit: 800),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 15, upperLimit: 1000),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 15, upperLimit: 1000),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 15, upperLimit: 1000),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 15, upperLimit: 1000),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 15, upperLimit: 1000),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 19, upperLimit: 1000)
        ]
    ),
    Vitamin(
        id: "vitK",
        name: "Vitamin K",
        unit: "µg",
        abbreviation: "Vit K",
        colorHex: "#D5F5E3", // Light Mint
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 2.0, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 2.5, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 30,  upperLimit: nil),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 55,  upperLimit: nil),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 60,  upperLimit: nil),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 75, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 75, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 90, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 120, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 90, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 120, upperLimit: nil),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 90, upperLimit: nil),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 90, upperLimit: nil)
        ]
    ),
    Vitamin(
        id: "choline",
        name: "Choline",
        unit: "mg",
        abbreviation: "Choline",
        colorHex: "#EBDEF0",
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 125, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 150, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 200, upperLimit: 1000),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 250, upperLimit: 1000),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 375, upperLimit: 2000),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 400, upperLimit: 3000),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 550, upperLimit: 3000),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 425, upperLimit: 3500),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 550, upperLimit: 3500),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 425, upperLimit: 3500),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 550, upperLimit: 3500),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 450, upperLimit: 3500),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 550, upperLimit: 3500)
        ]
    ),
    Vitamin(
        id: "folateDFE",
        name: "Folate (DFE)",
        unit: "µg",
        abbreviation: "Folate DFE",
        colorHex: "#D5F5E3", // Можете да използвате същия или подобен цвят
        requirements: [
            // DailyNeed е в µg DFE.
            // UpperLimit се отнася за синтетичната фолиева киселина, но се прилага към общия прием.
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 65,  upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 80,  upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 150, upperLimit: 300),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 200, upperLimit: 400),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 300, upperLimit: 600),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 400, upperLimit: 800),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 400, upperLimit: 800),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 400, upperLimit: 1000),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 400, upperLimit: 1000),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 400, upperLimit: 1000),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 400, upperLimit: 1000),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 600, upperLimit: 1000),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 500, upperLimit: 1000)
        ]
    ),
]
