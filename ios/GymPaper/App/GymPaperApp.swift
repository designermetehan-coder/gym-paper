import SwiftUI
import SwiftData
import AppIntents
import GymPaperKit

@main
struct GymPaperApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var health = HealthService()
    let container: ModelContainer
    /// Warning shown when the database fell back to a backup location
    nonisolated(unsafe) static var storageWarning: String?

    init() {
        let schema = AppSchema.schema
        // iCloud (CloudKit) private database; stays local without an account and syncs later
        let local = ProcessInfo.processInfo.arguments.contains("-demo")
        #if LITE
        // Lite: no iCloud entitlement; same file name, so data carries over to the full version
        let cloud = ModelConfiguration(local ? "GymPaperDemo" : "GymPaper", schema: schema, cloudKitDatabase: .none)
        #else
        let cloud = local
            ? ModelConfiguration("GymPaperDemo", schema: schema, cloudKitDatabase: .none)   // CI screenshots: unsigned build, no iCloud
            : ModelConfiguration("GymPaper", schema: schema, cloudKitDatabase: .private(AppConfig.iCloudContainer))
        #endif
        // If iCloud fails, open the same file locally (no data split); then a backup file; memory as a last resort
        if let c = try? ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: cloud) {
            container = c
        } else if let c = try? ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: ModelConfiguration(local ? "GymPaperDemo" : "GymPaper", schema: schema, cloudKitDatabase: .none)) {
            container = c
            Self.storageWarning = tl("iCloud eşitlemesi şu an kapalı; veriler bu cihazda tutuluyor.")
        } else if let c = try? ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: ModelConfiguration("GymPaperLocal", schema: schema, cloudKitDatabase: .none)) {
            container = c
            Self.storageWarning = tl("Verilerin açılamadı; geçici bir kayıt alanı kullanılıyor. Uygulamayı yeniden başlat; sorun sürerse bize yaz.")
        } else {
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            Self.storageWarning = tl("Verilerin açılamadı; bu oturumda girdiklerin kaydedilmeyecek. Uygulamayı yeniden başlat.")
        }
        BTips.configure()   // ON-03
        #if !LITE
        WatchSync.shared.activate(container)
        // Water added from Shortcuts/Siri is applied right away while the app is open
        let c = container
        Self.waterObserver = NotificationCenter.default.addObserver(forName: .gymPaperWaterAdded, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WidgetSync.applyPending(ctx: c.mainContext) }
        }
        #endif
    }
    nonisolated(unsafe) private static var waterObserver: NSObjectProtocol?

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(health)
                .tint(Color.bPrimary)
                .font(.geist(16))
        }
        .modelContainer(container)
        // Background refresh for the steps widget
        .backgroundTask(.appRefresh(StepRefresh.id)) {
            await StepRefresh.run()
            StepRefresh.schedule()
        }
    }
}

// MARK: - Shortcuts and Siri

struct GymPaperShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartWorkoutIntent(), phrases: [
            "\(.applicationName) ile antrenmanı başlat",
            "\(.applicationName) antrenmanı başlat",
            "Antrenmanı \(.applicationName) ile başlat",
        ], shortTitle: "Antrenmanı başlat", systemImageName: "dumbbell.fill")
        #if !LITE
        // Lite has no App Group: the water queue can't be written
        AppShortcut(intent: AddWaterIntent(), phrases: [
            "\(.applicationName) ile su ekle",
            "\(.applicationName) su ekle",
            "\(.applicationName) bir bardak su",
        ], shortTitle: "Su ekle", systemImageName: "drop.fill")
        #endif
    }
}

extension AppState {
    /// Today's workout: switches to the Workout tab and opens or starts the player; says rest day otherwise
    func startTodayWorkout(_ ctx: ModelContext) {
        let date = DayKey.today
        sheet = nil
        setTab(.workout)
        guard let p = Wk.programFor(date, profile: Store.profile(ctx), ctx: ctx) else { toast("Bugün dinlenme günü"); return }
        openSession(.init(pid: p.pid, date: date))
    }
}
