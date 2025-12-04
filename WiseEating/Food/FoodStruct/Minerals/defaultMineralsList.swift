import Foundation

nonisolated(unsafe) let defaultMineralsList: [Mineral] = [
    Mineral(
        id: "calcium",
        name: "Calcium",
        unit: "mg",
        symbol: "Ca",
        colorHex: "#D1FFD6", // Mint Green
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 200,  upperLimit: 1000),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 260,  upperLimit: 1500),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 700,  upperLimit: 2500),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 1000, upperLimit: 2500),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 1300, upperLimit: 3000),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 1300, upperLimit: 3000),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 1300, upperLimit: 3000),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 1000, upperLimit: 2500),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 1000, upperLimit: 2500),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 1200, upperLimit: 2000),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 1200, upperLimit: 2000),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 1000, upperLimit: 2500),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 1000, upperLimit: 2500)
        ]
    ),
    Mineral(
        id: "phosphorus",
        name: "Phosphorus",
        unit: "mg",
        symbol: "P",
        colorHex: "#FFE5CC", // Soft Orange
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 100,  upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 275,  upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 460,  upperLimit: 3000),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 500,  upperLimit: 3000),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 1250, upperLimit: 4000),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 1250, upperLimit: 4000),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 1250, upperLimit: 4000),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 700,  upperLimit: 4000),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 700,  upperLimit: 4000),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 700,  upperLimit: 3000),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 700,  upperLimit: 3000),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 700,  upperLimit: 3500),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 700,  upperLimit: 4000)
        ]
    ),
    Mineral(
        id: "magnesium",
        name: "Magnesium",
        unit: "mg",
        symbol: "Mg",
        colorHex: "#D0F0C0", // Tea Green
        requirements: [
            // Забележка: Горната граница (UL) се отнася САМО за магнезий от добавки,
            // а не за магнезий от храна. Затова дневната нужда (RDA) може да е по-висока от UL.
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 30,  upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 75,  upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 80,  upperLimit: 65),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 130, upperLimit: 110),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 240, upperLimit: 350),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 360, upperLimit: 350),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 410, upperLimit: 350),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 310, upperLimit: 350),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 400, upperLimit: 350),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 320, upperLimit: 350),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 420, upperLimit: 350),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 350, upperLimit: 350),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 310, upperLimit: 350)
        ]
    ),
    Mineral(
        id: "potassium",
        name: "Potassium",
        unit: "mg",
        symbol: "K",
        colorHex: "#F5D1FF", // Soft Purple
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 400,  upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 860,  upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 2000, upperLimit: nil),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 2300, upperLimit: nil),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 2500, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 2300, upperLimit: nil),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 3000, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 2600, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 3400, upperLimit: nil),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 2600, upperLimit: nil),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 3400, upperLimit: nil),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 2900, upperLimit: nil),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 2800, upperLimit: nil)
        ]
    ),
    Mineral(
        id: "sodium",
        name: "Sodium",
        unit: "mg",
        symbol: "Na",
        colorHex: "#EBDEF0", // Orchid Mist
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 110,  upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 370,  upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 800,  upperLimit: 1500),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 1000, upperLimit: 1900),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 1200, upperLimit: 2200),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 1500, upperLimit: 2300),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 1500, upperLimit: 2300),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 1500, upperLimit: 2300),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 1500, upperLimit: 2300),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 1300, upperLimit: 2300),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 1300, upperLimit: 2300),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 1500, upperLimit: 2300),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 1500, upperLimit: 2300)
        ]
    ),
    Mineral(
        id: "iron",
        name: "Iron",
        unit: "mg",
        symbol: "Fe",
        colorHex: "#F6D8CE", // Blush Coral
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 0.27, upperLimit: 40),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 11,   upperLimit: 40),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 7,    upperLimit: 40),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 10,   upperLimit: 40),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 8,    upperLimit: 40),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 15, upperLimit: 45),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 11, upperLimit: 45),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 18, upperLimit: 45),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 8,  upperLimit: 45),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 8,  upperLimit: 45),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 8,  upperLimit: 45),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 27, upperLimit: 45),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 9,  upperLimit: 45)
        ]
    ),
    Mineral(
        id: "zinc",
        name: "Zinc",
        unit: "mg",
        symbol: "Zn",
        colorHex: "#D6DBDF", // Silver Gray
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 2,   upperLimit: 4),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 3,   upperLimit: 5),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 3,   upperLimit: 7),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 5,   upperLimit: 12),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 8,   upperLimit: 23),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 9,  upperLimit: 34),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 11, upperLimit: 34),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 8,  upperLimit: 40),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 11, upperLimit: 40),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 8,  upperLimit: 40),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 11, upperLimit: 40),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 11, upperLimit: 40),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 12, upperLimit: 40)
        ]
    ),
    Mineral(
        id: "copper",
        name: "Copper",
        unit: "mg",
        symbol: "Cu",
        colorHex: "#F6D8CE", // Blush Coral
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 0.2,  upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0.22, upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0.34, upperLimit: 1),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 0.44, upperLimit: 3),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 0.7,  upperLimit: 5),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 0.89, upperLimit: 8),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 0.89, upperLimit: 8),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 0.9, upperLimit: 10),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 0.9, upperLimit: 10),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 0.9, upperLimit: 10),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 0.9, upperLimit: 10),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 1.0, upperLimit: 10),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 1.3, upperLimit: 10)
        ]
    ),
    Mineral(
        id: "manganese",
        name: "Manganese",
        unit: "mg",
        symbol: "Mn",
        colorHex: "#EAEDED", // Cloud Gray
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 0.003, upperLimit: nil),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0.6,   upperLimit: nil),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 1.2,   upperLimit: 2),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 1.5,   upperLimit: 3),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 1.9,   upperLimit: 6),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 1.6, upperLimit: 9),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 2.2, upperLimit: 9),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 1.8, upperLimit: 11),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 2.3, upperLimit: 11),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 1.8, upperLimit: 11),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 2.3, upperLimit: 11),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 2.0, upperLimit: 11),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 2.6, upperLimit: 11)
        ]
    ),
    Mineral(
        id: "selenium",
        name: "Selenium",
        unit: "µg",
        symbol: "Se",
        colorHex: "#F9E79F", // Honeydew Yellow
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 15,  upperLimit: 45),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 20,  upperLimit: 60),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 20,  upperLimit: 90),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 30,  upperLimit: 150),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 40,  upperLimit: 280),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 55, upperLimit: 400),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 55, upperLimit: 400),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 55, upperLimit: 400),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 55, upperLimit: 400),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 55, upperLimit: 400),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 55, upperLimit: 400),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 60, upperLimit: 400),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 70, upperLimit: 400)
        ]
    ),
    Mineral(
        id: "fluoride",
        name: "Fluoride",
        unit: "mg",
        symbol: "F",
        colorHex: "#FCF3CF", // Pale Gold
        requirements: [
            Requirement(demographic: Demographic.babies0_6m,  dailyNeed: 0.01, upperLimit: 0.7),
            Requirement(demographic: Demographic.babies7_12m, dailyNeed: 0.5,  upperLimit: 0.9),
            Requirement(demographic: Demographic.children1_3y, dailyNeed: 0.7,  upperLimit: 1.3),
            Requirement(demographic: Demographic.children4_8y, dailyNeed: 1.0,  upperLimit: 2.2),
            Requirement(demographic: Demographic.children9_13y, dailyNeed: 2.0,  upperLimit: 10),
            Requirement(demographic: Demographic.adolescentFemales14_18y, dailyNeed: 3.0, upperLimit: 10),
            Requirement(demographic: Demographic.adolescentMales14_18y,  dailyNeed: 4.0, upperLimit: 10),
            Requirement(demographic: Demographic.adultWomen19_50y, dailyNeed: 3.0, upperLimit: 10),
            Requirement(demographic: Demographic.adultMen19_50y,  dailyNeed: 4.0, upperLimit: 10),
            Requirement(demographic: Demographic.adultWomen51plusY, dailyNeed: 3.0, upperLimit: 10),
            Requirement(demographic: Demographic.adultMen51plusY,  dailyNeed: 4.0, upperLimit: 10),
            Requirement(demographic: Demographic.pregnantWomen,   dailyNeed: 3.0, upperLimit: 10),
            Requirement(demographic: Demographic.lactatingWomen,  dailyNeed: 3.0, upperLimit: 10)
        ]
    )
]
