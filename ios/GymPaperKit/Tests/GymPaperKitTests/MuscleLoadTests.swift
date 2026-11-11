import XCTest
@testable import GymPaperKit

/// Muscle map and weight suggestion
final class MuscleLoadTests: XCTestCase {
    typealias M = MuscleLoad

    func testPrimaryOneSecondaryHalf() {
        let e = M.load([.init(name: "Barbell Bench Press", muscle: "Göğüs", sets: 3)], scope: .workout)
        let v = Dictionary(uniqueKeysWithValues: e.map { ($0.muscle, $0.sets) })
        XCTAssertEqual(v["Göğüs"], 3); XCTAssertEqual(v["Triceps"], 1.5); XCTAssertEqual(v["Omuz"], 1.5)
        XCTAssertEqual(e.first?.muscle, "Göğüs")
    }
    func testRowsHitBiceps() {
        let v = Dictionary(uniqueKeysWithValues: M.load([.init(name: "Lat Pulldown", muscle: "Sırt", sets: 4)], scope: .workout).map { ($0.muscle, $0.sets) })
        XCTAssertEqual(v["Sırt"], 4); XCTAssertEqual(v["Biceps"], 2)
    }
    func testIsolationNoSecondary() {
        XCTAssertEqual(M.secondary(name: "Leg Extension", muscle: "Bacak"), [])
        XCTAssertEqual(M.secondary(name: "Dumbbell Fly", muscle: "Göğüs"), ["Omuz"])
        XCTAssertEqual(M.secondary(name: "Back Squat", muscle: "Bacak"), ["Kalça"])
    }
    func testCardioIgnored() {
        XCTAssertTrue(M.load([.init(name: "Koşu", muscle: "Kardiyo", sets: 1)], scope: .workout).isEmpty)
    }
    func testLevels() {
        XCTAssertEqual(M.level(0, .workout), .none)
        XCTAssertEqual(M.level(1.5, .workout), .light)
        XCTAssertEqual(M.level(2, .workout), .moderate)
        XCTAssertEqual(M.level(3, .workout), .hard)
        XCTAssertEqual(M.level(5, .workout), .max)
        XCTAssertEqual(M.level(4, .week), .light)
        XCTAssertEqual(M.level(9, .week), .moderate)
        XCTAssertEqual(M.level(20, .week), .hard)
        XCTAssertEqual(M.level(22, .week), .max)
    }
    func testFormat() {
        XCTAssertEqual(M.format(0.5), "½"); XCTAssertEqual(M.format(1.5), "1½"); XCTAssertEqual(M.format(3), "3")
    }
    func testGapCore() {
        let e = M.load([.init(name: "Bench Press", muscle: "Göğüs", sets: 4), .init(name: "Lat Pulldown", muscle: "Sırt", sets: 3)], scope: .workout)
        XCTAssertEqual(M.gap(e, scope: .workout)?.muscle, "Karın")
    }
    func testGapOpposite() {
        let e = M.load([.init(name: "Bench Press", muscle: "Göğüs", sets: 4)], scope: .workout)
        XCTAssertEqual(M.gap(e, scope: .workout), .init(muscle: "Sırt", because: "Göğüs"))
    }
    func testWeekGap() {
        let e = M.load([.init(name: "Squat", muscle: "Bacak", sets: 8), .init(name: "Row", muscle: "Sırt", sets: 8), .init(name: "Bench", muscle: "Göğüs", sets: 8),
                        .init(name: "Shoulder Press", muscle: "Omuz", sets: 6), .init(name: "Hip Thrust", muscle: "Kalça", sets: 4), .init(name: "Plank", muscle: "Karın", sets: 3)], scope: .week)
        XCTAssertNil(M.gap(e, scope: .week, workouts: 1))
        XCTAssertEqual(M.gap(e, scope: .week, workouts: 3)?.muscle, "Baldır")
    }
    func testPick() {
        let lib: [ExerciseAlternatives.Candidate] = [.init(name: "Crunch", muscle: "Karın"), .init(name: "Plank", muscle: "Karın", unit: "sn")]
        XCTAssertEqual(M.pick(for: "Karın", library: lib)?.name, "Plank")
        XCTAssertEqual(M.pick(for: "Karın", library: lib, done: ["crunch"])?.name, "Crunch")
    }

    // MARK: Weight suggestion
    typealias P = Progression
    private func s(_ d: String, _ kg: Double, _ reps: [Int]) -> P.Session { .init(date: d, sets: reps.map { .init(kg: kg, reps: $0) }) }

    func testNeverBelowCurrent() {
        // the bug that suggested 35 while lifting 40
        let r = P.suggest(name: "Dumbbell Shoulder Press", history: [s("2026-11-01", 35, [10, 10, 9])], currentKg: 40)
        XCTAssertEqual(r?.kg, 40); XCTAssertEqual(r?.up, false)
    }
    func testThreeSessionsAt15Up() {
        let h = [s("2026-11-01", 20, [15, 15, 15]), s("2026-11-03", 20, [16, 15, 15]), s("2026-11-05", 20, [15, 15, 17])]
        let r = P.suggest(name: "Dumbbell Curl", history: h)
        XCTAssertEqual(r?.kg, 22); XCTAssertEqual(r?.reps, 8); XCTAssertEqual(r?.up, true)
        XCTAssertEqual(P.suggest(name: "Barbell Squat", history: h)?.kg, 22.5)
        XCTAssertEqual(P.suggest(name: "Leg Press", history: h)?.kg, 25)
    }
    func testTwoSessionsNotYet() {
        let h = [s("2026-11-01", 20, [12, 12, 12]), s("2026-11-03", 20, [15, 15, 15]), s("2026-11-05", 20, [15, 15, 15])]
        let r = P.suggest(name: "Dumbbell Curl", history: h)
        XCTAssertEqual(r?.kg, 20); XCTAssertEqual(r?.up, false); XCTAssertEqual(r?.streak, 2)
    }
    func testOneSetBelowBreaksStreak() {
        let h = [s("2026-11-01", 20, [15, 15, 15]), s("2026-11-03", 20, [15, 15, 15]), s("2026-11-05", 20, [15, 15, 14])]
        XCTAssertEqual(P.suggest(name: "Dumbbell Curl", history: h)?.up, false)
    }
    func testNewWeightResetsStreak() {
        // 3× 15+ at 20 kg, then the user moved to 22: the increase isn't suggested again
        let h = [s("2026-11-01", 20, [15, 15]), s("2026-11-03", 20, [15, 15]), s("2026-11-05", 20, [15, 15])]
        let r = P.suggest(name: "Dumbbell Curl", history: h, currentKg: 22)
        XCTAssertEqual(r?.kg, 22); XCTAssertEqual(r?.up, false); XCTAssertEqual(r?.streak, 0)
    }
    func testBodyweightNoIncrease() {
        let h = [s("a", 10, [15]), s("b", 10, [15]), s("c", 10, [15])]
        XCTAssertEqual(P.suggest(name: "Push Up", history: h)?.up, false)
        XCTAssertNil(P.suggest(name: "Push Up", history: []))
    }

    // MARK: Assisted (less weight is harder)
    func testAssistedDetection() {
        XCTAssertTrue(P.isAssisted("Machine Assisted Pull Up"))
        XCTAssertTrue(P.isAssisted("Makine destekli barfiks"))
        XCTAssertTrue(P.isAssisted("Assisted Dip"))
        XCTAssertFalse(P.isAssisted("Göğüs destekli kürek"))
        XCTAssertFalse(P.isAssisted("Chest Supported Row"))
        XCTAssertFalse(P.isAssisted("Kettlebell Assisted Bulgarian Split Squat"))
        XCTAssertFalse(P.isAssisted("Lat Pulldown"))
    }
    func testAssistedNeverMoreHelp() {
        // 40 → 50 kg of help is a step back: the suggestion stays at 40
        let r = P.suggest(name: "Machine Assisted Pull Up", history: [s("a", 40, [10, 10])], currentKg: 50)
        XCTAssertEqual(r?.kg, 40); XCTAssertEqual(r?.up, false); XCTAssertEqual(r?.assisted, true)
    }
    func testAssistedThreeSessionsStepsDown() {
        let h = [s("a", 40, [15, 15]), s("b", 40, [15, 16]), s("c", 40, [15, 15])]
        let r = P.suggest(name: "Machine Assisted Pull Up", history: h)
        XCTAssertEqual(r?.kg, 35); XCTAssertEqual(r?.reps, 8); XCTAssertEqual(r?.up, true)
    }
    func testAssistedLoad() {
        XCTAssertEqual(P.load(name: "Machine Assisted Pull Up", kg: 40, bodyweight: 90), 50)
        XCTAssertEqual(P.load(name: "Machine Assisted Pull Up", kg: 100, bodyweight: 90), 0)
        XCTAssertEqual(P.load(name: "Lat Pulldown", kg: 40, bodyweight: 90), 40)
    }

    /// A leg day without core is not flagged when core is trained on another day of the week
    func testWorkoutGapRespectsWeek() {
        let day = M.load([.init(name: "Squat", muscle: "Bacak", sets: 4), .init(name: "Leg Press", muscle: "Bacak", sets: 3)], scope: .workout)
        XCTAssertEqual(M.gap(day, scope: .workout)?.muscle, "Karın")
        let week = M.load([.init(name: "Squat", muscle: "Bacak", sets: 4), .init(name: "Hip Thrust", muscle: "Kalça", sets: 3),
                           .init(name: "Plank", muscle: "Karın", sets: 3)], scope: .week)
        XCTAssertNil(M.gap(day, scope: .workout, week: week))
    }
}
