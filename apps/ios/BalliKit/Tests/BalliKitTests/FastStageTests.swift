import XCTest
@testable import BalliKit

/// Oruç evreleri (RA-07)
final class FastStageTests: XCTestCase {
    func testStageAtElapsed() {
        XCTAssertEqual(FastStage.at(elapsed: 0), .digest)
        XCTAssertEqual(FastStage.at(elapsed: -60), .digest)
        XCTAssertEqual(FastStage.at(elapsed: 4 * 3600), .sugar)
        XCTAssertEqual(FastStage.at(elapsed: 13 * 3600), .fatBurn)
        XCTAssertEqual(FastStage.at(elapsed: 20 * 3600), .ketosis)
    }

    func testReachableBy16h() {
        // 16:8'de ketozis tam bitişte başlar → izde yok
        XCTAssertEqual(FastStage.reachable(duration: 16 * 3600), [.digest, .sugar, .fatBurn])
        XCTAssertEqual(FastStage.reachable(duration: 18 * 3600), FastStage.allCases)
        XCTAssertEqual(FastStage.reachable(duration: 3 * 3600), [.digest])
    }

    func testSegmentsCoverWholeFast() {
        let seg = FastStage.segments(duration: 16 * 3600)
        XCTAssertEqual(seg.map(\.stage), [.digest, .sugar, .fatBurn])
        XCTAssertEqual(seg.first!.from, 0)
        XCTAssertEqual(seg.last!.to, 1)
        XCTAssertEqual(seg[1].from, 0.25, accuracy: 0.0001)
        XCTAssertEqual(seg[2].from, 0.75, accuracy: 0.0001)
        for (a, b) in zip(seg, seg.dropFirst()) { XCTAssertEqual(a.to, b.from, accuracy: 0.0001) }
    }
}
