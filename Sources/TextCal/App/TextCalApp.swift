import SwiftUI

/// The app entry point. This file is excluded from the TextCalKit library target
/// and is used when building the full app through Xcode.
/// To build: Open Package.swift in Xcode, create a new iOS App target,
/// add TextCalKit as a dependency, then use this file as the entry point.
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
