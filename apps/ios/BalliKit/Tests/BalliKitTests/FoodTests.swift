import XCTest
@testable import BalliKit

final class FoodTests: XCTestCase {
    func testNorm() {
        XCTAssertEqual(TextNorm.norm("Çiğ Köfte, İçli"), "cig kofte icli")
        XCTAssertEqual(TextNorm.norm("  Şiş  Ğğ "), "sis gg")
    }
    func testLocalFoodsLoad() {
        XCTAssertGreaterThan(LocalFoods.all.count, 100)
        XCTAssertEqual(FoodSearch.local("yumurta").first?.name, "Yumurta")
        XCTAssertFalse(FoodSearch.local("tavuk").isEmpty)
    }
    func testTypoAndDishes() {
        XCTAssertTrue(FoodSearch.local("tavk gogsu").prefix(3).contains { $0.name.hasPrefix("Tavuk göğsü") })
        XCTAssertTrue(FoodSearch.local("iskender").prefix(3).contains { TextNorm.norm($0.name).contains("iskender") })
        XCTAssertEqual(FoodSearch.local("mercimek corbasi").first?.name, "Mercimek çorbası")
        XCTAssertGreaterThan(LocalFoods.all.count, 800)
    }
    func testMineFirst() {
        let mine = FoodItem(id: "m", name: "Yumurta", per100: Macros(kcal: 150), source: .mine)
        XCTAssertEqual(FoodSearch.local("yumurta", mine: [mine]).first?.id, "m")
    }
    func testParse() {
        let p = TextParser.parseLine("1,5 dilim ekmek")
        XCTAssertEqual(p.qty, 1.5); XCTAssertEqual(p.unit, "dilim"); XCTAssertEqual(p.name, "ekmek")
        XCTAssertEqual(TextParser.parseLine("iki yumurta").qty, 2)
        XCTAssertEqual(TextParser.parseLine("yarım ekmek").frac, 0.5)
        XCTAssertEqual(TextParser.parseLine("150 g makarna").unit, "g")
    }
    func testParseUnitsNU03() {
        let a = TextParser.parseLine("yarım porsiyon patates kızartması")
        XCTAssertEqual(a.qty, 0.5); XCTAssertEqual(a.unit, "porsiyon"); XCTAssertEqual(a.name, "patates kizartmasi")
        XCTAssertEqual(TextParser.parseLine("1 su bardağı süt").unit, "su bardağı")
        XCTAssertEqual(TextParser.parseLine("1 çay kaşığı şeker").unit, "çay kaşığı")
        XCTAssertEqual(TextParser.parseLine("1 fincan türk kahvesi").unit, "fincan")
        let kg = TextParser.parseLine("1 kg tavuk göğsü")
        let chicken = FoodItem(id: "t", name: "Tavuk", per100: Macros(kcal: 120), portions: ["porsiyon": 150, "adet": 250], source: .builtin)
        XCTAssertEqual(TextParser.grams(kg, food: chicken), 1000)
        XCTAssertEqual(TextParser.grams(TextParser.parseLine("tavuk"), food: chicken), 150)   // porsiyon önce
        XCTAssertEqual(TextParser.parseLine("lahmacun").unit, nil)
    }
    func testGenericQueriesNU02() {
        XCTAssertEqual(FoodSearch.local("ekmek").first?.name, "Beyaz ekmek")
        XCTAssertEqual(FoodSearch.local("pilav").first?.name, "Pirinç pilavı")
        XCTAssertEqual(FoodSearch.local("köfte").first?.name, "Köfte (ızgara)")
    }
    func testSplit() {
        XCTAssertEqual(TextParser.split("2 yumurta 1 dilim ekmek"), ["2 yumurta", "1 dilim ekmek"])
        XCTAssertEqual(TextParser.split("1,5 dilim ekmek, çay"), ["1,5 dilim ekmek", "çay"])
        XCTAssertEqual(TextParser.split("1 porsiyon pilav 200 g"), ["1 porsiyon pilav 200 g"])
        XCTAssertEqual(TextParser.split("tavuk ve pilav"), ["tavuk", "pilav"])
    }
    func testGrams() {
        let egg = FoodItem(id: "e", name: "Yumurta", per100: Macros(kcal: 143), portions: ["adet": 55], source: .builtin)
        XCTAssertEqual(TextParser.grams(TextParser.parseLine("2 yumurta"), food: egg), 110)
        XCTAssertEqual(TextParser.grams(TextParser.parseLine("80 g yumurta"), food: egg), 80)
    }
    func testOFFItem() {
        let p: [String: Any] = ["code": "869", "product_name": "Yoğurt", "brands": "Sütaş, X", "nutriments": ["energy-kcal_100g": 60, "proteins_100g": "4,2", "carbohydrates_100g": 5, "fat_100g": 3], "serving_quantity": "150"]
        let f = OpenFoodFacts.item(p)
        XCTAssertEqual(f?.name, "Yoğurt · Sütaş"); XCTAssertEqual(f?.per100.p, 4.2); XCTAssertEqual(f?.portions["porsiyon"], 150)
        XCTAssertNil(OpenFoodFacts.item(["code": "1", "nutriments": [:] as [String: Any]]))
        let kj = OpenFoodFacts.item(["code": "2", "nutriments": ["energy_100g": 418.4, "fat_100g": 1]])
        XCTAssertEqual(kj?.per100.kcal ?? 0, 100, accuracy: 0.1)
        // makrosuz ürün reddedilir; kcal yoksa makrolardan hesaplanır (NU-04)
        XCTAssertNil(OpenFoodFacts.item(["code": "3", "nutriments": ["energy-kcal_100g": 50]]))
        XCTAssertEqual(OpenFoodFacts.item(["code": "4", "nutriments": ["proteins_100g": 10, "carbohydrates_100g": 10, "fat_100g": 0]])?.per100.kcal, 80)
    }
}
