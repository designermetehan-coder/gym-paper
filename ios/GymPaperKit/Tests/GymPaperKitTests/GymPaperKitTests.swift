import XCTest
@testable import GymPaperKit

final class CalorieEngineTests: XCTestCase {
    let mete = BodyProfile(weightKg: 110, heightCm: 180, age: 33, sex: .male)

    func testBMRMifflin() {
        // 10*110 + 6.25*180 - 5*33 + 5 = 1100 + 1125 - 165 + 5 = 2065
        XCTAssertEqual(CalorieEngine.bmr(mete), 2065, accuracy: 0.01)
        let f = BodyProfile(weightKg: 65, heightCm: 165, age: 30, sex: .female)
        // 650 + 1031.25 - 150 - 161 = 1370.25
        XCTAssertEqual(CalorieEngine.bmr(f), 1370.25, accuracy: 0.01)
    }

    func testTDEE() {
        XCTAssertEqual(CalorieEngine.tdee(mete, activity: .moderate), 2065 * 1.55, accuracy: 0.01)
        XCTAssertEqual(CalorieEngine.tdee(mete, activeKcal: 500), 2065 * 1.1 + 500, accuracy: 0.01)
        XCTAssertEqual(CalorieEngine.tdee(mete, activeKcal: -20), 2065 * 1.1, accuracy: 0.01)
    }

    func testDailyTargetNeverBelowBMR() {
        // 0.5 kg/week = 550 kcal/day deficit
        XCTAssertEqual(CalorieEngine.dailyTarget(tdee: 3000, bmr: 2065, weeklyLossKg: 0.5), 2450)
        XCTAssertEqual(CalorieEngine.dailyTarget(tdee: 2200, bmr: 2065, weeklyLossKg: 1), 2065)
    }

    func testStepsAndWorkout() {
        XCTAssertEqual(CalorieEngine.stepsKcal(steps: 10_000, weightKg: 70), 399, accuracy: 1)
        // 60 dk, 100 kg, MET 5 → 5*3.5*100/200*60 = 525
        XCTAssertEqual(CalorieEngine.workoutKcal(minutes: 60, weightKg: 100, met: 5), 420, accuracy: 0.01)
        // 60 min, 88 kg, default session → ~231 kcal (close to Apple Watch active energy)
        XCTAssertEqual(CalorieEngine.workoutKcal(minutes: 60, weightKg: 88), 231, accuracy: 0.5)
        XCTAssertEqual(CalorieEngine.estimatedMinutes(sets: [(rest: 80, count: 3)]), 6, accuracy: 0.01)
        // 2 × 15 min cardio (no rest) + 4 × (40 s + 40 s) = 30 + 5.33
        let blocks = [Block(single: Exercise(name: "Bike", sets: 1, reps: 15, unit: "dk", rest: 0)),
                      Block(single: Exercise(name: "Leg Press", sets: 4, reps: 10, rest: 40)),
                      Block(single: Exercise(name: "Walk", sets: 1, reps: 15, unit: "dk", rest: 0))]
        XCTAssertEqual(CalorieEngine.estimatedMinutes(sets: blocks.restProfile), 35.33, accuracy: 0.01)
    }
}

final class ScheduleTests: XCTestCase {
    func testWeekday() {
        XCTAssertEqual(DayKey.weekday("2026-10-26"), 0) // Pazartesi
        XCTAssertEqual(DayKey.weekday("2026-10-25"), 6) // Pazar
        XCTAssertEqual(DayKey.weekDate("2026-10-24", dow: 0, weekOffset: 1), "2026-10-26")
    }

    func testScheduleHistory() {
        var h = [ScheduleEntry(from: "0000-01-01", days: ["0": "A", "1": nil])]
        Schedule.set(&h, from: "2026-10-26", dow: 0, programId: "B")
        XCTAssertEqual(Schedule.programId(h, date: "2026-10-19"), "A")
        XCTAssertEqual(Schedule.programId(h, date: "2026-10-26"), "B")
        XCTAssertEqual(Schedule.programId(h, date: "2026-11-02"), "B")
        XCTAssertNil(Schedule.programId(h, date: "2026-10-27"))
    }
}

final class BackupTests: XCTestCase {
    func testParsePWABackup() throws {
        let json = """
        {"app":"gympaper","db":{"profile":{"name":"Alex","startKg":125},
         "targets":{"kcal":1800,"p":140,"goals":[95,90],"meals":["kahvalti","aksam"]},
         "programs":[{"id":"p1","name":"Üst","blocks":[{"id":"b1","kind":"single","ex":{"id":"e1","name":"Bench","sets":"4","reps":8,"unit":"tekrar","rest":90,"kg":"42,5"}}]},
                     {"id":"t","name":"geçici","temp":true,"blocks":[]}],
         "scheduleHist":[{"from":"0000-01-01","days":{"0":"p1","1":null}}],
         "log":{"2026-10-20":{"water":1000,"entries":[{"id":"x","meal":"aksam","name":"100 g Tavuk","foodName":"Tavuk","g":100,"per100":{"kcal":165,"p":31,"c":0,"f":3.6}}],
                              "sets":{"e1":[{"kg":"40","reps":"8","done":true},null]}}},
         "measures":[{"id":"m1","date":"2026-10-01","kg":110},{"id":"m2","date":"","kg":1}],
         "myFoods":[{"id":"f1","name":"Yoğurt","per100":{"kcal":60,"p":4,"c":5,"f":3},"barcode":"869"}],
         "recipes":[{"id":"r1","name":"Menemen","servings":2,"items":[{"name":"Yumurta","g":120,"per100":{"kcal":155,"p":13,"c":1,"f":11}}]}]}}
        """
        let b = try PWABackup.parse(Data(json.utf8))
        XCTAssertEqual(b.profile.name, "Alex")
        XCTAssertEqual(b.targets.meals, [.kahvalti, .aksam])
        XCTAssertEqual(b.programs.count, 1)
        XCTAssertEqual(b.programs[0].blocks[0].ex?.sets, 4)
        XCTAssertEqual(b.programs[0].blocks[0].ex?.kg, 42.5)
        XCTAssertEqual(Schedule.programId(b.schedule, date: "2026-10-26"), "p1")
        XCTAssertEqual(b.days.first?.entries.first?.macros.kcal ?? 0, 165, accuracy: 0.01)
        XCTAssertEqual(b.days.first?.sets["e1"]?.count, 2)
        XCTAssertEqual(b.days.first?.sets["e1"]?.first?.kg, 40)
        XCTAssertEqual(b.measures.count, 1)
        XCTAssertEqual(b.foods.first?.barcode, "869")
        XCTAssertEqual(b.recipes.first?.items.count, 1)
    }

    func testRejectsForeignFile() {
        XCTAssertThrowsError(try PWABackup.parse(Data("{\"app\":\"x\"}".utf8)))
        XCTAssertThrowsError(try PWABackup.parse(Data("nope".utf8)))
    }
}
