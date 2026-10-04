import XCTest
@testable import PlannerCore

final class PlanningTests: XCTestCase {

    private var scheduler: Scheduler { Scheduler(settings: T.settings, calendar: T.cal) }
    private var availability: AvailabilityCalculator { AvailabilityCalculator(settings: T.settings, calendar: T.cal) }

    // MARK: Konflikte

    func testDetectsOverlap() {
        let entries = [
            T.entry("Universität", T.date(28, 8), T.date(28, 14)),
            T.entry("Sport", T.date(28, 13), T.date(28, 15))
        ]
        let conflicts = ConflictDetector.conflicts(in: entries)
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].overlap, DateInterval(start: T.date(28, 13), end: T.date(28, 14)))
        XCTAssertEqual(ConflictDetector.conflictingIDs(in: entries), ["Universität", "Sport"])
    }

    func testAdjacentBlocksAreNoConflict() {
        let entries = [
            T.entry("A", T.date(28, 8), T.date(28, 14)),
            T.entry("B", T.date(28, 14), T.date(28, 17))
        ]
        XCTAssertTrue(ConflictDetector.conflicts(in: entries).isEmpty)
    }

    func testOvernightBlockConflictsWithEarlyMorning() {
        let entries = [
            T.entry("Schlafen", T.date(28, 21), T.date(29, 7), .sleep),
            T.entry("Frühsport", T.date(29, 6), T.date(29, 7, 30))
        ]
        XCTAssertEqual(ConflictDetector.conflicts(in: entries).count, 1)
    }

    // MARK: Freie Zeit / Schlafenszeit

    func testFreeSlotsRespectWakeAndBedtime() {
        let slots = availability.freeSlots(on: T.date(28), entries: T.exampleDay())
        XCTAssertEqual(slots.map { "\(T.hm($0.start))-\(T.hm($0.end))" },
                       ["07:00-08:00", "14:00-14:52", "17:00-21:00"])
    }

    func testFreeSlotsStartAtNow() {
        let slots = availability.freeSlots(on: T.date(28), entries: T.exampleDay(), notBefore: T.date(28, 17, 42))
        XCTAssertEqual(slots.map { "\(T.hm($0.start))-\(T.hm($0.end))" }, ["17:45-21:00"])
    }

    func testEarlierSleepBlockShortensDay() {
        var entries = T.exampleDay().filter { $0.id != "Schlafen" }
        entries.append(T.entry("Schlafen", T.date(28, 20), T.date(29, 6), .sleep))
        let window = availability.planningWindow(for: T.date(28), entries: entries)
        XCTAssertEqual(window.end, T.date(28, 20))
    }

    func testBufferAroundFixedBlocks() {
        var settings = T.settings
        settings.bufferMinutes = 10
        let calc = AvailabilityCalculator(settings: settings, calendar: T.cal)
        let slots = calc.freeSlots(on: T.date(28), entries: T.exampleDay())
        XCTAssertEqual(slots.map { "\(T.hm($0.start))-\(T.hm($0.end))" },
                       ["07:00-07:50", "14:10-14:42", "17:10-21:00"])
    }

    // MARK: Automatische Planung

    func testSuggestsTwoHoursLearningAfterSport() {
        let task = TaskRequest(id: "lernen", title: "Lernen", durationMinutes: 120)
        let result = scheduler.suggest(task, on: T.date(28), entries: T.exampleDay(), now: T.date(28, 6))
        guard let s = result.suggestion else { return XCTFail("Kein Vorschlag") }
        XCTAssertEqual(s.interval, DateInterval(start: T.date(28, 17), end: T.date(28, 19)))
        XCTAssertFalse(s.alternatives.isEmpty, "\"Andere Zeit\" braucht Alternativen")
        XCTAssertTrue(s.alternatives.allSatisfy { $0.end <= T.date(28, 21) })
    }

    func testNeverSuggestsPastTimes() {
        let task = TaskRequest(id: "x", title: "X", durationMinutes: 30)
        let result = scheduler.suggest(task, on: T.date(28), entries: T.exampleDay(), now: T.date(28, 18, 3))
        XCTAssertEqual(result.suggestion?.interval.start, T.date(28, 18, 5))
    }

    func testNoFitWhenDayIsFull() {
        let task = TaskRequest(id: "lernen", title: "Lernen", durationMinutes: 5 * 60)
        let tomorrow = [T.entry("Uni", T.date(29, 8), T.date(29, 12))]
        let result = scheduler.suggest(task, on: T.date(28), entries: T.exampleDay(),
                                       nextDayEntries: tomorrow, now: T.date(28, 6))
        guard let n = result.noFit else { return XCTFail("Hätte nicht passen dürfen") }
        XCTAssertEqual(n.largestGapMinutes, 240)
        XCTAssertEqual(n.missingMinutes, 60)
        XCTAssertEqual(n.nextDay, DateInterval(start: T.date(29, 12), end: T.date(29, 17)))
    }

    func testHintsWhenOnlyAfterBedtimeFits() {
        let entries = T.exampleDay() + [T.entry("Kino", T.date(28, 17), T.date(28, 20, 30))]
        let task = TaskRequest(id: "x", title: "Lesen", durationMinutes: 60)
        let result = scheduler.suggest(task, on: T.date(28), entries: entries, now: T.date(28, 15))
        guard let n = result.noFit else { return XCTFail() }
        XCTAssertEqual(n.afterBedtime?.start, T.date(28, 21))
    }

    func testWindowBetweenItems() {
        let window = DateInterval(start: T.date(28, 14), end: T.date(28, 14, 52))
        let task = TaskRequest(id: "x", title: "Mails", durationMinutes: 30)
        let result = scheduler.suggest(task, on: T.date(28), entries: T.exampleDay(), within: window, now: T.date(28, 6))
        XCTAssertEqual(result.suggestion?.interval.start, T.date(28, 14))
    }

    func testDeadlinePreferredCandidates() {
        let entries = T.exampleDay()
        let task = TaskRequest(id: "x", title: "Abgabe", durationMinutes: 60, deadline: T.date(28, 8))
        let result = scheduler.suggest(task, on: T.date(28), entries: entries, now: T.date(28, 6))
        XCTAssertEqual(result.suggestion?.interval, DateInterval(start: T.date(28, 7), end: T.date(28, 8)))
        XCTAssertNil(result.suggestion?.deadlineWarning)
    }

    // MARK: Prioritäten

    func testHighPriorityIsPlannedFirst() {
        var tasks: [TaskRequest] = (0..<10).map {
            TaskRequest(id: "unwichtig\($0)", title: "Kleinkram \($0)", durationMinutes: 30, priority: .low)
        }
        tasks.append(TaskRequest(id: "wichtig", title: "Klausur", durationMinutes: 120, priority: .veryHigh))
        let plan = scheduler.planDay(tasks, on: T.date(28), entries: T.exampleDay(), now: T.date(28, 6))
        XCTAssertEqual(plan.first?.task.id, "wichtig")
        XCTAssertEqual(plan.first?.result.suggestion?.interval.start, T.date(28, 17))
        // Keine zwei Vorschläge überschneiden sich
        let intervals = plan.compactMap { $0.result.suggestion?.interval }
        for i in 0..<intervals.count {
            for j in (i + 1)..<intervals.count {
                XCTAssertFalse(DayMath.overlaps(intervals[i], intervals[j]))
            }
        }
    }

    func testUrgentDeadlineBeatsPriority() {
        let now = T.date(28, 6)
        let tasks = [
            TaskRequest(id: "hoch", title: "A", durationMinutes: 60, priority: .high),
            TaskRequest(id: "dringend", title: "B", durationMinutes: 60, priority: .normal, deadline: T.date(28, 20))
        ]
        XCTAssertEqual(Scheduler.order(tasks, now: now, calendar: T.cal).map(\.id), ["dringend", "hoch"])
    }

    // MARK: Deadlines

    func testDeadlineTightWhenOnlyTodayHasTime() {
        let now = T.date(28, 6)
        let task = TaskRequest(id: "h", title: "Hausarbeit", durationMinutes: 120, deadline: T.date(29, 10))
        let result = DeadlineAnalyzer.assess(task: task, scheduled: nil, now: now, availability: availability) { day in
            if day == T.date(29) {
                return [T.entry("Uni", T.date(29, 8), T.date(29, 14))]
            }
            return T.exampleDay()
        }
        XCTAssertEqual(result?.level, .tight)
        XCTAssertEqual(result?.message, "Wenn du diese Aufgabe heute nicht einplanst, wird es zeitlich knapp.")
    }

    func testDeadlineAtRisk() {
        let task = TaskRequest(id: "h", title: "Hausarbeit", durationMinutes: 6 * 60, deadline: T.date(28, 20))
        let result = DeadlineAnalyzer.assess(task: task, scheduled: nil, now: T.date(28, 15), availability: availability) { _ in T.exampleDay() }
        XCTAssertEqual(result?.level, .atRisk)
    }

    func testDeadlineOverdueAndScheduled() {
        let task = TaskRequest(id: "h", title: "H", durationMinutes: 60, deadline: T.date(28, 12))
        XCTAssertEqual(DeadlineAnalyzer.assess(task: task, scheduled: nil, now: T.date(28, 13),
                                               availability: availability) { _ in [] }?.level, .overdue)
        let ok = DeadlineAnalyzer.assess(task: task, scheduled: DateInterval(start: T.date(28, 9), end: T.date(28, 10)),
                                         now: T.date(28, 8), availability: availability) { _ in [] }
        XCTAssertEqual(ok?.level, .ok)
    }

    // MARK: Tagesanalyse

    func testDayAnalysisCountsFixedAndOpen() {
        let load = DayAnalyzer.analyze(day: T.date(28), entries: T.exampleDay(),
                                       unplannedTaskMinutes: [120, 180, nil],
                                       now: T.date(28, 6), availability: availability)
        XCTAssertEqual(load.fixedMinutes, 6 * 60 + 128)
        XCTAssertEqual(load.unplannedTaskMinutes, 300)
        XCTAssertEqual(load.unestimatedTaskCount, 1)
        XCTAssertEqual(load.freeMinutes, 60 + 52 + 240)
        XCTAssertEqual(load.level, .balanced)
    }

    func testDayAnalysisFull() {
        let entries = T.exampleDay() + [T.entry("Arbeit", T.date(28, 17), T.date(28, 21))]
        let load = DayAnalyzer.analyze(day: T.date(28), entries: entries, unplannedTaskMinutes: [180],
                                       now: T.date(28, 15), availability: availability)
        XCTAssertEqual(load.level, .full)
        XCTAssertTrue(load.headline.contains("vollständig verplant"))
    }

    func testPastDay() {
        let load = DayAnalyzer.analyze(day: T.date(27), entries: [], unplannedTaskMinutes: [],
                                       now: T.date(28, 10), availability: availability)
        XCTAssertEqual(load.level, .past)
    }
}
