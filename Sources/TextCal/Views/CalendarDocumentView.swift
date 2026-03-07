import SwiftUI

struct CalendarDocumentView: View {
    @Environment(CalendarStore.self) private var store
    @State private var viewModel = CalendarViewModel()
    @State private var hasScrolledToToday = false

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.dates, id: \.self) { date in
                            DaySectionView(date: date)
                                .id(date)
                                .onAppear {
                                    viewModel.expandIfNeeded(visibleDate: date)
                                }
                        }
                    }
                }
                .onAppear {
                    if !hasScrolledToToday {
                        // Small delay to let LazyVStack render
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(DateFormatting.today, anchor: .top)
                            hasScrolledToToday = true
                        }
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

            TodayButtonOverlay {
                viewModel.scrollToToday()
            }
        }
        .background(Color(.systemBackground))
    }
}
