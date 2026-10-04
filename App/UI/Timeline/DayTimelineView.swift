import SwiftUI
import PlannerCore

/// Ein darstellbarer Block der Zeitleiste (App-Eintrag oder Kalendertermin).
struct DisplayBlock: Identifiable, Hashable {
    var id: String
    var title: String
    var symbol: String
    var start: Date
    var end: Date
    /// Auf den angezeigten Tag zugeschnitten (Minuten seit 00:00, 0…1440).
    var topMinute: Int
    var bottomMinute: Int
    var continuesFromPreviousDay: Bool
    var continuesToNextDay: Bool
    var isExternal: Bool
    var isSleep: Bool
    var isDone: Bool
    var isTask: Bool
    var isFixed: Bool
    var isConflict: Bool
    var itemID: UUID?
    /// Spalte bei Überschneidung.
    var column = 0
    var columnCount = 1
}

/// Vertikale Zeitleiste 00:00–24:00. Je länger ein Block, desto höher.
struct DayTimelineView: View {
    let day: Date
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var calendarService: CalendarService

    static let hourHeight: CGFloat = 64
    static let labelWidth: CGFloat = 52
    private var minuteHeight: CGFloat { Self.hourHeight / 60 }

    var body: some View {
        let _ = store.revision
        let _ = calendarService.revision
        let blocks = makeBlocks()
        let gaps = freeGaps()
        let allDay = store.externalEvents(on: day).filter(\.isAllDay)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !allDay.isEmpty {
                        AllDayStrip(events: allDay)
                            .padding(.leading, Self.labelWidth)
                            .padding(.trailing, 12)
                            .padding(.bottom, 8)
                    }
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        GeometryReader { geo in
                            let width = geo.size.width - Self.labelWidth - 12
                            ZStack(alignment: .topLeading) {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture { location in createBlock(atY: location.y) }

                                ForEach(gaps, id: \.self) { gap in
                                    FreeGapLabel(interval: gap)
                                        .frame(width: width, height: height(of: gap), alignment: .center)
                                        .offset(x: Self.labelWidth, y: y(of: gap.start))
                                        .allowsHitTesting(false)
                                }

                                ForEach(blocks) { block in
                                    let columnWidth = width / CGFloat(block.columnCount)
                                    TimelineBlockView(block: block, minuteHeight: minuteHeight)
                                        .frame(width: max(40, columnWidth - 4),
                                               height: max(22, CGFloat(block.bottomMinute - block.topMinute) * minuteHeight - 2))
                                        .offset(x: Self.labelWidth + CGFloat(block.column) * columnWidth,
                                                y: CGFloat(block.topMinute) * minuteHeight + 1)
                                }

                                if Calendar.current.isDateInToday(day) {
                                    NowLine(labelWidth: Self.labelWidth)
                                        .offset(y: y(of: store.now) - 4)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .frame(height: Self.hourHeight * 24 + 20)
                }
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .onAppear { scrollToRelevant(proxy, blocks: blocks) }
            .onChange(of: day) { _, _ in scrollToRelevant(proxy, blocks: makeBlocks()) }
        }
    }

    // MARK: Raster

    private var hourGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0...24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: Self.labelWidth - 8, alignment: .trailing)
                        .offset(y: -7)
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 0.5)
                }
                .frame(height: hour == 24 ? 20 : Self.hourHeight, alignment: .top)
                .id("hour-\(hour)")
            }
        }
    }

    // MARK: Daten

    private func makeBlocks() -> [DisplayBlock] {
        let di = store.dayInterval(day)
        let conflictIDs = ConflictDetector.conflictingIDs(in: store.scheduleEntries(around: day))
        var result: [DisplayBlock] = store.timedItems(on: day).compactMap { item in
            guard let iv = item.interval else { return nil }
            return block(id: item.id.uuidString, title: item.title, symbol: item.category.symbol,
                         interval: iv, dayInterval: di, isExternal: false, isSleep: item.isSleep,
                         isDone: item.isDone, isTask: item.isTask, isFixed: item.isFixed,
                         isConflict: conflictIDs.contains(item.id.uuidString), itemID: item.id)
        }
        result += store.externalEvents(on: day).filter { !$0.isAllDay }.map { e in
            block(id: e.id, title: e.title, symbol: "calendar", interval: e.interval, dayInterval: di,
                  isExternal: true, isSleep: false, isDone: false, isTask: false, isFixed: true,
                  isConflict: conflictIDs.contains(e.id), itemID: nil)
        }
        return TimelineLayout.assignColumns(result)
    }

    private func block(id: String, title: String, symbol: String, interval: DateInterval, dayInterval di: DateInterval,
                       isExternal: Bool, isSleep: Bool, isDone: Bool, isTask: Bool, isFixed: Bool,
                       isConflict: Bool, itemID: UUID?) -> DisplayBlock {
        let fromPrev = interval.start < di.start
        let toNext = interval.end > di.end
        let top = fromPrev ? 0 : TimeOfDay(interval.start).minutesSinceMidnight
        var bottom = toNext ? 24 * 60 : TimeOfDay(interval.end).minutesSinceMidnight
        if bottom <= top { bottom = 24 * 60 }
        return DisplayBlock(id: id, title: title, symbol: symbol, start: interval.start, end: interval.end,
                            topMinute: top, bottomMinute: bottom,
                            continuesFromPreviousDay: fromPrev, continuesToNextDay: toNext,
                            isExternal: isExternal, isSleep: isSleep, isDone: isDone, isTask: isTask,
                            isFixed: isFixed, isConflict: isConflict, itemID: itemID)
    }

    /// Freie Lücken ab 30 Min. im Wach-Fenster – damit freie Zeit sichtbar wird.
    private func freeGaps() -> [DateInterval] {
        let isPast = store.dayInterval(day).end <= store.now
        guard !isPast else { return [] }
        return store.availability.freeSlots(on: day, entries: store.scheduleEntries(around: day))
            .filter { $0.duration >= 30 * 60 }
            .filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    private func y(of date: Date) -> CGFloat {
        let di = store.dayInterval(day)
        if date <= di.start { return 0 }
        if date >= di.end { return 24 * Self.hourHeight }
        return CGFloat(TimeOfDay(date).minutesSinceMidnight) * minuteHeight
    }

    private func height(of interval: DateInterval) -> CGFloat {
        max(0, y(of: interval.end) - y(of: interval.start))
    }

    private func scrollToRelevant(_ proxy: ScrollViewProxy, blocks: [DisplayBlock]) {
        let hour: Int
        if Calendar.current.isDateInToday(day) {
            hour = max(0, Calendar.current.component(.hour, from: Date()) - 1)
        } else if let first = blocks.filter({ !$0.isSleep && !$0.continuesFromPreviousDay }).map(\.topMinute).min() {
            hour = max(0, first / 60 - 1)
        } else {
            hour = max(0, settings.wakeTime.hour - 1)
        }
        DispatchQueue.main.async {
            proxy.scrollTo("hour-\(hour)", anchor: .top)
        }
    }

    /// Tippen auf eine freie Stelle → neuer Block zu dieser Uhrzeit.
    private func createBlock(atY yPos: CGFloat) {
        let minutes = Int(yPos / minuteHeight)
        let rounded = max(0, min(23 * 60 + 45, (minutes / 15) * 15))
        let start = TimeOfDay(minutesSinceMidnight: rounded).date(on: day, calendar: Calendar.current)
        ui.editor = EditorRequest(item: nil, defaultStart: start, defaultDay: day, asTask: false)
    }
}

enum TimelineLayout {
    /// Überlappende Blöcke nebeneinander anordnen (Spalten pro Cluster).
    static func assignColumns(_ blocks: [DisplayBlock]) -> [DisplayBlock] {
        let sorted = blocks.sorted { ($0.topMinute, $1.bottomMinute) < ($1.topMinute, $0.bottomMinute) }
        var result: [DisplayBlock] = []
        var cluster: [DisplayBlock] = []
        var clusterEnd = -1

        func flush() {
            guard !cluster.isEmpty else { return }
            var columnEnds: [Int] = []
            var placed: [DisplayBlock] = []
            for var b in cluster {
                if let free = columnEnds.firstIndex(where: { $0 <= b.topMinute }) {
                    b.column = free
                    columnEnds[free] = b.bottomMinute
                } else {
                    b.column = columnEnds.count
                    columnEnds.append(b.bottomMinute)
                }
                placed.append(b)
            }
            for var b in placed {
                b.columnCount = columnEnds.count
                result.append(b)
            }
            cluster.removeAll()
        }

        for b in sorted {
            if b.topMinute >= clusterEnd { flush(); clusterEnd = b.bottomMinute }
            else { clusterEnd = max(clusterEnd, b.bottomMinute) }
            cluster.append(b)
        }
        flush()
        return result
    }
}

struct NowLine: View {
    let labelWidth: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            Text(Fmt.time(Date()))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accentText)
                .frame(width: labelWidth - 10, alignment: .trailing)
                .padding(.trailing, 2)
            Circle().fill(Theme.accentText).frame(width: 8, height: 8)
            Rectangle().fill(Theme.accentText).frame(height: 1.5)
        }
    }
}

struct FreeGapLabel: View {
    let interval: DateInterval
    var body: some View {
        Text("frei · \(DurationText.approximate(DayMath.minutes(interval)))")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.textSecondary.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

struct AllDayStrip: View {
    let events: [ExternalEvent]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(events) { e in
                    Label(e.title, systemImage: "calendar")
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.surface, in: Capsule())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}
