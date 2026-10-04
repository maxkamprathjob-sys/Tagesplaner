import SwiftUI
import PlannerCore

/// Hauptansicht: Tageskopf, Tagesanalyse, Tagesplan | Aufgaben, Schnelleingabe.
/// Auf dem iPhone werden Zeitplan (links) und To-do-Liste (rechts) als zwei
/// Seiten dargestellt, zwischen denen man umschaltet oder wischt.
struct RootView: View {
    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var calendarService: CalendarService

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayHeaderView()
                DayLoadBanner(day: ui.selectedDay)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                Picker("Ansicht", selection: $ui.tab) {
                    ForEach(UIState.Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                TabView(selection: $ui.tab) {
                    DayTimelineView(day: ui.selectedDay)
                        .tag(UIState.Tab.plan)
                    TaskListView(day: ui.selectedDay)
                        .tag(UIState.Tab.tasks)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { QuickAddBar() }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) { ToastView() }
        }
        .sheet(isPresented: $ui.showQuickAdd) {
            QuickAddView()
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.background)
        }
        .sheet(item: $ui.editor) { request in
            ItemEditorView(request: request)
                .presentationBackground(Theme.background)
        }
        .sheet(item: $ui.planning) { session in
            SuggestionSheet(session: session)
                .presentationDetents([.height(360), .large])
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $ui.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $ui.showPlanDay) {
            PlanDayView(day: ui.selectedDay)
                .presentationBackground(Theme.background)
        }
        .alert("Hinweis", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .task { await store.refreshIntegrations() }
    }
}

/// Kurzmeldung oben (z. B. "Eingeplant: 17:00–19:00").
struct ToastView: View {
    @EnvironmentObject private var ui: UIState

    var body: some View {
        if let text = ui.toast {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.surfaceStrong, in: Capsule())
                .overlay(Capsule().stroke(Theme.accent.opacity(0.6), lineWidth: 1))
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { ui.toast = nil }
        }
    }
}
