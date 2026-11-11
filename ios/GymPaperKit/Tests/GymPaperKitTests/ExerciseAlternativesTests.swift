import XCTest
@testable import GymPaperKit

/// Machine taken → alternative exercise
final class ExerciseAlternativesTests: XCTestCase {
    private let lib: [ExerciseAlternatives.Candidate] = [
        .init(name: "Barbell Bench Press", alias: "Göğüs pres (bar)", muscle: "Göğüs"),
        .init(name: "Incline Barbell Bench Press", muscle: "Göğüs"),
        .init(name: "Dumbbell Bench Press", alias: "Dambıl göğüs pres", muscle: "Göğüs"),
        .init(name: "Machine Chest Press", muscle: "Göğüs"),
        .init(name: "Cable Chest Press", muscle: "Göğüs"),
        .init(name: "Push Up", alias: "Şınav", muscle: "Göğüs"),
        .init(name: "Lat Pulldown", muscle: "Sırt"),
        .init(name: "Plank", muscle: "Karın", unit: "sn"),
    ]

    func testEquipment() {
        typealias E = ExerciseAlternatives
        XCTAssertEqual(E.equipment("Barbell Bench Press"), .barbell)
        XCTAssertEqual(E.equipment("Göğüs pres (bar)"), .barbell)
        XCTAssertEqual(E.equipment("Barfiks"), .bodyweight, "bar ≠ barfiks")
        XCTAssertEqual(E.equipment("Dumbbell Fly"), .dumbbell)
        XCTAssertEqual(E.equipment("Lat Pulldown"), .cable)
        XCTAssertEqual(E.equipment("Machine Chest Press"), .machine)
        XCTAssertEqual(E.equipment("Pull-ups"), .bodyweight)
    }

    func testSameRegionDifferentEquipmentFirst() {
        let r = ExerciseAlternatives.rank(current: "Barbell Bench Press", muscle: "Göğüs", unit: "tekrar", library: lib, limit: 4)
        XCTAssertEqual(r.count, 4)
        XCTAssertTrue(r.allSatisfy { $0.muscle == "Göğüs" })
        XCTAssertFalse(r.contains { $0.name == "Barbell Bench Press" }, "kendisi önerilmez")
        XCTAssertFalse(r.prefix(3).contains { $0.equipment == .barbell }, "dolu olan alet ilk sıralarda olmaz")
    }

    func testTurkishNameFindsRegionAndHistoryFirst() {
        let r = ExerciseAlternatives.rank(current: "Göğüs pres (bar)", muscle: "", unit: "tekrar", library: lib,
                                          done: [TextNorm.norm("Push Up")])
        XCTAssertEqual(r.first?.name, "Push Up", "daha önce yapılan üstte")
        XCTAssertFalse(r.contains { $0.name == "Barbell Bench Press" }, "Türkçe adla da kendisi çıkmaz")
    }

    func testExcludesProgramExercises() {
        let r = ExerciseAlternatives.rank(current: "Barbell Bench Press", muscle: "Göğüs", unit: "tekrar", library: lib,
                                          exclude: [TextNorm.norm("Dumbbell Bench Press")])
        XCTAssertFalse(r.contains { $0.name == "Dumbbell Bench Press" })
    }

    func testDayCopyPidIsStable() {
        XCTAssertEqual(ExerciseAlternatives.dayCopyPid("p1", date: "2026-11-08"), "p1@2026-11-08")
        XCTAssertEqual(ExerciseAlternatives.dayCopyPid("p1@2026-11-08", date: "2026-11-08"), "p1@2026-11-08")
    }

    func testSwapKeepsDoneSetsAndPlan() throws {
        let bench = Exercise(id: "e1", name: "Barbell Bench Press", sets: 4, reps: 8, rest: 90, kg: 60, muscle: "Göğüs")
        let blocks = [Block(id: "b1", single: bench), Block(id: "b2", single: Exercise(id: "e2", name: "Plank", sets: 3, reps: 45, unit: "sn"))]
        // with no sets done it changes in place
        let a = ExerciseAlternatives.swap(blocks, eid: "e1", doneSets: 0, to: "Dumbbell Bench Press", muscle: "Göğüs")
        XCTAssertEqual(a.count, 2)
        let n = try XCTUnwrap(a[0].ex)
        XCTAssertEqual(n.name, "Dumbbell Bench Press"); XCTAssertEqual(n.sets, 4); XCTAssertEqual(n.reps, 8); XCTAssertEqual(n.rest, 90)
        XCTAssertNil(n.kg, "kilo boş başlar")
        XCTAssertEqual(n.id, ExerciseAlternatives.swappedId("e1", name: "Dumbbell Bench Press"), "iki cihazda aynı kimlik")
        // with 1 set done the old one keeps 1 set and the new one follows with 3
        let b = ExerciseAlternatives.swap(blocks, eid: "e1", doneSets: 1, to: "Dumbbell Bench Press", muscle: "Göğüs")
        XCTAssertEqual(b.count, 3)
        XCTAssertEqual(b[0].ex?.id, "e1"); XCTAssertEqual(b[0].ex?.sets, 1)
        XCTAssertEqual(b[1].ex?.name, "Dumbbell Bench Press"); XCTAssertEqual(b[1].ex?.sets, 3)
        XCTAssertEqual(b[2].ex?.id, "e2")
    }

    func testSwapInSuperset() {
        let s = Block(id: "s", superset: [Exercise(id: "x", name: "Curl", sets: 3, reps: 12), Exercise(id: "y", name: "Triceps Pushdown", sets: 3, reps: 15)], rounds: 3, rest: 60)
        let r = ExerciseAlternatives.swap([s], eid: "y", doneSets: 1, to: "Bench Dips", muscle: "Triceps")
        XCTAssertEqual(r.count, 1); XCTAssertEqual(r[0].rounds, 3)
        XCTAssertEqual(r[0].exs.map(\.name), ["Curl", "Bench Dips"])
    }
}
