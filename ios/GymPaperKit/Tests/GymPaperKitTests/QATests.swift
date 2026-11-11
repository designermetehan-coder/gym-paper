import XCTest
@testable import GymPaperKit

/// QA round: edge cases and regression tests for bugs that were found
final class ProgramShareTests: XCTestCase {
    private func sample() -> [Block] {
        [Block(single: Exercise(name: "Bench Press", sets: 4, reps: 8, rest: 90, kg: 60)),
         Block(superset: [Exercise(name: "Curl", sets: 3, reps: 12), Exercise(name: "Triceps Pushdown", sets: 3, reps: 15)], rounds: 3, rest: 75, tag: "warm"),
         Block(single: Exercise(name: "Plank", sets: 3, reps: 45, unit: "sn", rest: 30))]
    }

    func testRoundTripKeepsPlan() throws {
        let s = try XCTUnwrap(ProgramShare.encode(name: "Üst vücut · Çarşamba", blocks: sample()))
        XCTAssertFalse(s.contains("+") || s.contains("/") || s.contains("="), "base64url olmalı")
        let d = try XCTUnwrap(ProgramShare.decode(s))
        XCTAssertEqual(d.name, "Üst vücut · Çarşamba")
        XCTAssertEqual(d.blocks.count, 3)
        let bench = try XCTUnwrap(d.blocks[0].ex)
        XCTAssertEqual(bench.name, "Bench Press"); XCTAssertEqual(bench.sets, 4); XCTAssertEqual(bench.reps, 8)
        XCTAssertEqual(bench.rest, 90); XCTAssertEqual(bench.kg, 60)
        XCTAssertEqual(d.blocks[1].kind, .superset)
        XCTAssertEqual(d.blocks[1].rounds, 3); XCTAssertEqual(d.blocks[1].rest, 75); XCTAssertEqual(d.blocks[1].tag, "warm")
        XCTAssertEqual(d.blocks[1].exs.map(\.sets), [3, 3], "süpersette set = tur")
        XCTAssertEqual(d.blocks[2].ex?.unit, "sn")
    }

    func testImportGetsFreshIds() throws {
        let b = sample()
        let d = try XCTUnwrap(ProgramShare.decode(XCTUnwrap(ProgramShare.encode(name: "A", blocks: b))))
        XCTAssertNotEqual(d.blocks[0].ex?.id, b[0].ex?.id)
        XCTAssertNotEqual(d.blocks[0].id, b[0].id)
    }

    func testGarbageAndHugeInputsRejected() {
        XCTAssertNil(ProgramShare.decode(""))
        XCTAssertNil(ProgramShare.decode("!!!bozuk!!!"))
        XCTAssertNil(ProgramShare.decode("aGVsbG8"))                       // valid base64, not zlib
        XCTAssertNil(ProgramShare.decode(String(repeating: "A", count: 20_000)))
        XCTAssertNil(ProgramShare.encode(name: "Boş", blocks: []).flatMap(ProgramShare.decode))   // a program without exercises isn't imported
    }

    func testOutOfRangeValuesClamped() throws {
        let b = [Block(single: Exercise(name: String(repeating: "x", count: 200), sets: 99, reps: 0, unit: "bilinmez", rest: 5000, kg: 5000))]
        let d = try XCTUnwrap(ProgramShare.decode(XCTUnwrap(ProgramShare.encode(name: String(repeating: "P", count: 100), blocks: b))))
        let e = try XCTUnwrap(d.blocks[0].ex)
        XCTAssertEqual(e.sets, 20); XCTAssertEqual(e.reps, 1); XCTAssertEqual(e.unit, "tekrar")
        XCTAssertEqual(e.rest, 900); XCTAssertEqual(e.kg, 999)
        XCTAssertEqual(e.name.count, 80); XCTAssertEqual(d.name.count, 60)
    }

    func testTypicalProgramFitsInQR() throws {
        let blocks = (1...12).map { Block(single: Exercise(name: "Hareket numarası \($0) dumbbell", sets: 4, reps: 10, rest: 90, kg: Double($0) * 2.5)) }
        let s = try XCTUnwrap(ProgramShare.encode(name: "Tam vücut", blocks: blocks))
        XCTAssertLessThan(s.count, 1500, "QR (M) kapasitesinin altında kalmalı")
    }
}

final class ParserQATests: XCTestCase {
    private func food(_ name: String, kcal: Double = 100, _ portions: [String: Double]) -> FoodItem {
        FoodItem(id: name, name: name, per100: Macros(kcal: kcal), portions: portions, source: .builtin)
    }

    // absurd amounts must not overflow the math
    func testHugeQuantityClamped() {
        let p = TextParser.parseLine("99999999999999999999 g tavuk")
        XCTAssertLessThanOrEqual(p.qty, TextParser.maxQty)
        let g = TextParser.grams(p, food: food("Tavuk", kcal: 165, ["porsiyon": 150]))
        XCTAssertTrue(g.isFinite)
        XCTAssertLessThan(g * 165 / 100, Double(Int.max))
    }

    // generic words go to the right food
    func testGenericWords() {
        XCTAssertEqual(FoodSearch.local("su").first?.name, "Su")
        XCTAssertEqual(FoodSearch.local("şeker").first?.name, "Toz şeker")
        XCTAssertEqual(FoodSearch.local("kıyma").first?.name, "Dana kıyma (%20 yağ)")
        XCTAssertEqual(FoodSearch.local("tuz").first?.name, "Tuz")
    }

    // pieces when a count is given, servings otherwise
    func testCountPrefersAdet() {
        let kofte = food("Köfte", ["adet": 25, "porsiyon": 150])
        XCTAssertEqual(TextParser.grams(TextParser.parseLine("3 köfte"), food: kofte), 75)
        XCTAssertEqual(TextParser.grams(TextParser.parseLine("üç köfte"), food: kofte), 75)
        XCTAssertEqual(TextParser.grams(TextParser.parseLine("köfte"), food: kofte), 150)
        XCTAssertEqual(TextParser.grams(TextParser.parseLine("1 porsiyon köfte"), food: kofte), 150)
    }

    // spoon/cup units the food lacks are scaled
    func testVolumeLadder() {
        let bal = food("Bal", kcal: 304, ["tatlı kaşığı": 7])
        XCTAssertEqual(TextParser.grams(TextParser.parseLine("1 yemek kaşığı bal"), food: bal), 21, accuracy: 0.01)
        let cay = food("Çay", kcal: 1, ["çay bardağı": 100])
        XCTAssertEqual(TextParser.grams(TextParser.parseLine("1 su bardağı çay"), food: cay), 200, accuracy: 0.01)
        let badem = food("Badem", kcal: 579, ["avuç": 30])
        XCTAssertFalse(TextParser.isExact(TextParser.parseLine("10 badem"), food: badem))
        XCTAssertTrue(TextParser.isExact(TextParser.parseLine("1 avuç badem"), food: badem))
        XCTAssertTrue(TextParser.isExact(TextParser.parseLine("30 g badem"), food: badem))
    }

    // fractions, "buçuk", thousands dot
    func testFractions() {
        let a = TextParser.parseLine("1/2 porsiyon pilav")
        XCTAssertEqual(a.qty, 0.5); XCTAssertEqual(a.unit, "porsiyon"); XCTAssertEqual(a.name, "pilav")
        XCTAssertEqual(TextParser.parseLine("½ porsiyon pilav").qty, 0.5)
        XCTAssertEqual(TextParser.parseLine("bir buçuk dilim ekmek").qty, 1.5)
        XCTAssertEqual(TextParser.parseLine("1 buçuk dilim ekmek").qty, 1.5)
        XCTAssertEqual(TextParser.parseLine("1.000 ml su").qty, 1000)
        XCTAssertEqual(TextParser.parseLine("1.5 dilim ekmek").qty, 1.5)
        XCTAssertEqual(TextParser.parseLine("1/0 porsiyon pilav").qty, 1, "sıfıra bölme olmasın")
    }

    // trailing amount, size words, "kaşık"
    func testTrailingQtyAndSizeWords() {
        let a = TextParser.parseLine("pilav 200 g")
        XCTAssertEqual(a.qty, 200); XCTAssertEqual(a.unit, "g"); XCTAssertEqual(a.name, "pilav")
        let b = TextParser.parseLine("yumurta 2 adet")
        XCTAssertEqual(b.qty, 2); XCTAssertEqual(b.unit, "adet"); XCTAssertEqual(b.name, "yumurta")
        XCTAssertEqual(TextParser.parseLine("1 küçük elma").name, "elma")
        XCTAssertEqual(TextParser.parseLine("1 orta boy muz").name, "muz")
        XCTAssertEqual(TextParser.parseLine("2 kaşık yoğurt").unit, "yemek kaşığı")
    }

    // serving keys independent of case and accents
    func testPortionKeysNormalized() {
        let f = food("Ev köftesi", ["Adet": 30, "Su Bardağı": 180])
        XCTAssertEqual(TextParser.grams(TextParser.parseLine("2 ev köftesi"), food: f), 60)
        XCTAssertEqual(TextParser.grams(TextParser.parseLine("1 su bardağı ev köftesi"), food: f), 180)
    }

    func testNegativeAndZero() {
        XCTAssertEqual(TextParser.parseLine("0 yumurta").qty, 0)
        XCTAssertEqual(TextParser.grams(TextParser.parseLine("0 yumurta"), food: food("Yumurta", ["adet": 55])), 0)
        XCTAssertGreaterThanOrEqual(TextParser.parseLine("-3 yumurta").qty, 0)
    }

    // Open Food Facts data validation
    func testOFFItemSanity() {
        XCTAssertNil(OpenFoodFacts.item(["code": "5", "nutriments": ["energy-kcal_100g": 400, "proteins_100g": 250, "carbohydrates_100g": 10, "fat_100g": 5]]))
        let kjAsKcal = OpenFoodFacts.item(["code": "6", "nutriments": ["energy-kcal_100g": 1674, "energy_100g": 1674, "proteins_100g": 10, "carbohydrates_100g": 70, "fat_100g": 5]])
        XCTAssertEqual(kjAsKcal?.per100.kcal ?? 0, 400, accuracy: 1)
        let a = OpenFoodFacts.item(["product_name": "A", "nutriments": ["energy-kcal_100g": 50, "fat_100g": 1]])
        let b = OpenFoodFacts.item(["product_name": "B", "nutriments": ["energy-kcal_100g": 60, "fat_100g": 1]])
        XCTAssertNotNil(a); XCTAssertNotEqual(a?.id, b?.id)
    }
}

final class RobustnessQATests: XCTestCase {
    // broken numbers must not crash
    func testOutOfRangeNumbersFallBack() throws {
        let json = #"{"id":"e","name":"X","sets":1e30,"reps":-1e300,"rest":"90,5"}"#
        let e = try JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
        XCTAssertEqual(e.sets, 3)
        XCTAssertEqual(e.rest, 90)
        XCTAssertNil(safeInt(.nan)); XCTAssertNil(safeInt(.infinity)); XCTAssertNil(safeInt(1e20)); XCTAssertEqual(safeInt(42.9), 42)
    }

    func testCorruptBackupNumbers() throws {
        let json = #"{"app":"gympaper","db":{"log":{"2026-10-20":{"water":"NaN","steps":1e40,"entries":[]}},"recipes":[{"id":"r","name":"X","servings":"inf","items":[]}]}}"#
        let b = try PWABackup.parse(Data(json.utf8))
        XCTAssertEqual(b.days.first?.water, 0)
        XCTAssertEqual(b.days.first?.steps, 0)
        XCTAssertEqual(b.recipes.first?.servings, 1)
    }

    func testDayKeyEdges() {
        XCTAssertEqual(DayKey.shift("2028-02-28", days: 1), "2028-02-29")
        XCTAssertEqual(DayKey.shift("2026-12-31", days: 1), "2027-01-01")
        XCTAssertEqual(DayKey.shift("2026-03-29", days: 1), "2026-03-30")
        XCTAssertNil(DayKey.date("2026-10"))
    }
}

final class WidgetQATests: XCTestCase {
    private func tmp() -> SharedStore {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return SharedStore(dir: d)
    }

    // a low background Health step count must not overwrite a higher manual value
    func testStepsNeverDecreaseWithinDay() {
        let st = tmp()
        var s = WidgetSnapshot.placeholder; s.date = "2026-10-25"; s.stepsRaw = 10_000
        st.write(s)
        XCTAssertNil(st.setSteps(3_000, day: "2026-10-25"))
        XCTAssertEqual(st.read()?.steps, 10_000)
        st.setSteps(12_000, day: "2026-10-25")
        XCTAssertEqual(st.read()?.steps, 12_000)
        st.setSteps(500, day: "2026-10-26")          // a new day starts from zero
        XCTAssertEqual(st.read()?.steps, 500)
    }

    func testWriteSanitizesNonFiniteNumbers() {
        let st = tmp()
        var s = WidgetSnapshot.placeholder
        s.kcalTarget = .nan; s.kcalActive = .infinity
        st.write(s)
        XCTAssertNotNil(st.read())
        XCTAssertEqual(st.read()?.kcalTarget, 0); XCTAssertEqual(st.read()?.kcalActive, 0)
    }
}

final class NormQATests: XCTestCase {
    func testAccentsAndNonLatin() {
        XCTAssertEqual(TextNorm.norm("Crème brûlée"), "creme brulee")
        XCTAssertEqual(TextNorm.norm("Çiğ Köfte, İçli"), "cig kofte icli")
        XCTAssertNotEqual(TextNorm.norm("Жим лёжа"), TextNorm.norm("Присед"))
        XCTAssertFalse(TextNorm.norm("Жим лёжа").isEmpty)
    }
    func testWordNumberSplit() {
        XCTAssertEqual(TextParser.split("iki yumurta bir dilim ekmek"), ["iki yumurta", "bir dilim ekmek"])
        XCTAssertEqual(TextParser.split("yarım ekmek 2 yumurta"), ["yarım ekmek", "2 yumurta"])
        XCTAssertEqual(TextParser.split("2 yumurta 1 dilim ekmek"), ["2 yumurta", "1 dilim ekmek"])
        XCTAssertEqual(TextParser.split("sütlü kahve"), ["sütlü kahve"])
    }
}

// MARK: - Intermittent fasting

final class FastingTests: XCTestCase {
    private func at(_ key: String, _ h: Int, _ m: Int = 0) -> Date {
        DayKey.calendar.date(bySettingHour: h, minute: m, second: 0, of: DayKey.date(key)!)!
    }

    func testOvernightFast() {
        let p = FastPlan(startMin: 20 * 60, hours: 16)
        // Oct 26 08:00 → the fast that started Oct 25 20:00 is still running and ends at 12:00
        guard case let .fasting(s, e, k) = p.phase(at: at("2026-10-26", 8)) else { return XCTFail("oruçta olmalı") }
        XCTAssertEqual(k, "2026-10-25")
        XCTAssertEqual(s, at("2026-10-25", 20))
        XCTAssertEqual(e, at("2026-10-26", 12))
    }

    func testEatingWindow() {
        let p = FastPlan(startMin: 20 * 60, hours: 16)
        guard case let .eating(since, next, fk) = p.phase(at: at("2026-10-26", 15)) else { return XCTFail("yeme penceresi olmalı") }
        XCTAssertEqual(since, at("2026-10-26", 12))
        XCTAssertEqual(next, at("2026-10-26", 20))
        XCTAssertEqual(fk, "2026-10-25")
    }

    func testEarlyEndAndSkip() {
        var p = FastPlan(startMin: 20 * 60, hours: 16)
        p.endedAt["2026-10-25"] = at("2026-10-26", 9)
        guard case .eating = p.phase(at: at("2026-10-26", 10)) else { return XCTFail("erken bitti") }
        XCTAssertEqual(p.completion(of: "2026-10-25", now: at("2026-10-26", 10))!, 13.0 / 16.0, accuracy: 0.001)
        p.skipped.insert("2026-10-26")
        guard case let .eating(_, next, _) = p.phase(at: at("2026-10-26", 21)) else { return XCTFail("atlandı → yeme") }
        XCTAssertEqual(next, at("2026-10-27", 20))
    }

    func testEndEarlyShiftsNextFast() {
        // 16:8 (20:00 → 12:00). Ended Oct 26 at 10:00: eating window 10:00–18:00, that day's fast starts at 18:00
        var p = FastPlan(startMin: 20 * 60, hours: 16)
        p.endEarly("2026-10-25", at: at("2026-10-26", 10))
        guard case let .eating(since, next, _) = p.phase(at: at("2026-10-26", 10, 1)) else { return XCTFail("yeme aralığı") }
        XCTAssertEqual(since, at("2026-10-26", 10))
        XCTAssertEqual(next, at("2026-10-26", 18))
        guard case let .fasting(s, e, k) = p.phase(at: at("2026-10-26", 19)) else { return XCTFail("öne çekilen oruç") }
        XCTAssertEqual(k, "2026-10-26"); XCTAssertEqual(s, at("2026-10-26", 18)); XCTAssertEqual(e, at("2026-10-27", 10))
        // the next day the schedule is back to normal
        XCTAssertEqual(p.start(of: "2026-10-27"), at("2026-10-27", 20))
        let d = try! JSONEncoder().encode(p)
        XCTAssertEqual(try! JSONDecoder().decode(FastPlan.self, from: d), p)
    }

    func testDaytimeFast() {
        // 18-hour fast starting at 08:00 (ends 02:00 the next day)
        let p = FastPlan(startMin: 8 * 60, hours: 18)
        guard case .fasting = p.phase(at: at("2026-10-27", 1)) else { return XCTFail("gece de oruç") }
        guard case let .eating(_, next, _) = p.phase(at: at("2026-10-27", 3)) else { return XCTFail("yeme") }
        XCTAssertEqual(next, at("2026-10-27", 8))
    }

    func testCodableRoundTrip() throws {
        var p = FastPlan(startMin: 19 * 60 + 30, hours: 18)
        p.skipped = ["2026-10-20"]; p.endedAt = ["2026-10-21": at("2026-10-22", 10)]
        let d = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(FastPlan.self, from: d), p)
        XCTAssertEqual(p.startText, "19:30"); XCTAssertEqual(p.endText, "13:30")
    }
}
