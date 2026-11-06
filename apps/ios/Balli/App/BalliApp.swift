import SwiftUI
import SwiftData
import AppIntents
import BalliKit

@main
struct BalliApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var health = HealthService()
    let container: ModelContainer
    /// Veritabanı yedek yola düştüyse kullanıcıya gösterilecek uyarı (CR-29)
    nonisolated(unsafe) static var storageWarning: String?

    init() {
        let schema = AppSchema.schema
        // iCloud (CloudKit) özel veritabanı; hesap yoksa yerel kalır, sonradan eşitlenir
        let local = ProcessInfo.processInfo.arguments.contains("-demo")
        #if LITE
        // Lite: iCloud izni yok; aynı dosya adı, tam sürüme geçince veri korunur
        let cloud = ModelConfiguration(local ? "BalliDemo" : "Balli", schema: schema, cloudKitDatabase: .none)
        #else
        let cloud = local
            ? ModelConfiguration("BalliDemo", schema: schema, cloudKitDatabase: .none)   // CI ekran görüntüsü: imzasız derleme, iCloud yok
            : ModelConfiguration("Balli", schema: schema, cloudKitDatabase: .private("iCloud.com.metehankaya.balli"))
        #endif
        // iCloud açılamazsa aynı dosya yerel açılır (veri bölünmez); o da olmazsa yedek dosya, en son bellek (CR-03)
        if let c = try? ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: cloud) {
            container = c
        } else if let c = try? ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: ModelConfiguration(local ? "BalliDemo" : "Balli", schema: schema, cloudKitDatabase: .none)) {
            container = c
            Self.storageWarning = tl("iCloud eşitlemesi şu an kapalı; veriler bu cihazda tutuluyor.")
        } else if let c = try? ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: ModelConfiguration("BalliLocal", schema: schema, cloudKitDatabase: .none)) {
            container = c
            Self.storageWarning = tl("Verilerin açılamadı; geçici bir kayıt alanı kullanılıyor. Uygulamayı yeniden başlat; sorun sürerse bize yaz.")
        } else {
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            Self.storageWarning = tl("Verilerin açılamadı; bu oturumda girdiklerin kaydedilmeyecek. Uygulamayı yeniden başlat.")
        }
        BTips.configure()   // ON-03
        #if !LITE
        WatchSync.shared.activate(container)
        // Kestirme/Siri ile eklenen su uygulama açıkken hemen kayda işlensin (TE-12)
        let c = container
        Self.waterObserver = NotificationCenter.default.addObserver(forName: .balliWaterAdded, object: nil, queue: .main) { _ in
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
        // Adım widget'ı için arka plan yenilemesi (WG-10)
        .backgroundTask(.appRefresh(StepRefresh.id)) {
            await StepRefresh.run()
            StepRefresh.schedule()
        }
    }
}

// MARK: - Kestirmeler ve Siri (TE-12)

struct BalliShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartWorkoutIntent(), phrases: [
            "\(.applicationName) ile antrenmanı başlat",
            "\(.applicationName) antrenmanı başlat",
            "Antrenmanı \(.applicationName) ile başlat",
        ], shortTitle: "Antrenmanı başlat", systemImageName: "dumbbell.fill")
        #if !LITE
        // Lite'ta App Group yok: su kuyruğu yazılamaz
        AppShortcut(intent: AddWaterIntent(), phrases: [
            "\(.applicationName) ile su ekle",
            "\(.applicationName) su ekle",
            "\(.applicationName) bir bardak su",
        ], shortTitle: "Su ekle", systemImageName: "drop.fill")
        #endif
    }
}

extension AppState {
    /// Bugünün antrenmanı: Antrenman sekmesine geçer, varsa oynatıcıyı açar/başlatır; yoksa dinlenme der (TE-12)
    func startTodayWorkout(_ ctx: ModelContext) {
        let date = DayKey.today
        sheet = nil
        setTab(.workout)
        guard let p = Wk.programFor(date, profile: Store.profile(ctx), ctx: ctx) else { toast("Bugün dinlenme günü"); return }
        openSession(.init(pid: p.pid, date: date))
    }
}
