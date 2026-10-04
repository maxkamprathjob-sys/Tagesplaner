import XCTest
import SwiftData
import PlannerCore
@testable import Tagesplaner

@MainActor
final class AppTests: XCTestCase {

    private var cal: Calendar { DayMath.plannerCalendar }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func makeStore(container: ModelContainer? = nil, now: Date? = nil) -> PlanStore {
        let c = container ?? Persistence.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        let store = PlanStore(context: c.mainContext, settings: SettingsStore(defaults: defaults),
                              calendarService: CalendarService())
        store.integrationsEnabled = false
        let fixedNow = now ?? date(28, 6)
        store.clock = { fixedNow }
        store.settings.bufferMinutes = 0
        return store
    }

    // MARK: Gemeinsames Datenmodell / Synchronisierung

    func testTaskWithTimeAppearsInPlanAndList() {
        let store = makeStore()
        let item = PlanItem(title: "Zur Universität gehen", day: date(29),
                            interval: DateInterval(start: date(29, 8), end: date(29, 14)),
                            isTask: true, category: .uni, calendar: cal)
        store.insert(item)

        XCTAssertEqual(store.tasks(on: date(29)).map(\.id), [item.id])
        XCTAssertEqual(store.timedItems(on: date(29)).map(\.id), [item.id])
        XCTAssertEqual(store.allItems().count, 1, "Es darf keine Kopie entstehen")
    }

    func testChangingTimeIsVisibleEverywhere() {
        let store = makeStore()
        let item = PlanItem(title: "Sport", day: date(28),
                            interval: DateInterval(start: date(28, 14, 52), end: date(28, 17)),
                            isTask: true, category: .sport, calendar: cal)
        store.insert(item)
        store.schedule(item, at: DateInterval(start: date(28, 15, 30), end: date(28, 17, 30)))

        XCTAssertEqual(store.timedItems(on: date(28)).first?.start, date(28, 15, 30))
        XCTAssertEqual(store.tasks(on: date(28)).first?.end, date(28, 17, 30))
        XCTAssertEqual(store.scheduleEntries(around: date(28)).first?.interval.start, date(28, 15, 30))
    }

    func testMovingToOtherDayKeepsTimeAndChangesDay() {
        let store = makeStore()
        let item = PlanItem(title: "Uni", day: date(28),
                            interval: DateInterval(start: date(28, 8), end: date(28, 14)), calendar: cal)
        store.insert(item)
        store.move(item, toDay: date(29))
        XCTAssertEqual(item.start, date(29, 8))
        XCTAssertEqual(item.end, date(29, 14))
        XCTAssertTrue(store.timedItems(on: date(28)).isEmpty)
        XCTAssertEqual(store.timedItems(on: date(29)).count, 1)
    }

    // MARK: Tagesgenaue Daten

    func testTaskForTomorrowNotShownToday() {
        let store = makeStore()
        let parser = NaturalLanguageParser(calendar: cal)
        store.create(from: parser.parse("Ich muss morgen 2 Stunden lernen", now: date(28, 10)),
                     selectedDay: date(28), asTask: true)
        XCTAssertTrue(store.tasks(on: date(28)).isEmpty)
        XCTAssertEqual(store.tasks(on: date(29)).first?.title, "Lernen")
        XCTAssertEqual(store.tasks(on: date(29)).first?.estimatedMinutes, 120)
    }

    func testOvernightSleepShowsOnBothDays() {
        let store = makeStore()
        let parser = NaturalLanguageParser(calendar: cal)
        let result = store.create(from: parser.parse("Um 21 Uhr möchte ich schlafen", now: date(28, 10)),
                                  selectedDay: date(28), asTask: false)
        XCTAssertEqual(result.item.interval, DateInterval(start: date(28, 21), end: date(29, 7)))
        XCTAssertEqual(result.item.day, date(28))
        XCTAssertEqual(store.timedItems(on: date(28)).count, 1)
        XCTAssertEqual(store.timedItems(on: date(29)).count, 1, "Übernacht-Block reicht in den Folgetag")
        XCTAssertFalse(result.item.isTask)
    }

    // MARK: Konflikte & Planung über den Store

    func testConflictDetectedButNothingMoved() {
        let store = makeStore()
        let parser = NaturalLanguageParser(calendar: cal)
        store.create(from: parser.parse("Uni 08:00-14:00", now: date(28, 6)), selectedDay: date(28), asTask: false)
        let result = store.create(from: parser.parse("Sport 13:00-15:00", now: date(28, 6)), selectedDay: date(28), asTask: false)
        XCTAssertEqual(result.collisions.map(\.title), ["Uni"])
        XCTAssertEqual(store.conflicts(on: date(28)).count, 1)
        XCTAssertEqual(store.timedItems(on: date(28)).first?.start, date(28, 8), "Nichts wird automatisch verschoben")
    }

    func testSuggestionRequiresConfirmation() {
        let store = makeStore()
        let parser = NaturalLanguageParser(calendar: cal)
        store.create(from: parser.parse("Uni 08:00-14:00", now: date(28, 6)), selectedDay: date(28), asTask: false)
        store.create(from: parser.parse("Sport 14:52-17:00", now: date(28, 6)), selectedDay: date(28), asTask: false)
        let result = store.create(from: parser.parse("2 Stunden für die Klausur lernen", now: date(28, 6)),
                                  selectedDay: date(28), asTask: true)
        XCTAssertTrue(result.needsSuggestion)
        XCTAssertNil(result.item.interval, "Ohne Zustimmung wird nichts eingeplant")

        let suggestion = store.suggestion(for: result.item, on: date(28)).suggestion
        XCTAssertEqual(suggestion?.interval, DateInterval(start: date(28, 17), end: date(28, 19)))
        store.schedule(result.item, at: suggestion!.interval)
        XCTAssertEqual(store.timedItems(on: date(28)).count, 3)
    }

    func testWindowBetweenUniAndSport() {
        let store = makeStore()
        let parser = NaturalLanguageParser(calendar: cal)
        store.create(from: parser.parse("Uni 08:00-14:00", now: date(28, 6)), selectedDay: date(28), asTask: false)
        store.create(from: parser.parse("Sport 16:00-17:00", now: date(28, 6)), selectedDay: date(28), asTask: false)
        let result = store.create(from: parser.parse("heute 1 Stunde Mails zwischen Uni und Sport", now: date(28, 6)),
                                  selectedDay: date(28), asTask: true)
        XCTAssertEqual(result.window, DateInterval(start: date(28, 14), end: date(28, 16)))
        let s = store.suggestion(for: result.item, on: date(28), within: result.window).suggestion
        XCTAssertEqual(s?.interval.start, date(28, 14))
    }

    // MARK: Aufgabenstatus

    func testDoneStatus() {
        let store = makeStore()
        let item = PlanItem(title: "Einkaufen", day: date(28), calendar: cal)
        store.insert(item)
        store.setDone(item, true)
        XCTAssertTrue(item.isDone)
        XCTAssertNotNil(item.completedAt)
        store.setDone(item, false)
        XCTAssertNil(item.completedAt)
    }

    // MARK: Persistenz

    func testDataSurvivesRestart() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let container = Persistence.makeContainer(url: url)
            let store = makeStore(container: container)
            let item = PlanItem(title: "Hausarbeit", day: date(28), priority: .veryHigh,
                                estimatedMinutes: 120, deadline: date(30, 18), calendar: cal)
            store.insert(item)
        }

        let reopened = Persistence.makeContainer(url: url)
        let items = try reopened.mainContext.fetch(FetchDescriptor<PlanItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "Hausarbeit")
        XCTAssertEqual(items.first?.priority, .veryHigh)
        XCTAssertEqual(items.first?.deadline, date(30, 18))
    }

    // MARK: Benachrichtigungen (Logik)

    func testReminderTexts() {
        let item = PlanItem(title: "Universität", day: date(28),
                            interval: DateInterval(start: date(28, 8), end: date(28, 14)),
                            isTask: false, calendar: cal)
        let task = PlanItem(title: "Einkaufen", day: date(28), calendar: cal)
        let reminders = NotificationService.makeReminders(items: [item, task], externalEvents: [],
                                                          leadMinutes: 15, summaryEnabled: true,
                                                          summaryTime: TimeOfDay(hour: 7),
                                                          now: date(28, 6), calendar: cal)
        XCTAssertTrue(reminders.contains { $0.title == "Universität beginnt in 15 Minuten." && $0.fireDate == date(28, 7, 45) })
        XCTAssertTrue(reminders.contains { $0.title == "Du hast heute noch 1 offene Aufgabe." })
        XCTAssertLessThanOrEqual(reminders.count, 60)
    }

    // MARK: Widget-Snapshot

    func testWidgetSnapshotContainsTodayAndOpenTasks() {
        let item = PlanItem(title: "Sport", day: date(28),
                            interval: DateInterval(start: date(28, 14, 52), end: date(28, 17)), calendar: cal)
        let task = PlanItem(title: "E-Mail schreiben", day: date(28), priority: .high, calendar: cal)
        let snapshot = WidgetSync.makeSnapshot(items: [item, task], externalEvents: [], now: date(28, 10), calendar: cal)
        XCTAssertEqual(snapshot.items(on: date(28), calendar: cal).map(\.title), ["Sport"])
        XCTAssertEqual(snapshot.openTasks(on: date(28), calendar: cal).map(\.title), ["E-Mail schreiben", "Sport"])
        XCTAssertEqual(snapshot.current(at: date(28, 15))?.title, "Sport")
        XCTAssertEqual(snapshot.upcoming(after: date(28, 10), limit: 3).first?.title, "Sport")
    }

    func testCategoryGuess() {
        XCTAssertEqual(ItemCategory.guess(from: "Zur Universität gehen"), .uni)
        XCTAssertEqual(ItemCategory.guess(from: "Kommunikation üben"), .other)
        XCTAssertEqual(ItemCategory.guess(from: "Hausarbeit fertigstellen"), .study)
        XCTAssertEqual(ItemCategory.guess(from: "Schlafen"), .sleep)
    }
}
