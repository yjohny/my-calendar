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
                    let settings = CalendarSettings()
                    let baseURL = await Self.resolveBaseURL(settings: settings)
                    let usingCloud = settings.iCloudSyncEnabled && baseURL != FileStore.localBaseURL()
                    let eventKitManager = EventKitManager()
                    let fileStore = FileStore(baseURL: baseURL)
                    let templateStore = TemplateStore(baseURL: baseURL)
                    let coalescer = ChangeCoalescer()
                    let cloudWatcher: CloudWatcher? = usingCloud ? CloudWatcher() : nil
                    store.configure(
                        eventKitManager: eventKitManager,
                        fileStore: fileStore,
                        coalescer: coalescer,
                        calendarSettings: settings,
                        templateStore: templateStore,
                        cloudWatcher: cloudWatcher
                    )
                    await store.load()
                    cloudWatcher?.start()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task { await store.forceSave() }
            }
        }
    }

    /// Pick the storage base URL based on the user's iCloud preference and
    /// seed the chosen location with any files from the other so toggling the
    /// setting doesn't strand the journal. Falls back to local Documents if
    /// iCloud is requested but unavailable (not signed in, container not
    /// provisioned). `url(forUbiquityContainerIdentifier:)` can block on
    /// first call, so resolution runs on a detached task.
    @MainActor
    private static func resolveBaseURL(settings: CalendarSettings) async -> URL {
        let local = FileStore.localBaseURL()
        let cloud = await Task.detached(priority: .userInitiated) {
            FileStore.cloudBaseURL()
        }.value

        if settings.iCloudSyncEnabled, let cloud {
            try? FileStore.migrateTextCalTree(from: local, to: cloud)
            return cloud
        }
        if let cloud {
            try? FileStore.migrateTextCalTree(from: cloud, to: local)
        }
        return local
    }
}
