import XCTest
@testable import GymPaperKit

final class DayMergeTests: XCTestCase {
    func testEntriesUnionById() {
        let m = Macros(kcal: 100, p: 1, c: 1, f: 1)
        let a = [FoodEntry(id: "1", meal: .ogle, name: "A", foodName: "A", g: 100, per100: m)]
        let b = [FoodEntry(id: "1", meal: .ogle, name: "A2", foodName: "A", g: 50, per100: m),
                 FoodEntry(id: "2", meal: .aksam, name: "B", foodName: "B", g: 80, per100: m)]
        let r = DayMerge.entries(a, b)
        XCTAssertEqual(r.map(\.id), ["1", "2"])
        XCTAssertEqual(r[0].name, "A")
    }

    func testSetsPreferDone() {
        let a = ["x": [SetLog(kg: 50, reps: 8, done: false)]]
        let b = ["x": [SetLog(kg: 60, reps: 6, done: true), SetLog(kg: 60, reps: 6, done: true)], "y": [SetLog(done: true)]]
        let r = DayMerge.sets(a, b)
        XCTAssertEqual(r["x"]?.count, 2)
        XCTAssertEqual(r["x"]?[0].kg, 60)
        XCTAssertEqual(r["y"]?.count, 1)
    }

    func testFlagsOr() {
        XCTAssertEqual(DayMerge.flags(["a": false, "b": true], ["a": true]), ["a": true, "b": true])
    }
}
