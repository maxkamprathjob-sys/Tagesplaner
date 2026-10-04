import SwiftUI
import PlannerCore

/// Ein Zeitblock in der Zeitleiste.
/// - Tippen: bearbeiten
/// - Gedrückt halten und ziehen: verschieben (5-Minuten-Raster)
/// - Unteren Griff ziehen: Länge ändern
struct TimelineBlockView: View {
    let block: DisplayBlock
    let minuteHeight: CGFloat
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var ui: UIState

    @GestureState private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false
    @GestureState private var resizeOffset: CGFloat = 0

    private var editable: Bool { block.itemID != nil }
    private var heightPoints: CGFloat { CGFloat(block.bottomMinute - block.topMinute) * minuteHeight }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background)
            .overlay(border)
            .overlay(alignment: .bottom) { resizeHandle }
            .padding(.bottom, -resizeOffset)
            .offset(y: dragOffset)
            .scaleEffect(isDragging ? 1.02 : 1)
            .shadow(color: .black.opacity(isDragging ? 0.4 : 0), radius: 8, y: 4)
            .zIndex(isDragging ? 10 : 0)
            .animation(.easeOut(duration: 0.15), value: isDragging)
            .contentShape(Rectangle())
            .onTapGesture { openEditor() }
            .gesture(moveGesture, including: editable ? .all : .subviews)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(block.title), \(Fmt.range(block.start, block.end))")
            .accessibilityHint(editable ? "Doppeltippen zum Bearbeiten" : "Termin aus dem Apple-Kalender")
    }

    // MARK: Inhalt

    @ViewBuilder
    private var content: some View {
        let compact = heightPoints < 40
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
            if compact {
                HStack(spacing: 6) {
                    Text(block.title.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.6)
                        .lineLimit(1)
                    Text(timeText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: block.isDone ? "checkmark.circle.fill" : block.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accentColor)
                        Text(block.title.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.8)
                            .lineLimit(2)
                            .strikethrough(block.isDone)
                    }
                    Text(timeText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                    if block.isExternal {
                        Text("Apple-Kalender")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if block.isConflict {
                        Label("Überschneidung", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.warning)
                    }
                }
                .padding(.vertical, 6)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(block.isDone ? Theme.textSecondary : Theme.textPrimary)
        .clipped()
    }

    private var timeText: String {
        var text = Fmt.range(block.start, block.end)
        if block.continuesFromPreviousDay { text = "seit gestern · bis \(Fmt.time(block.end))" }
        else if block.continuesToNextDay { text += " (+1 Tag)" }
        return text
    }

    private var accentColor: Color {
        if block.isConflict { return Theme.warning }
        if block.isSleep || block.isExternal { return Theme.textSecondary }
        return Theme.accentText
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(block.isSleep ? Theme.surface.opacity(0.6) : (block.isTask && !block.isFixed ? Theme.accentFill : Theme.surfaceStrong))
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(block.isConflict ? Theme.warning : (block.isExternal ? Theme.hairline : Color.clear),
                          style: StrokeStyle(lineWidth: block.isConflict ? 1.5 : 1, dash: block.isExternal ? [4, 3] : []))
    }

    @ViewBuilder
    private var resizeHandle: some View {
        if editable && heightPoints >= 40 && !block.continuesToNextDay {
            Capsule()
                .fill(Theme.textSecondary.opacity(0.5))
                .frame(width: 28, height: 4)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)
                .frame(height: 18, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(resizeGesture)
                .accessibilityHidden(true)
        }
    }

    // MARK: Gesten

    private func snappedMinutes(_ points: CGFloat) -> Int {
        let minutes = Double(points / minuteHeight)
        return Int((minutes / 5).rounded()) * 5
    }

    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($isDragging) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .updating($dragOffset) { value, state, _ in
                if case .second(true, let drag?) = value {
                    state = CGFloat(snappedMinutes(drag.translation.height)) * minuteHeight
                }
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value, let item = currentItem else { return }
                let minutes = snappedMinutes(drag.translation.height)
                if minutes != 0 {
                    store.shift(item, byMinutes: minutes)
                    ui.showToast("\(item.title): \(Fmt.range(item.start ?? Date(), item.end ?? Date()))")
                }
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($resizeOffset) { value, state, _ in
                state = CGFloat(snappedMinutes(value.translation.height)) * minuteHeight
            }
            .onEnded { value in
                guard let item = currentItem else { return }
                store.resize(item, endByMinutes: snappedMinutes(value.translation.height))
            }
    }

    private var currentItem: PlanItem? {
        block.itemID.flatMap { store.item(id: $0) }
    }

    private func openEditor() {
        guard let item = currentItem else { return }
        ui.editor = EditorRequest(item: item, defaultStart: nil, defaultDay: item.day, asTask: item.isTask)
    }
}
