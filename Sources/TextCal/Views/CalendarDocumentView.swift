import EventKit
import SwiftUI

struct CalendarDocumentView: View {
    @Environment(CalendarStore.self) private var store
    @State private var viewModel = CalendarViewModel()
    @State private var showingSyntaxHelp = false
    @State private var showingDatePicker = false
    @State private var showingCalendarPicker = false
    @State private var writableCalendars: [EKCalendar] = []
    @State private var defaultCalendarId: String?
    @State private var pickerDate = DateFormatting.today

    var body: some View {
        NavigationStack {
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
                            withAnimation(.easeInOut(duration: 0.3)) {
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
                    startDate: viewModel.startDate,
                    endDate: viewModel.endDate
                ) { date in
                    viewModel.jumpTo(date: date)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        viewModel.scrollToToday()
                    } label: {
                        Label("Today", systemImage: "calendar.badge.clock")
                    }

                    Spacer()

                    Button {
                        Task {
                            if let ekManager = store.eventKitManager {
                                writableCalendars = await ekManager.writableCalendars()
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
                }
            }
            .toolbarBackground(.visible, for: .bottomBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingSyntaxHelp) {
            SyntaxHelpView()
        }
        .sheet(isPresented: $showingDatePicker) {
            DateJumpPicker(selectedDate: $pickerDate) { date in
                viewModel.jumpTo(date: date)
            }
        }
        .sheet(isPresented: $showingCalendarPicker) {
            CalendarPickerView(
                calendars: writableCalendars,
                selectedIdentifier: $defaultCalendarId
            )
            .onDisappear {
                store.calendarSettings?.defaultCalendarIdentifier = defaultCalendarId
            }
        }
    }
}
