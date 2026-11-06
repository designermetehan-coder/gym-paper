import SwiftUI
import SwiftData
import WatchKit
import WatchConnectivity

/// GYM Paper — Apple Watch. Veriler iPhone ile aynı iCloud (CloudKit) veritabanından gelir.
@main
struct BalliWatchApp: App {
    let container: ModelContainer
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @State private var workout = WatchWorkout.shared
    @Environment(\.scenePhase) private var phase

    init() {
        // Saatin verisi yalnız iPhone'dan gelir (WatchConnectivity); iCloud kullanılmaz, çift kayıt oluşmaz
        let schema = AppSchema.schema
        if let c = try? ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: ModelConfiguration("BalliWatch", schema: schema, cloudKitDatabase: .none)) {
            container = c
        } else {
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        // Plan hesabı profile bağlı; ilk açılışta boş profil oluşsun
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
                .tint(Color.wAction)   // metin butonları ve başlık neon lime
                // Gün değişince ya da öne gelince komplikasyonlar tazelensin (TE-12); adım ve aktif kalori de okunur (WC-01, WC-03)
                .onChange(of: phase, initial: true) { _, p in
                    guard p == .active else { return }
                    WLogic.publish(container.mainContext)
                    PhoneSync.shared.requestSync()   // plan değişikliği kaçmasın (4 Kas)
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
        // iPhone'dan gelen veri arka planda da işlensin (telefonda başlayan antrenman bildirimi, 4 Kas)
        .backgroundTask(.watchConnectivity) {
            for _ in 0..<20 {
                if !WCSession.default.hasContentPending { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        // Arka planda ~15 dakikada bir adım ve aktif kalori okunur; köşe göstergeleri güncel kalır
        .backgroundTask(.appRefresh(ComplicationRefresh.id)) {
            await WHealth.refresh()
            await MainActor.run { WLogic.publish(container.mainContext); ComplicationRefresh.schedule() }
        }
    }
}

/// Köşe göstergeleri için arka plan yenilemesi (WC-01, WC-03). Saat yüzünde komplikasyon varken sistem saatte birkaç kez izin verir.
enum ComplicationRefresh {
    static let id = "gp.complications"
    static func schedule() {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date().addingTimeInterval(15 * 60), userInfo: id as NSString) { _ in }
    }
}

/// Uygulama antrenman sırasında çökerse/kapanırsa sistem yeniden açar; oturum geri bağlanır (WT-14)
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in await WatchWorkout.shared.recover() }
    }
}
