import SwiftUI
import SwiftData
import Combine
import TipKit
import CoreData
import BalliKit

struct RootView: View {
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var phase
    @Environment(\.horizontalSizeClass) private var hsc
    /// Sekme içeriğinin güvenli alanı (sekme çubuğu dahil) ve kök güvenli alan: mini oynatıcıyı
    /// sekme çubuğu nerede olursa olsun (altta, yanda — iPhone Duo) onun hemen üstüne/yanına yerleştirmek için
    @State private var tabInsets = EdgeInsets()
    @State private var rootInsets = EdgeInsets()
    @AppStorage("healthAsked") private var healthAsked = false
    /// İlk açılış akışı (TE-12): bir kez; veri varsa hiç gösterilmez
    @AppStorage(Onboarding.key) private var onboarded = false
    enum OnbPhase { case checking, showing, done }
    @State private var onb: OnbPhase = UserDefaults.standard.bool(forKey: Onboarding.key) ? .done : .checking
    @State private var app = AppState()
    /// Açılış ekranının devamı: logo kısa bir geçişle açılıp uygulamaya yerini bırakır (SP-01); ekran görüntüsü modunda yok
    @State private var lastDedupe = Date.distantPast
    @State private var splash = !ProcessInfo.processInfo.arguments.contains("-demo")
    /// Fontlar çizim anında ölçeklenir; yazı boyutu değişince sekmeler yeniden kurulsun (CR-29)
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var playerNS
    private let restTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// Mini oynatıcının alt boşluğu: sekme çubuğunun kapladığı alan + 8 (ölçülemezse eski sabitler)
    private var miniBottom: CGFloat {
        let bar = tabInsets.bottom - rootInsets.bottom
        if tabInsets.bottom > 0 { return bar > 20 ? bar + 8 : 12 }
        return hsc == .regular ? 16 : (iOS26 ? 74 : 58)
    }
    private var iOS26: Bool { if #available(iOS 26, *) { return true } else { return false } }

    /// Sekme ikonu: seçili değilken çizgi, seçiliyken dolu; seçilince hafif zıplar
    private func tabLabel(_ t: AppTab) -> some View {
        Label(t.label, systemImage: t.symbol)
            .environment(\.symbolVariants, app.tab == t ? .fill : .none)
            .symbolEffect(.bounce.down, value: app.tab == t)
    }

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .bottom) {
            // Yerel (native) tab bar: iOS 26'da liquid glass ve büyüme efekti sistemden gelir
            TabView(selection: $app.tab) {
                Tab(value: AppTab.today) { NavigationStack { TodayView() }.tint(Color.bPrimary).modifier(TabInsetReader(insets: $tabInsets)) } label: { tabLabel(.today) }
                Tab(value: AppTab.workout) { NavigationStack(path: $app.workoutPath) { WorkoutView() }.tint(Color.bPrimary).modifier(TabInsetReader(insets: $tabInsets)) } label: { tabLabel(.workout) }
                Tab(value: AppTab.food) { NavigationStack { NutritionView() }.tint(Color.bPrimary).modifier(TabInsetReader(insets: $tabInsets)) } label: { tabLabel(.food) }
                if AppTab.socialEnabled {
                    Tab(value: AppTab.social) { NavigationStack { SocialView() }.tint(Color.bPrimary).modifier(TabInsetReader(insets: $tabInsets)) } label: { tabLabel(.social) }
                }
                Tab(value: AppTab.profile) { NavigationStack { ProfileView() }.tint(Color.bPrimary).modifier(TabInsetReader(insets: $tabInsets)) } label: { tabLabel(.profile) }
            }
            // seçili sekme: koyuda marka lime, açıkta ana renk (GP-06); içerik eski vurgusunu korur
            .tint(Color.bTab)
            .id(typeSize)
            // Kenar çubuğu yok: Duo'nun iç ve dış ekranında sekmeler sistemin sağdaki kontrol sütununda (ikon),
            // iPhone'da alt çubuk. .sidebarAdaptable geniş ekranda soldaki kenar çubuğunu açıyordu (2 Kas)
            .tabViewStyle(.tabBarOnly)
            .environment(\.miniPlayerInset, app.session != nil && app.sessionMin ? 76 : 0)
            .sensoryFeedback(.selection, trigger: app.tab)
            // Oynatıcı: sheet olarak açılır; aşağı kaydırınca/küçültünce mini oynatıcıya "zoom" ile döner (Apple Music gibi)
            .fullScreenCover(item: Binding(get: { app.sessionMin ? nil : app.session },
                                 set: { v in if v == nil, app.session != nil, !app.sessionMin { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { app.sessionMin = true } } })) { s in
                SessionView(pid: s.pid, date: s.date)
                    .environment(app).environment(health)
                    .interactiveDismissDisabled(app.rt.finished)   // bitiş ekranı küçültülmez
                    .background(Color.bBg.ignoresSafeArea())
                    // Apple Music gibi: mini oynatıcıdan büyür, aşağı sürükleyince parmağı izleyerek ona küçülür
                    .navigationTransition(.zoom(sourceID: "player", in: playerNS))
            }
            // Mini oynatıcı: seans varken hep yerinde durur (oynatıcı açıkken görünmez) — böylece sheet kapanırken
            // Apple Music'teki gibi kapak/kart bu çubuğun içine "zoom" ile küçülür
            // Mini oynatıcının arkası için ayrı bulanıklık yok: ekranın alt bulanıklığı (BScreen) oynatıcıyı da kapsayacak kadar uzar;
            // iki ayrı katman üst üste binip oynatıcı hizasında kesik bir çizgi oluşturuyordu (4 Kas)
            if app.session != nil {
                MiniPlayer(now: app.sessionNow ?? .init(program: "", exercise: tl("Antrenman"), detail: ""), expand: { app.minimizeSession(false) })
                    .matchedTransitionSource(id: "player", in: playerNS) { src in
                        src.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 20)
                    // Sekme çubuğu yandaysa (iPhone Duo) onun altına girmesin
                    .padding(.leading, max(0, tabInsets.leading - rootInsets.leading))
                    .padding(.trailing, max(0, tabInsets.trailing - rootInsets.trailing))
                    // Sekme çubuğunun hemen üstü; çubuk altta değilse ekranın altına iner
                    .padding(.bottom, miniBottom)
                    // tam ekran oynatıcının altında hep hazır: zoom geçişi tam bu çubuğa iner (gecikmeli solma yok)
                    .allowsHitTesting(app.sessionMin)
            }
            // İlk açılış: veri denetlenirken düz zemin, sonra akış (sekmeler arkada yüklenir)
            if onb != .done {
                Group {
                    if onb == .showing { OnboardingView(onFinish: finishOnboarding).balliTheme() }
                    else { Color.bBg.ignoresSafeArea() }
                }
                .environment(app)
                .transition(.opacity)
                .zIndex(5)
            }
            ToastOverlay().zIndex(6)
            if splash { SplashOverlay { splash = false }.zIndex(10) }
        }
        .background(Color.bBg.ignoresSafeArea())
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { rootInsets = $0 }
        .environment(app)
        .confirmationDialog("Açık bir antrenman var", isPresented: Binding(get: { app.switchTo != nil }, set: { if !$0 { app.switchTo = nil } }), titleVisibility: .visible) {
            Button("Açık antrenmana dön") { app.switchTo = nil; app.minimizeSession(false) }
            Button("Yenisini başlat") {
                if let s = app.switchTo { app.switchTo = nil; app.closeSession(); app.openSession(s, force: true) }
            }
            Button("Vazgeç", role: .cancel) { app.switchTo = nil }
        } message: {
            Text("\(app.sessionNow?.program ?? tl("Önceki antrenman")) yarım. Yenisini başlatırsan o gün kaldığın yerden sonra devam edebilirsin.")
        }
        .modifier(RootShots(app: app))
        .sheet(item: $app.sheet) { s in
            Group {
                switch s {
                case .addFood(let d, let m): AddFoodSheet(date: d, meal: m)
                case .cheat(let d): CheatSheet(date: d)
                case .measure(let q): MeasureSheet(quick: q)
                case .importProgram(let p): WkImportSheet(payload: p)
                }
            }
            .environment(app).environment(health)
        }
        #if DEBUG
        .overlay { if DemoTour.active { TourTouchOverlay() } }   // kapak videosu dokunma halkası
        #endif
        .task {
            if let w = BalliApp.storageWarning { app.toast(w, kind: .error) }
            Store.dedupe(ctx)
            _ = Store.profile(ctx)
            if StartWorkoutRequest.take() { app.startTodayWorkout(ctx) }   // soğuk açılış: Kestirme/Denetim Merkezi (TE-12)
            UserMotion.shared.load(ctx)
            FoodImages.shared.load(ctx)
            #if DEBUG
            DemoData.seedIfRequested(ctx: ctx, app: app)
            if DemoTour.active { Task { await DemoTour.run(app: app, ctx: ctx) } }   // kapak videosu gezintisi
            if DemoData.active { onb = DemoData.onboarding ? .showing : .done; return }   // ekran görüntüsü modu: Sağlık izni sorma
            #endif
            WidgetSync.applyPending(ctx: ctx)
            LiveSession.endOrphans()             // önceki çalıştırmadan kalan etkinlik
            // Bu cihazda ya da iCloud'da veri varsa (güncelleme, yeni cihaz) ilk açılış akışı atlanır (TE-12)
            if !onboarded, Onboarding.hasData(ctx) { onboarded = true; onb = .done }
            if onboarded { await afterOnboarding() } else { onb = .showing }
        }
        .onChange(of: onb, initial: true) { _, v in TipGate.appReady = (v == .done) }   // ilk açılış akışında ipucu yok
        .onChange(of: phase) { _, p in
            switch p {
            case .active:
                WidgetSync.applyPending(ctx: ctx)
                Task { await health.refresh(); WidgetSync.update(ctx: ctx, health: health); WatchSync.shared.push(); if AppTab.socialEnabled { await SocialService.shared.push(health.weekSteps) } }
                Notifier.openSession(nil)
                Notifier.invalidate()   // izin Ayarlar'dan değişmiş olabilir
                Notifier.reschedule(ctx)
                LiveFast.sync(Store.profile(ctx))
            case .background:
                WidgetSync.update(ctx: ctx, health: health)
                Store.save(ctx); WatchSync.shared.push()   // plan değişikliği saate kaçmasın (WT-15)
                LiveFast.sync(Store.profile(ctx))
                Notifier.reschedule(ctx)
                Notifier.openSession(app.session != nil && !app.rt.finished ? (app.sessionNow?.program ?? tl("Antrenman")) : nil)
            default: break
            }
        }
        // Paylaşılan antrenman: gympaper://p?d=… ya da https://gympaper.vercel.app/p#…
        .onOpenURL { url in
            // gympaper://start → bugünün antrenmanı (TE-12)
            if url.scheme == "gympaper", url.host == "start" { app.startTodayWorkout(ctx); return }
            // Widget'tan sekme: gympaper://tab/workout | food | today | profile
            if url.scheme == "gympaper", url.host == "tab" {
                if let t = AppTab(rawValue: url.lastPathComponent) {
                    app.sheet = nil
                    if app.session != nil { app.sessionMin = true }
                    app.setTab(t)
                }
                return
            }
            guard let p = WkShare.payload(from: url) else { return }
            // Açık oynatıcı ya da sheet varken önce onlar kapansın, sonra içe aktarma açılsın (PR-04)
            let busy = app.sheet != nil || (app.session != nil && !app.sessionMin)
            if app.session != nil { app.sessionMin = true }
            app.sheet = nil
            Task { try? await Task.sleep(for: .milliseconds(busy ? 650 : 50)); app.open(.importProgram(payload: p)) }
        }
        // Kayıt hatası artık sessiz değil; art arda gelirse tek uyarı (CR-14)
        .onReceive(NotificationCenter.default.publisher(for: .balliSaveFailed).throttle(for: .seconds(10), scheduler: RunLoop.main, latest: false)) { _ in
            app.toast("Değişiklik kaydedilemedi. Tekrar dene; sürerse uygulamayı yeniden başlat.", kind: .error)
        }
        .onReceive(NotificationCenter.default.publisher(for: .balliStartWorkout).receive(on: RunLoop.main)) { _ in
            if StartWorkoutRequest.take() { app.startTodayWorkout(ctx) }   // (TE-12)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { a in
            if let url = a.webpageURL, let p = WkShare.payload(from: url) { app.open(.importProgram(payload: p)) }
        }
        // Gece yarısını uygulama açıkken geçince dünün adım/aktif kalorisi kalmasın (CR-32)
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            Task { await health.refresh(); WidgetSync.update(ctx: ctx, health: health); WatchSync.shared.push() }
            Notifier.reschedule(ctx)
        }
        .onChange(of: app.sessionNow) { _, n in LiveSession.sync(n, active: app.session != nil) }
        // Dinlenme bitişi: arka planda bildirim; küçültülmüşken burada biter (WK-02/03)
        .onChange(of: app.rt.rest) { _, r in
            if let r, r.left == nil, app.session != nil { RestAlarm.schedule(at: r.end, next: app.rt.restNext ?? app.sessionNow.map { "\($0.exercise) · \($0.setText)" }) }
            else { RestAlarm.cancel() }
        }
        .onReceive(restTick) { t in
            guard app.session != nil, app.sessionMin else { return }
            if let r = app.rt.rest, r.left == nil, r.end <= t {
                RestAlarm.beep(); app.rt.rest = nil
                if var n = app.sessionNow { n.restEnd = nil; n.detail = n.setText; app.sessionNow = n }
            }
            if let x = app.rt.timer, x.left == nil, x.end <= t { RestAlarm.beep(); app.rt.timer = nil }
        }
        .onChange(of: app.session, initial: true) { _, s in
            if s == nil { LiveSession.end() }
            // Saate haber ver: telefonda başlayan antrenman saatte bildirim olarak görünür (4 Kas)
            WatchSync.shared.setLive(s.flatMap { $0.date == DayKey.today ? "\($0.date)|\($0.pid)" : nil })
        }
        // Diğer cihazdan gelen iCloud değişiklikleri: çiftleri birleştir, widget'ı tazele (CR-01, WG-13)
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).debounce(for: .seconds(2), scheduler: RunLoop.main)) { _ in
            // Art arda gelen iCloud değişikliklerinde tüm tablolar en fazla 20 sn'de bir taranır (PF-04)
            if Date.now.timeIntervalSince(lastDedupe) > 20 { Store.dedupe(ctx); lastDedupe = .now }
            else {
                // Atlanan son değişiklik de birleştirilsin
                Task { try? await Task.sleep(for: .seconds(21)); if Date.now.timeIntervalSince(lastDedupe) > 20 { Store.dedupe(ctx); lastDedupe = .now } }
            }
            // İlk açılış sürerken iCloud'dan veri geldiyse akış gereksiz: kapat (akış bitene kadar yerelde bir şey yazılmaz)
            if onb == .showing, !ProcessInfo.processInfo.arguments.contains("-demo"), Onboarding.hasData(ctx) {
                finishOnboarding()
                app.toast("iCloud'daki verilerin yüklendi")
            }
            FoodImages.shared.load(ctx); UserMotion.shared.load(ctx)
            WidgetSync.update(ctx: ctx, health: health)
            WatchSync.shared.push()
        }
        // Her kayıtta widget'ları güncelle (değişmediyse yazmaz)
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in
            WidgetSync.update(ctx: ctx, health: health)
            Notifier.reschedule(ctx)
            WatchSync.shared.push()
        }
    }
}

extension RootView {
    /// Sağlık izni, adım gözlemi, widget ve bildirim izni: ilk açılış akışından sonra (ya da her açılışta) (TE-12)
    private func afterOnboarding() async {
        // Her açılışta istenir: zaten yanıtlanan türler için iOS ekran göstermez, yeni eklenen türler sorulur (CR-22)
        healthAsked = true
        await health.requestAccess()
        health.startStepUpdates()
        WidgetSync.update(ctx: ctx, health: health)
        await Notifier.askOnce()
        Notifier.invalidate()
        Notifier.reschedule(ctx)
    }

    private func finishOnboarding() {
        onboarded = true
        withAnimation(.easeInOut(duration: 0.35)) { onb = .done }
        Task { await afterOnboarding() }
    }
}

/// Mini oynatıcı: program, hareket, dinlenme geri sayımı ve ilerleme; dokununca büyür
struct MiniPlayer: View {
    let now: AppState.SessionNow
    var expand: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // Poster bir kez alınır; 15 fps'lik geri sayımda her karede yeniden aranmasın (CR-06)
        let poster = Motion.poster(now.exercise)
        Button(action: expand) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.bPrimary.opacity(0.14))
                    if let img = poster {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay { if now.restEnd != nil { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.45)) } }
                    }
                    if let end = now.restEnd {
                        TimelineView(.animation(minimumInterval: 1.0 / 15)) { ctx in
                            let left = max(0, end.timeIntervalSince(ctx.date))
                            ZStack {
                                Circle().stroke(Color.bPrimary.opacity(0.2), lineWidth: 3)
                                Circle().trim(from: 0, to: min(1, left / max(1, now.restTotal)))
                                    .stroke(Color.bPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                                Text("\(Int(left.rounded(.up)))").font(.geist(11, .semibold)).monospacedDigit().foregroundStyle(poster == nil ? Color.bPrimary : .white)
                            }
                            .padding(7)
                        }
                    } else if poster == nil {
                        Image(systemName: now.paused ? "pause.fill" : "figure.strengthtraining.traditional")
                            .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.bPrimary)
                            .symbolEffect(.pulse, isActive: !now.paused)
                    }
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(now.exercise).font(.geist(15, .semibold)).lineLimit(1).foregroundStyle(Color.bFg)
                        .contentTransition(.opacity)
                    Text([now.program, now.paused ? tl("Duraklatıldı") : now.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.bXs).lineLimit(1).foregroundStyle(Color.bMutedFg)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.bMutedFg)
                    .padding(.trailing, 6)
            }
            .padding(.leading, 8).padding(.trailing, 10).padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.bFg.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.16), radius: 14, y: 6)
        }
        .buttonStyle(.press)
        .accessibilityLabel("Antrenmana dön: \(now.exercise)")
        .animation(.snappy, value: now)
    }
}

/// Sekme içeriğinin güvenli alanını (sekme çubuğu dahil) bildirir
struct TabInsetReader: ViewModifier {
    @Binding var insets: EdgeInsets
    func body(content: Content) -> some View {
        content.onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { if $0 != insets { insets = $0 } }
    }
}


// MARK: - Açılış (SP-01)

/// iOS açılış ekranıyla birebir aynı karede başlar (marka zemini + dambıl), sonra logo hafifçe büyüyüp
/// ekran açılarak uygulamaya geçer. Toplam ~0,6 sn; "Hareketi azalt" açıksa yalnız yumuşak geçiş.
struct SplashOverlay: View {
    var done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoScale: CGFloat = 1
    @State private var opacity: Double = 1
    @State private var bgScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color("LaunchBackground").scaleEffect(bgScale)
            Image("LaunchLogo").scaleEffect(logoScale)
        }
        .ignoresSafeArea()
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.25)) { opacity = 0 }
                try? await Task.sleep(for: .milliseconds(260)); done(); return
            }
            try? await Task.sleep(for: .milliseconds(120))
            // Önce hafifçe toplanır, sonra büyüyerek ekranı açar
            withAnimation(.easeInOut(duration: 0.18)) { logoScale = 0.88 }
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeIn(duration: 0.32)) { logoScale = 9; bgScale = 1.08; opacity = 0 }
            try? await Task.sleep(for: .milliseconds(340))
            done()
        }
    }
}


/// Figma ekran görüntüleri (-shot): uzun modifier zincirini derleyici için böler
private struct RootShots: ViewModifier {
    /// Ortamdan okunmaz: RootView'da bu noktada AppState henüz ortama verilmemiş (açılışta çöküyordu)
    let app: AppState
    func body(content: Content) -> some View {
        content
            .shot("nut.add") { app.tab = .food; app.sheet = .addFood(date: DayKey.today, meal: nil) }
            .shot("nut.cheat") { app.tab = .food; app.sheet = .cheat(date: DayKey.today) }
            .shot("prof.measureQuick") { app.sheet = .measure(quick: true) }
    }
}
