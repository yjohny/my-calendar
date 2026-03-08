import SwiftUI

@main
struct TextCalApp: App {
    @State private var store = CalendarStore()

    var body: some Scene {
        WindowGroup {
            CalendarDocumentView()
                .environment(store)
                .task {
                    let fileStore = FileStore()
                    let coalescer = ChangeCoalescer()
                    store.configure(fileStore: fileStore, coalescer: coalescer)
                    await store.load()
                }
        }
    }
}
