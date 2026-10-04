import Foundation
import SwiftData
import SwiftUI
import PlannerCore

/// Zentrale Geschäftslogik der App.
///
/// Alle Änderungen laufen hierüber. Danach werden automatisch gespeichert und
/// Widgets, Benachrichtigungen und Live Activity aktualisiert. Dadurch gibt es
/// genau einen Weg, Daten zu verändern – und keine widersprüchlichen Zustände.
@MainActor
final class PlanStore: ObservableObject {
    let context: ModelContext
    let settings: SettingsStore
    let calendarService: CalendarService
    let notifications: NotificationService
    let liveActivity: LiveActivityService

    /// Erhöht sich bei jeder Änderung – Views berechnen daraufhin neu.
    @Published private(set) var revision = 0
    /// Verständliche Fehlermeldung für die Oberfläche.
    @Published var errorMessage: String?

    var calendar: Calendar { DayMath.plannerCalendar }
    /// Überschreibbar für Tests.
    var clock: () -> Date = { Date() }
    var now: Date { clock() }
    /// In Tests aus, damit keine Systemdienste angesprochen werden.
    var integrationsEnabled = true

    init(context: ModelContext,
         settings: SettingsStore,
         calendarService: CalendarService,
         notifications: NotificationService? = nil,
         liveActivity: LiveActivityService? = nil) {
        self.context = context
        self.settings = settings
        self.calendarService = calendarService
        self.notifications = notifications ?? NotificationService()
        self.liveActivity = liveActivity ?? LiveActivityService()
    }

    // MARK: - Lesen

    func allItems() -> [PlanItem] {
        let descriptor = FetchDescriptor<PlanItem>(sortBy: [SortDescriptor(\.createdAt)])
        do {
            return try context.fetch(descriptor)
        } catch {
            errorMessage = "Daten konnten nicht gelesen werden: \(error.localizedDescription)"
            return []
        }
    }

    func item(id: UUID) -> PlanItem? {
        var descriptor = FetchDescriptor<PlanItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func dayInterval(_ day: Date) -> DateInterval {
        DayMath.dayInterval(containing: day, calendar: calendar)
    }

    /// Zeitblöcke, die den Tag berühren (inkl. Übernacht-Blöcke vom Vortag).
    func timedItems(on day: Date) -> [PlanItem] {
        let di = dayInterval(day)
        return allItems()
            .filter { item in
                guard let iv = item.interval else { return false }
                return iv.start < di.end && iv.end > di.start
            }
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    /// Aufgaben eines Tages (eingeplant oder nicht). Ein Eintrag erscheint
    /// ausschließlich an seinem eigenen Tag.
    func tasks(on day: Date) -> [PlanItem] {
        let target = calendar.startOfDay(for: day)
        return allItems().filter { $0.isTask && calendar.isDate($0.day, inSameDayAs: target) }
    }

    /// Termine des Tages, die keine Aufgaben sind (für die Termin-Liste).
    func appointments(on day: Date) -> [PlanItem] {
        let target = calendar.startOfDay(for: day)
        return allItems().filter { !$0.isTask && $0.isScheduled && calendar.isDate($0.day, inSameDayAs: target) }
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    /// Offene Aufgaben früherer Tage, die nie erledigt wurden.
    func overdueTasks(before day: Date) -> [PlanItem] {
        let target = calendar.startOfDay(for: day)
        return allItems().filter { $0.isTask && !$0.isDone && $0.day < target }
            .sorted { $0.day > $1.day }
    }

    func externalEvents(in interval: DateInterval) -> [ExternalEvent] {
        guard settings.calendarEnabled else { return [] }
        return calendarService.events(in: interval)
    }

    func externalEvents(on day: Date) -> [ExternalEvent] {
        externalEvents(in: dayInterval(day))
    }

    /// Belegte Zeiträume rund um einen Tag (Vortag-Nacht bis Folgetag-Mittag).
    func scheduleEntries(around day: Date, excluding excludedID: UUID? = nil) -> [ScheduleEntry] {
        let di = dayInterval(day)
        let range = DateInterval(start: di.start.addingTimeInterval(-12 * 3600), end: di.end.addingTimeInterval(12 * 3600))
        var entries = allItems().compactMap { item -> ScheduleEntry? in
            guard item.id != excludedID, let e = item.scheduleEntry, DayMath.overlaps(e.interval, range) else { return nil }
            return e
        }
        entries += externalEvents(in: range).filter { !$0.isAllDay }.map {
            ScheduleEntry(id: $0.id, title: $0.title, interval: $0.interval, kind: .external)
        }
        return entries
    }

    var availability: AvailabilityCalculator {
        AvailabilityCalculator(settings: settings.planner, calendar: calendar)
    }

    var scheduler: Scheduler {
        Scheduler(settings: settings.planner, calendar: calendar)
    }

    // MARK: - Analyse

    func conflicts(on day: Date) -> [Conflict] {
        let di = dayInterval(day)
        return ConflictDetector.conflicts(in: scheduleEntries(around: day))
            .filter { DayMath.overlaps($0.overlap, di) }
    }

    func dayLoad(on day: Date) -> DayLoad {
        let open = tasks(on: day).filter { !$0.isDone && !$0.isScheduled }
        let entries = scheduleEntries(around: day)
        return DayAnalyzer.analyze(day: day, entries: entries,
                                   unplannedTaskMinutes: open.map(\.estimatedMinutes),
                                   now: now, availability: availability)
    }

    func deadlineAssessment(for item: PlanItem) -> DeadlineAssessment? {
        guard item.isTask, !item.isDone, item.deadline != nil else { return nil }
        return DeadlineAnalyzer.assess(task: item.taskRequest(defaultMinutes: settings.defaultTaskMinutes),
                                       scheduled: item.interval, now: now, availability: availability) { day in
            self.scheduleEntries(around: day, excluding: item.id)
        }
    }

    /// Aufgaben (aller Tage) mit gefährdeter Deadline in den nächsten 14 Tagen.
    func deadlineWarnings() -> [(item: PlanItem, assessment: DeadlineAssessment)] {
        let limit = now.addingTimeInterval(14 * 86_400)
        return allItems()
            .filter { $0.isTask && !$0.isDone && ($0.deadline.map { $0 <= limit } ?? false) }
            .compactMap { item in
                guard let a = deadlineAssessment(for: item), a.level != .ok else { return nil }
                return (item, a)
            }
            .sorted { $0.assessment.level > $1.assessment.level }
    }

    // MARK: - Planung (nur Vorschläge)

    /// Zeitfenster aus Bezügen wie "zwischen Uni und Sport".
    func window(after: String?, before: String?, on day: Date) -> DateInterval? {
        guard after != nil || before != nil else { return nil }
        let entries = scheduleEntries(around: day)
        func find(_ name: String?) -> ScheduleEntry? {
            guard let n = name?.lowercased(), !n.isEmpty else { return nil }
            return entries.first { e in
                let t = e.title.lowercased()
                return t.hasPrefix(n) || t.contains(" " + n) || t == n
            }
        }
        let a = find(after)
        let b = find(before)
        let di = dayInterval(day)
        let start = a?.interval.end ?? di.start
        let end = b?.interval.start ?? di.end
        if (after != nil && a == nil) || (before != nil && b == nil) { return nil }
        return end > start ? DateInterval(start: start, end: end) : nil
    }

    func suggestion(for item: PlanItem, on day: Date, within window: DateInterval? = nil) -> SchedulingResult {
        let request = item.taskRequest(defaultMinutes: settings.defaultTaskMinutes)
        let next = DayMath.addDays(1, to: day, calendar: calendar)
        return scheduler.suggest(request, on: day,
                                 entries: scheduleEntries(around: day, excluding: item.id),
                                 nextDayEntries: scheduleEntries(around: next, excluding: item.id),
                                 within: window, now: now)
    }

    /// Sucht in den nächsten Tagen den ersten Tag, an dem die Aufgabe passt.
    func firstFit(for item: PlanItem, from day: Date, days: Int = 7) -> (day: Date, suggestion: Suggestion)? {
        for offset in 0..<days {
            let d = DayMath.addDays(offset, to: day, calendar: calendar)
            if dayInterval(d).end <= now { continue }
            if let s = suggestion(for: item, on: d).suggestion {
                return (d, s)
            }
        }
        return nil
    }

    /// Vorschläge für alle offenen, nicht eingeplanten Aufgaben eines Tages.
    func planDayProposals(on day: Date) -> [(item: PlanItem, result: SchedulingResult)] {
        let open = tasks(on: day).filter { !$0.isDone && !$0.isScheduled }
        let byID = Dictionary(uniqueKeysWithValues: open.map { ($0.id.uuidString, $0) })
        let next = DayMath.addDays(1, to: day, calendar: calendar)
        let plan = scheduler.planDay(open.map { $0.taskRequest(defaultMinutes: settings.defaultTaskMinutes) },
                                     on: day, entries: scheduleEntries(around: day),
                                     nextDayEntries: scheduleEntries(around: next), now: now)
        return plan.compactMap { entry in
            guard let item = byID[entry.task.id] else { return nil }
            return (item, entry.result)
        }
    }

    // MARK: - Ändern

    struct CreationResult {
        var item: PlanItem
        /// Vorschlag nötig (Dauer bekannt, aber keine Uhrzeit).
        var needsSuggestion: Bool
        var window: DateInterval?
        var collisions: [ScheduleEntry]
    }

    /// Erstellt einen Eintrag aus einer (geparsten) Schnelleingabe.
    @discardableResult
    func create(from parsed: ParsedInput, selectedDay: Date, asTask: Bool) -> CreationResult {
        let day = parsed.day ?? calendar.startOfDay(for: selectedDay)
        let category: ItemCategory = parsed.isSleep ? .sleep : ItemCategory.guess(from: parsed.title)

        var interval = parsed.interval(defaultDay: day, calendar: calendar)
        if interval == nil, let start = parsed.startTime {
            if parsed.isSleep {
                interval = DayMath.interval(on: day, from: start, to: settings.wakeTime, calendar: calendar)
            } else {
                let s = start.date(on: day, calendar: calendar)
                interval = DateInterval(start: s, duration: TimeInterval(settings.defaultTaskMinutes * 60))
            }
        }

        let item = PlanItem(title: parsed.title,
                            day: day,
                            interval: interval,
                            isTask: asTask && !parsed.isSleep,
                            category: category,
                            priority: parsed.priority ?? .normal,
                            estimatedMinutes: parsed.durationMinutes ?? interval.map { DayMath.minutes($0) },
                            deadline: parsed.deadline,
                            isFixed: interval != nil && (!asTask || category.isFixedByDefault),
                            calendar: calendar)
        context.insert(item)
        didChange()

        let collisions = interval.map {
            ConflictDetector.collisions(of: $0, ignoring: item.id.uuidString, in: scheduleEntries(around: day))
        } ?? []
        let window = self.window(after: parsed.afterItem, before: parsed.beforeItem, on: day)
        return CreationResult(item: item,
                              needsSuggestion: interval == nil && parsed.durationMinutes != nil,
                              window: window,
                              collisions: collisions)
    }

    func insert(_ item: PlanItem) {
        context.insert(item)
        didChange()
    }

    func delete(_ item: PlanItem) {
        context.delete(item)
        didChange()
    }

    /// Übernimmt einen bestätigten Vorschlag.
    func schedule(_ item: PlanItem, at interval: DateInterval) {
        item.setSchedule(interval, calendar: calendar)
        didChange()
    }

    func unschedule(_ item: PlanItem) {
        item.setSchedule(nil, calendar: calendar)
        didChange()
    }

    func setDone(_ item: PlanItem, _ done: Bool) {
        item.setDone(done)
        didChange()
    }

    func move(_ item: PlanItem, toDay day: Date) {
        item.move(toDay: day, calendar: calendar)
        didChange()
    }

    /// Verschiebt einen Block um eine Anzahl Minuten (Drag & Drop).
    func shift(_ item: PlanItem, byMinutes minutes: Int) {
        guard let iv = item.interval, minutes != 0 else { return }
        let delta = TimeInterval(minutes * 60)
        item.setSchedule(DateInterval(start: iv.start.addingTimeInterval(delta), end: iv.end.addingTimeInterval(delta)),
                         calendar: calendar)
        didChange()
    }

    /// Ändert die Länge eines Blocks (Ziehen am unteren Rand).
    func resize(_ item: PlanItem, endByMinutes minutes: Int) {
        guard let iv = item.interval, minutes != 0 else { return }
        let newEnd = iv.end.addingTimeInterval(TimeInterval(minutes * 60))
        guard newEnd.timeIntervalSince(iv.start) >= 5 * 60 else { return }
        item.setSchedule(DateInterval(start: iv.start, end: newEnd), calendar: calendar)
        didChange()
    }

    /// Nach Bearbeitung im Formular.
    func commitEdit() {
        didChange()
    }

    // MARK: - Speichern & Integrationen

    private var refreshTask: Task<Void, Never>?

    func didChange() {
        do {
            try context.save()
        } catch {
            errorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
        revision += 1
        scheduleIntegrationRefresh()
    }

    /// Bündelt schnelle Folgeänderungen (z. B. beim Ziehen) zu einer Aktualisierung.
    func scheduleIntegrationRefresh() {
        guard integrationsEnabled else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshIntegrations()
        }
    }

    func refreshIntegrations() async {
        let now = self.now
        let items = allItems()
        let horizon = DateInterval(start: DayMath.addDays(-1, to: now, calendar: calendar),
                                   end: DayMath.addDays(8, to: now, calendar: calendar))
        let events = externalEvents(in: horizon)

        if let error = WidgetSync.publish(WidgetSync.makeSnapshot(items: items, externalEvents: events,
                                                                   now: now, calendar: calendar)) {
            errorMessage = error
        }

        await notifications.reschedule(items: items, externalEvents: events, settings: settings,
                                       now: now, calendar: calendar)

        let today = dayInterval(now)
        let blocks: [TimelineBlock] = items.compactMap { item in
            guard let iv = item.interval, !item.isDone, DayMath.overlaps(iv, today) || iv.start > now else { return nil }
            return TimelineBlock(id: item.id.uuidString, title: item.title, symbol: item.category.symbol,
                                 start: iv.start, end: iv.end, isSleep: item.isSleep)
        } + events.filter { !$0.isAllDay }.map {
            TimelineBlock(id: $0.id, title: $0.title, symbol: "calendar", start: $0.start, end: $0.end, isSleep: false)
        }
        await liveActivity.sync(enabled: settings.liveActivityEnabled, blocks: blocks, now: now)
    }
}
