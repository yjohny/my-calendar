import SwiftUI

@main
struct TextCalApp: App {
    @State private var store = CalendarStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CalendarDocumentView()
                .environment(store)
                .task {
                    let eventKitManager = EventKitManager()
                    let fileStore = FileStore()
                    let coalescer = ChangeCoalescer()
                    store.configure(
                        eventKitManager: eventKitManager,
                        fileStore: fileStore,
                        coalescer: coalescer,
                        calendarSettings: CalendarSettings()
                    )
                    await store.load()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task { await store.forceSave() }
            }
        }
    }
}
