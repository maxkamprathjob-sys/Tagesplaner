import XCTest
@testable import PlannerCore

final class ParserTests: XCTestCase {

    private let parser = NaturalLanguageParser(calendar: T.cal)
    private let now = T.date(28, 10)   // Mittwoch, 28.10.2026, 10:00

    func testTomorrowTwoHoursLearning() {
        let p = parser.parse("Ich muss morgen 2 Stunden lernen.", now: now)
        XCTAssertEqual(p.title, "Lernen")
        XCTAssertEqual(p.day, T.date(29))
        XCTAssertEqual(p.durationMinutes, 120)
        XCTAssertNil(p.startTime)
    }

    func testUniFromEightToFourteen() {
        let p = parser.parse("Ich habe morgen um 8 Uhr Uni bis 14 Uhr.", now: now)
        XCTAssertEqual(p.title, "Uni")
        XCTAssertEqual(p.day, T.date(29))
        XCTAssertEqual(p.startTime, TimeOfDay(hour: 8))
        XCTAssertEqual(p.endTime, TimeOfDay(hour: 14))
        XCTAssertNil(p.deadline)
        XCTAssertEqual(p.interval(defaultDay: T.date(28), calendar: T.cal),
                       DateInterval(start: T.date(29, 8), end: T.date(29, 14)))
    }

    func testVonBisRange() {
        let p = parser.parse("Ich habe morgen von 8 bis 14 Uhr Uni", now: now)
        XCTAssertEqual(p.title, "Uni")
        XCTAssertEqual(p.startTime, TimeOfDay(hour: 8))
        XCTAssertEqual(p.endTime, TimeOfDay(hour: 14))
    }

    func testSleepAtNine() {
        let p = parser.parse("Um 21 Uhr möchte ich schlafen.", now: now)
        XCTAssertTrue(p.isSleep)
        XCTAssertEqual(p.title, "Schlafen")
        XCTAssertEqual(p.startTime, TimeOfDay(hour: 21))
    }

    func testShoppingToday() {
        let p = parser.parse("Ich muss heute noch einkaufen.", now: now)
        XCTAssertEqual(p.title, "Einkaufen")
        XCTAssertEqual(p.day, T.date(28))
        XCTAssertNil(p.durationMinutes)
    }

    func testPlanNinetyMinutesSport() {
        let p = parser.parse("Plane mir morgen 90 Minuten Sport ein.", now: now)
        XCTAssertEqual(p.title, "Sport")
        XCTAssertEqual(p.durationMinutes, 90)
        XCTAssertEqual(p.day, T.date(29))
    }

    func testTwoHoursForExam() {
        let p = parser.parse("2 Stunden für die Klausur lernen", now: now)
        XCTAssertEqual(p.title, "Klausur lernen")
        XCTAssertEqual(p.durationMinutes, 120)
    }

    func testNumberWordsAndHalfHours() {
        XCTAssertEqual(parser.parse("zwei Stunden lernen", now: now).durationMinutes, 120)
        XCTAssertEqual(parser.parse("eine halbe Stunde Mails", now: now).durationMinutes, 30)
        XCTAssertEqual(parser.parse("anderthalb Stunden joggen", now: now).durationMinutes, 90)
        XCTAssertEqual(parser.parse("1,5 h Lesen", now: now).durationMinutes, 90)
        XCTAssertEqual(parser.parse("1 Stunde 30 Minuten Lesen", now: now).durationMinutes, 90)
    }

    func testExactTimeRangeWithColons() {
        let p = parser.parse("Sport 14:52–17:00", now: now)
        XCTAssertEqual(p.title, "Sport")
        XCTAssertEqual(p.startTime, TimeOfDay(hour: 14, minute: 52))
        XCTAssertEqual(p.endTime, TimeOfDay(hour: 17))
    }

    func testOvernightRange() {
        let p = parser.parse("Schlafen 21:00-07:00", now: now)
        XCTAssertEqual(p.interval(defaultDay: T.date(28), calendar: T.cal),
                       DateInterval(start: T.date(28, 21), end: T.date(29, 7)))
    }

    func testDateAndDeadline() {
        let p = parser.parse("Steuererklärung fertigstellen bis 30.10. 18 Uhr, 2 Stunden, wichtig", now: now)
        XCTAssertEqual(p.title, "Steuererklärung fertigstellen")
        XCTAssertEqual(p.deadline, T.date(30, 18))
        XCTAssertNil(p.day)
        XCTAssertNil(p.startTime)
        XCTAssertEqual(p.durationMinutes, 120)
        XCTAssertEqual(p.priority, .high)
    }

    func testDeadlineKeyword() {
        let p = parser.parse("Hausarbeit fertigstellen Deadline 28.11. 18:00 Dauer 2 Stunden", now: now)
        XCTAssertEqual(p.title, "Hausarbeit fertigstellen")
        XCTAssertEqual(p.deadline, T.date(28, 18, month: 11))
        XCTAssertEqual(p.durationMinutes, 120)
    }

    func testDeadlineTimeOnly() {
        let p = parser.parse("Ich muss bis 18 Uhr einkaufen", now: now)
        XCTAssertEqual(p.title, "Einkaufen")
        XCTAssertEqual(p.deadline, T.date(28, 18))
        XCTAssertNil(p.startTime)
    }

    func testExplicitDate() {
        let p = parser.parse("29.10. Zur Universität gehen 08:00–14:00", now: now)
        XCTAssertEqual(p.day, T.date(29))
        XCTAssertEqual(p.title, "Zur Universität gehen")
        XCTAssertEqual(p.startTime, TimeOfDay(hour: 8))
        XCTAssertEqual(p.endTime, TimeOfDay(hour: 14))
    }

    func testDateWithoutYearInJanuaryMeansNextYear() {
        let p = parser.parse("Zahnarzt am 15.01. um 9 Uhr", now: now)
        XCTAssertEqual(p.day, T.date(15, month: 1, year: 2027))
        XCTAssertEqual(p.title, "Zahnarzt")
    }

    func testInvalidDateIsIgnored() {
        let p = parser.parse("Treffen am 31.02.", now: now)
        XCTAssertNil(p.day)
    }

    func testWeekday() {
        let p = parser.parse("Am Freitag um 10 Uhr Zahnarzt", now: now)
        XCTAssertEqual(p.day, T.date(30))
        XCTAssertEqual(p.title, "Zahnarzt")
        // Mittwoch → nächste Woche, nicht heute
        XCTAssertEqual(parser.parse("Mittwoch Training", now: now).day, T.date(4, month: 11))
    }

    func testEveningShiftsHours() {
        let p = parser.parse("morgen abends um 8 Kino", now: now)
        XCTAssertEqual(p.startTime, TimeOfDay(hour: 20))
        XCTAssertEqual(p.title, "Kino")
    }

    func testBetweenItems() {
        let p = parser.parse("Pack mir heute noch zwei Stunden Lernen irgendwo zwischen Uni und Sport", now: now)
        XCTAssertEqual(p.title, "Lernen")
        XCTAssertEqual(p.durationMinutes, 120)
        XCTAssertEqual(p.afterItem, "uni")
        XCTAssertEqual(p.beforeItem, "sport")
    }

    func testBetweenTimes() {
        let p = parser.parse("Lernen zwischen 17 und 19 Uhr", now: now)
        XCTAssertEqual(p.startTime, TimeOfDay(hour: 17))
        XCTAssertEqual(p.endTime, TimeOfDay(hour: 19))
        XCTAssertNil(p.afterItem)
    }

    func testPriorityWords() {
        XCTAssertEqual(parser.parse("Steuer sehr wichtig", now: now).priority, .veryHigh)
        XCTAssertEqual(parser.parse("Steuer dringend", now: now).priority, .veryHigh)
        XCTAssertEqual(parser.parse("Steuer unwichtig", now: now).priority, .low)
        XCTAssertNil(parser.parse("Steuer", now: now).priority)
    }

    func testPlainTitleIsKept() {
        let p = parser.parse("E-Mail schreiben", now: now)
        XCTAssertEqual(p.title, "E-Mail schreiben")
        XCTAssertNil(p.day)
        XCTAssertNil(p.startTime)
        XCTAssertNil(p.durationMinutes)
    }

    func testEmptyInputGivesFallbackTitle() {
        XCTAssertEqual(parser.parse("   ", now: now).title, "Neuer Eintrag")
    }
}
