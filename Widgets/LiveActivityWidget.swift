import ActivityKit
import WidgetKit
import SwiftUI

/// Laufender Block auf dem Sperrbildschirm und in der Dynamic Island.
struct DayLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DayActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "tagesplaner://today"))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(s.title).font(.headline).lineLimit(1)
                    } icon: {
                        Image(systemName: s.symbol).foregroundStyle(Theme.accentText)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.isStale {
                        Text(timerInterval: s.start...s.end, countsDown: true)
                            .monospacedDigit()
                            .font(.headline)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(timerInterval: s.start...s.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(Theme.accentText)
                        HStack {
                            Text(Fmt.range(s.start, s.end)).font(.caption.monospaced())
                            Spacer()
                            if let next = s.nextTitle, let ns = s.nextStart {
                                Text("Danach \(Fmt.time(ns)) \(next)").font(.caption).lineLimit(1)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: s.symbol).foregroundStyle(Theme.accentText)
            } compactTrailing: {
                Text(timerInterval: s.start...s.end, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
                    .font(.caption2.weight(.semibold))
            } minimal: {
                Image(systemName: s.symbol).foregroundStyle(Theme.accentText)
            }
            .widgetURL(URL(string: "tagesplaner://today"))
        }
    }
}

struct LockScreenActivityView: View {
    let state: DayActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(isStale ? "BEENDET" : "AKTUELL")
                    .font(.caption.weight(.heavy)).tracking(1)
                    .foregroundStyle(Color(red: 0.77, green: 0.68, blue: 1.0))
                Spacer()
                if !isStale {
                    Text(timerInterval: state.start...state.end, countsDown: true)
                        .monospacedDigit()
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.white)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: state.symbol)
                Text(state.title.uppercased()).font(.title3.weight(.bold)).lineLimit(1)
            }
            .foregroundStyle(.white)
            Text(Fmt.range(state.start, state.end)).font(.subheadline.monospaced()).foregroundStyle(.white.opacity(0.7))
            if !isStale {
                ProgressView(timerInterval: state.start...state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(Color(red: 0.49, green: 0.30, blue: 0.86))
            }
            if let next = state.nextTitle, let ns = state.nextStart {
                Text("NÄCHSTER: \(Fmt.time(ns)) \(next)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(16)
    }
}
