import XCTest
@testable import PlannerCore

final class TimeMathTests: XCTestCase {

    func testOvernightIntervalEndsNextDay() {
        let iv = DayMath.interval(on: T.date(28), from: TimeOfDay(hour: 21), to: TimeOfDay(hour: 7), calendar: T.cal)
        XCTAssertEqual(iv.start, T.date(28, 21))
        XCTAssertEqual(iv.end, T.date(29, 7))
        XCTAssertEqual(DayMath.minutes(iv), 10 * 60)
    }

    func testSameDayInterval() {
        let iv = DayMath.interval(on: T.date(28), from: TimeOfDay(hour: 14, minute: 52), to: TimeOfDay(hour: 17), calendar: T.cal)
        XCTAssertEqual(iv.start, T.date(28, 14, 52))
        XCTAssertEqual(iv.end, T.date(28, 17))
    }

    func testNormalizedIntervalFixesEndBeforeStart() {
        let iv = DayMath.normalizedInterval(start: T.date(28, 21), end: T.date(28, 7), calendar: T.cal)
        XCTAssertEqual(iv?.end, T.date(29, 7))
        XCTAssertNil(DayMath.normalizedInterval(start: T.date(28, 9), end: T.date(28, 9), calendar: T.cal))
    }

    func testDayIntervalAcrossDSTChange() {
        // 25.10.2026: Umstellung auf Winterzeit → 25-Stunden-Tag
        let iv = DayMath.dayInterval(containing: T.date(25, 12), calendar: T.cal)
        XCTAssertEqual(iv.duration, 25 * 3600)
        XCTAssertEqual(iv.end, T.date(26))
    }

    func testDayChangeNavigation() {
        let tomorrow = DayMath.addDays(1, to: T.date(28, 15), calendar: T.cal)
        XCTAssertEqual(tomorrow, T.date(29))
        let yesterday = DayMath.addDays(-1, to: T.date(28, 0, 30), calendar: T.cal)
        XCTAssertEqual(yesterday, T.date(27))
        // Monatswechsel
        XCTAssertEqual(DayMath.addDays(4, to: T.date(28), calendar: T.cal), T.date(1, month: 11))
    }

    func testOverlapsTreatsTouchingAsFree() {
        let a = DateInterval(start: T.date(28, 14), end: T.date(28, 15))
        let b = DateInterval(start: T.date(28, 15), end: T.date(28, 16))
        XCTAssertFalse(DayMath.overlaps(a, b))
        let c = DateInterval(start: T.date(28, 14, 30), end: T.date(28, 16))
        XCTAssertTrue(DayMath.overlaps(a, c))
    }

    func testSubtractAndMerge() {
        let window = DateInterval(start: T.date(28, 7), end: T.date(28, 21))
        let busy = [
            DateInterval(start: T.date(28, 8), end: T.date(28, 14)),
            DateInterval(start: T.date(28, 13), end: T.date(28, 15)),
            DateInterval(start: T.date(28, 20), end: T.date(28, 23))
        ]
        let free = DayMath.subtract(busy, from: window)
        XCTAssertEqual(free.count, 2)
        XCTAssertEqual(free[0], DateInterval(start: T.date(28, 7), end: T.date(28, 8)))
        XCTAssertEqual(free[1], DateInterval(start: T.date(28, 15), end: T.date(28, 20)))
    }

    func testRoundUpToGrid() {
        XCTAssertEqual(DayMath.roundUp(T.date(28, 14, 52), toMinutes: 5, calendar: T.cal), T.date(28, 14, 55))
        XCTAssertEqual(DayMath.roundUp(T.date(28, 15, 0), toMinutes: 5, calendar: T.cal), T.date(28, 15, 0))
        XCTAssertEqual(DayMath.roundUp(T.date(28, 15, 1), toMinutes: 5, calendar: T.cal), T.date(28, 15, 5))
    }

    func testDurationText() {
        XCTAssertEqual(DurationText.exact(135), "2 Std. 15 Min.")
        XCTAssertEqual(DurationText.exact(45), "45 Min.")
        XCTAssertEqual(DurationText.approximate(127), "2 Std.")
        XCTAssertEqual(DurationText.approximate(97), "1,5 Std.")
        XCTAssertEqual(DurationText.approximate(150), "2,5 Std.")
    }

    func testTimeOfDayNormalizes() {
        XCTAssertEqual(TimeOfDay(hour: 24).formatted, "00:00")
        XCTAssertEqual(TimeOfDay(minutesSinceMidnight: -30).formatted, "23:30")
    }
}
