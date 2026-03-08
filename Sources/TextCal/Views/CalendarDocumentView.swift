import SwiftUI

struct CalendarDocumentView: View {
    @Environment(CalendarStore.self) private var store
    @State private var viewModel = CalendarViewModel()

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

            TodayButtonOverlay {
                viewModel.scrollToToday()
            }
        }
        .background(Color(.systemBackground))
    }
}
