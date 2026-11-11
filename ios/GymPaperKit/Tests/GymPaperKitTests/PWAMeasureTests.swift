import XCTest
@testable import GymPaperKit

/// Web measurement keys are Turkish
final class PWAMeasureTests: XCTestCase {
    private func parse(_ measures: String) throws -> [PWABackup.Measure] {
        try PWABackup.parse(Data(#"{"app":"gympaper","db":{"measures":\#(measures)}}"#.utf8)).measures
    }

    func testTurkishKeys() throws {
        let m = try parse(#"[{"id":"a","date":"2026-10-01","kg":98.4,"bel":"92,5","kalca":104,"gogus":110,"sagkol":38,"solkol":37.5,"bacak":60,"omuz":120}]"#)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].kg, 98.4)
        XCTAssertEqual(m[0].waist, 92.5)
        XCTAssertEqual(m[0].hip, 104)
        XCTAssertEqual(m[0].chest, 110)
        XCTAssertEqual(m[0].rightArm, 38)
        XCTAssertEqual(m[0].leftArm, 37.5)
        XCTAssertEqual(m[0].thigh, 60)
        XCTAssertEqual(m[0].shoulder, 120)
    }

    func testWaistFallbackAndBelWins() throws {
        let m = try parse(#"[{"date":"2026-10-01","waist":90},{"date":"2026-10-02","bel":88,"waist":91}]"#)
        XCTAssertEqual(m.map(\.waist), [90, 88])
        XCTAssertNil(m[0].kg)
    }

    func testSkipsEmptyMeasures() throws {
        let m = try parse(#"[{"id":"x","date":"2026-10-01"},{"date":"2026-10-02","kg":0,"bel":""},{"date":"2026-10-03","omuz":118}]"#)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].date, "2026-10-03")
        XCTAssertEqual(m[0].shoulder, 118)
        XCTAssertFalse(m[0].isEmpty)
    }
}
