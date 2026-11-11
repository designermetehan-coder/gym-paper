import SwiftUI
import SwiftData
import WatchKit
import WatchConnectivity

/// GYM Paper — Apple Watch.
@main
struct GymPaperWatchApp: App {
    let container: ModelContainer
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @State private var workout = WatchWorkout.shared
    @Environment(\.scenePhase) private var phase

    init() {
        // the watch's data comes only from iPhone (WatchConnectivity); no iCloud, so no duplicate records
        let schema = AppSchema.schema
        if let c = try? ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: ModelConfiguration("GymPaperWatch", schema: schema, cloudKitDatabase: .none)) {
            container = c
        } else {
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        // plan math depends on the profile; create an empty one on first launch
        _ = Store.profile(container.mainContext)
        try? container.mainContext.save()
        PhoneSync.shared.activate(container)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let s = WShot.screen { WShotRoot(screen: s) } else { NavigationStack { HomeView().wRoutes() } }
                #else
                NavigationStack { HomeView().wRoutes() }
                #endif
            }
                .environment(workout)
                .tint(Color.wAction)   // text buttons and the title in neon lime
                // refresh complications when the day changes or the app comes forward; steps and active calories are read too
                .onChange(of: phase, initial: true) { _, p in
                    guard p == .active else { return }
                    WLogic.publish(container.mainContext)
                    PhoneSync.shared.requestSync()   // don't miss plan changes
                    WLiveNotice.requestAuth()
                    let ctx = container.mainContext
                    Task { @MainActor in
                        await WatchWorkout.shared.requestAuth()
                        await WHealth.refresh(); WLogic.publish(ctx)
                        ComplicationRefresh.schedule()
                    }
                }
        }
        .modelContainer(container)
        // handle data from iPhone in the background too (notice for a workout started on the phone)
        .backgroundTask(.watchConnectivity) {
            for _ in 0..<20 {
                if !WCSession.default.hasContentPending { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        // steps and active calories are read about every 15 minutes in the background so corner complications stay current
        .backgroundTask(.appRefresh(ComplicationRefresh.id)) {
            await WHealth.refresh()
            await MainActor.run { WLogic.publish(container.mainContext); ComplicationRefresh.schedule() }
        }
    }
}

/// Background refresh for corner complications. With a complication on the face the system allows a few per hour.
enum ComplicationRefresh {
    static let id = "gp.complications"
    static func schedule() {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date().addingTimeInterval(15 * 60), userInfo: id as NSString) { _ in }
    }
}

/// If the app crashes/closes during a workout the system relaunches it and the session reattaches
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in await WatchWorkout.shared.recover() }
    }
}
