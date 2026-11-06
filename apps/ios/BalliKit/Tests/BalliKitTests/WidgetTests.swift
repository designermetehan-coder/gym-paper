import XCTest
@testable import BalliKit

final class WidgetTests: XCTestCase {
    private func tmp() -> SharedStore {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return SharedStore(dir: d)
    }

    func testRoundTripKeepsRestDays() {
        let st = tmp()
        var s = WidgetSnapshot.placeholder
        s.workouts["2026-10-25"] = .some(nil)
        st.write(s)
        let r = st.read()
        XCTAssertEqual(r, s)
        let known: WidgetWorkout?? = r!.workout(on: "2026-10-25")
        let unknown: WidgetWorkout?? = r!.workout(on: "2030-01-01")
        XCTAssertTrue(known != nil)                           // biliniyor
        if case .some(.some) = known { XCTFail("dinlenme olmalı") }
        XCTAssertTrue(unknown == nil)                         // bilinmiyor
    }

    func testNewDayResetsCounters() {
        let s = WidgetSnapshot.placeholder.on("2099-01-01")
        XCTAssertEqual(s.waterMl, 0); XCTAssertEqual(s.kcalEaten, 0); XCTAssertEqual(s.kcalTarget, 2000)
    }

    func testAddWaterQueuesPending() {
        let st = tmp()
        var s = WidgetSnapshot.placeholder; s.date = "2026-10-24"; s.waterMl = 500; s.waterStepMl = 250
        st.write(s)
        st.addWater(day: "2026-10-24"); st.addWater(day: "2026-10-24")
        XCTAssertEqual(st.read()?.waterMl, 1000)
        XCTAssertEqual(st.takePending(), ["2026-10-24": 500])
        XCTAssertEqual(st.pending(), [:])
    }

    func testNoGroupIsNoop() {
        let st = SharedStore(dir: nil)
        XCTAssertNil(st.addWater())
        XCTAssertNil(st.read())
    }

    func testOldJsonWithoutStepsDecodes() throws {
        var s = WidgetSnapshot.placeholder; s.stepsRaw = nil; s.stepGoalRaw = nil; s.week = nil
        let d = try JSONEncoder().encode(s)
        let r = try JSONDecoder().decode(WidgetSnapshot.self, from: d)
        XCTAssertEqual(r.steps, 0); XCTAssertEqual(r.stepGoal, 10_000); XCTAssertNil(r.week)
    }

    func testSetStepsUpdatesOnlySteps() {
        let st = tmp()
        var s = WidgetSnapshot.placeholder; s.date = "2026-10-24"
        st.write(s)
        st.setSteps(8123, day: "2026-10-24")
        XCTAssertEqual(st.read()?.steps, 8123)
        XCTAssertEqual(st.read()?.waterMl, s.waterMl)
        XCTAssertNil(st.setSteps(8123, day: "2026-10-24"))     // değişmedi → yazmaz
    }

    func testPlaceholderWeekHasSevenDays() {
        XCTAssertEqual(WidgetSnapshot.placeholder.week?.count, 7)
    }
}
