import EventKit
import SwiftUI

struct CalendarDocumentView: View {
    @Environment(CalendarStore.self) private var store
    @State private var viewModel = CalendarViewModel()
    @State private var showingSyntaxHelp = false
    @State private var showingSearch = false
    @State private var showingDatePicker = false
    @State private var showingCalendarPicker = false
    @State private var showingWeekView = false
    @State private var writableCalendars: [EKCalendar] = []
    @State private var defaultCalendarId: String?
    @State private var pickerDate = DateFormatting.today
    @State private var currentVisibleDate = DateFormatting.today
    @AppStorage("dismissedCalendarPermissionBanner") private var dismissedPermissionBanner = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !store.hasCalendarAccess && !dismissedPermissionBanner {
                    HStack {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text(Strings.calendarAccessDenied)
                            .font(.system(.caption, design: .rounded))
                        Spacer()
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text(Strings.settings)
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.semibold)
                        }
                        Button {
                            dismissedPermissionBanner = true
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Dismiss")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .accessibilityElement(children: .combine)
                }
                ZStack {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.dates, id: \.self) { date in
                                    DaySectionView(date: date) {
                                        pickerDate = date
                                        showingDatePicker = true
                                    }
                                    .id(date)
                                    .onAppear {
                                        viewModel.expandIfNeeded(visibleDate: date)
                                        currentVisibleDate = date
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .defaultScrollAnchor(.center)
                        .onAppear {
                            DispatchQueue.main.async {
                                proxy.scrollTo(DateFormatting.today, anchor: .top)
                            }
                        }
                        .onChange(of: viewModel.scrollTarget) { _, target in
                            if let target {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(target, anchor: .top)
                                }
                                viewModel.scrollTarget = nil
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                            Task { await store.forceSave() }
                        }
                    }

                    // Date scrubber on right edge
                    DateScrubber(
                        startDate: viewModel.dateRangeStart,
                        endDate: viewModel.dateRangeEnd
                    ) { date in
                        viewModel.jumpTo(date: date)
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        viewModel.scrollToToday()
                    } label: {
                        Label("Today", systemImage: "calendar.badge.clock")
                    }
                    .keyboardShortcut("t", modifiers: .command)

                    Spacer()

                    Button {
                        showingSearch = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: .command)

                    Spacer()

                    Button {
                        Task {
                            if let ekManager = store.eventKitManager {
                                writableCalendars = await ekManager.allCalendars()
                            }
                            defaultCalendarId = store.calendarSettings?.defaultCalendarIdentifier
                            showingCalendarPicker = true
                        }
                    } label: {
                        Label("Calendars", systemImage: "calendar")
                    }

                    Spacer()

                    Button {
                        showingSyntaxHelp = true
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    .keyboardShortcut("/", modifiers: .command)
                }
            }
            .toolbarBackground(.visible, for: .bottomBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if case .error(let message) = store.syncStatus {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text(message)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.red)
                            Button {
                                store.syncStatus = .idle
                                Task { await store.retryLastSync() }
                            } label: {
                                Text(Strings.retry)
                                    .font(.system(.caption, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                            .accessibilityLabel("Retry sync")
                            Button {
                                store.syncStatus = .idle
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Dismiss error")
                        }
                        .transition(.opacity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Error: \(message)")
                        .accessibilityHint("Tap retry to try again, or dismiss")
                    } else if store.syncStatus != .idle {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text(store.syncStatus == .saving ? Strings.saving : Strings.syncing)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                        .accessibilityLabel(store.syncStatus == .saving ? "Saving changes" : "Syncing with calendar")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingWeekView = true
                    } label: {
                        Label("Week", systemImage: "calendar.day.timeline.leading")
                    }
                    .accessibilityLabel("Week summary view")
                    .keyboardShortcut("w", modifiers: .command)
                }
            }
            .focusable()
            .onKeyPress(.upArrow) {
                navigateDay(offset: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                navigateDay(offset: 1)
                return .handled
            }
        }
        .sheet(isPresented: $showingSearch) {
            SearchView { date in
                viewModel.jumpTo(date: date)
            }
        }
        .sheet(isPresented: $showingSyntaxHelp) {
            SyntaxHelpView()
        }
        .sheet(isPresented: $showingDatePicker) {
            DateJumpPicker(selectedDate: $pickerDate) { date in
                viewModel.jumpTo(date: date)
            }
        }
        .sheet(isPresented: $showingWeekView) {
            WeekSummaryView(currentDate: currentVisibleDate) { date in
                viewModel.jumpTo(date: date)
            }
        }
        .sheet(isPresented: $showingCalendarPicker) {
            CalendarPickerView(
                calendars: writableCalendars,
                selectedIdentifier: $defaultCalendarId,
                calendarSettings: store.calendarSettings
            )
            .onDisappear {
                store.calendarSettings?.defaultCalendarIdentifier = defaultCalendarId
            }
        }
    }

    private func navigateDay(offset: Int) {
        if let target = Calendar.current.date(byAdding: .day, value: offset, to: currentVisibleDate) {
            viewModel.jumpTo(date: target)
            currentVisibleDate = DateFormatting.normalizeToDay(target)
        }
    }
}
