import SwiftUI
import SwiftData
import Combine
import TipKit
import CoreData
import GymPaperKit

struct RootView: View {
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var phase
    @Environment(\.horizontalSizeClass) private var hsc
    /// Safe area of the tab content (tab bar included) and the root: places the mini player right above/beside
    /// the tab bar wherever it is (bottom, or side on iPhone Duo)
    @State private var tabInsets = EdgeInsets()
    @State private var rootInsets = EdgeInsets()
    @AppStorage("healthAsked") private var healthAsked = false
    /// First-run flow: once; never shown when data exists
    @AppStorage(Onboarding.key) private var onboarded = false
    enum OnbPhase { case checking, showing, done }
    @State private var onb: OnbPhase = UserDefaults.standard.bool(forKey: Onboarding.key) ? .done : .checking
    @State private var app = AppState()
    /// Continuation of the launch screen: the logo opens into the app with a short transition; off in screenshot mode
    @State private var lastDedupe = Date.distantPast
    @State private var splash = !ProcessInfo.processInfo.arguments.contains("-demo")
    /// Fonts scale at draw time; rebuild the tabs when the text size changes
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var playerNS
    private let restTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// Mini player bottom inset: the tab bar's height + 8 (old constants if it can't be measured)
    private var miniBottom: CGFloat {
        let bar = tabInsets.bottom - rootInsets.bottom
        if tabInsets.bottom > 0 { return bar > 20 ? bar + 8 : 12 }
        return hsc == .regular ? 16 : (iOS26 ? 74 : 58)
    }
    private var iOS26: Bool { if #available(iOS 26, *) { return true } else { return false } }

    /// Tab icon: outlined when not selected, filled when selected; bounces slightly on selection
    @ViewBuilder private func tabLabel(_ t: AppTab) -> some View {
        // fork.knife has no outline form: unselected Nutrition uses the Tabler outline fork and knife
        if t == .food && app.tab != t {
            Label(t.label, image: "ti-tools-kitchen-2")
        } else {
            Label(t.label, systemImage: t.symbol)
                .environment(\.symbolVariants, app.tab == t ? .fill : .none)
                .symbolEffect(.bounce.down, value: app.tab == t)
        }
    }

    /// Every app sheet except Profile, which opens full screen
    private var sheetBinding: Binding<AppSheet?> {
        Binding(get: { Self.isProfile(app.sheet) ? nil : app.sheet },
                set: { v in if v == nil && Self.isProfile(app.sheet) { return }; app.sheet = v })
    }
    private var profileBinding: Binding<Bool> {
        Binding(get: { Self.isProfile(app.sheet) }, set: { if !$0 { app.sheet = nil } })
    }
    private static func isProfile(_ s: AppSheet?) -> Bool {
        if case .profile? = s { return true }
        return false
    }

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .bottom) {
            // Native tab bar: Liquid Glass and the grow effect come from the system on iOS 26
            // no + tab: the workout card starts the workout and the nutrition card adds food
            TabView(selection: $app.tab) {
                Tab(value: AppTab.today) { NavigationStack { TodayView() }.tint(Color.bPrimary).modifier(TabInsetReader(insets: $tabInsets)) } label: { tabLabel(.today) }
                Tab(value: AppTab.workout) { NavigationStack(path: $app.workoutPath) { WorkoutView() }.tint(Color.bPrimary).modifier(TabInsetReader(insets: $tabInsets)) } label: { tabLabel(.workout) }
                Tab(value: AppTab.food) { NavigationStack { NutritionView() }.tint(Color.bPrimary).modifier(TabInsetReader(insets: $tabInsets)) } label: { tabLabel(.food) }
                if AppTab.socialEnabled {
                    Tab(value: AppTab.social) { NavigationStack { SocialView() }.tint(Color.bPrimary).modifier(TabInsetReader(insets: $tabInsets)) } label: { tabLabel(.social) }
                }
                Tab(value: AppTab.profile) { NavigationStack { ProgressScreen() }.tint(Color.bPrimary).modifier(TabInsetReader(insets: $tabInsets)) } label: { tabLabel(.profile) }
            }
            // selected tab: brand lime in dark mode, primary color in light mode; content keeps its own tint
            .tint(Color.bTab)
            .id(typeSize)
            // No sidebar: on Duo's inner and outer screens the tabs sit in the system control column (icons),
            // on iPhone in the bottom bar. .sidebarAdaptable opened a left sidebar on wide screens
            .tabViewStyle(.tabBarOnly)
            .environment(\.miniPlayerInset, app.session != nil && app.sessionMin ? 76 : 0)
            .sensoryFeedback(.selection, trigger: app.tab)
            // Player: opens full screen; swiping down or minimizing zooms back into the mini player (like Apple Music)
            .fullScreenCover(item: Binding(get: { app.sessionMin ? nil : app.session },
                                 set: { v in if v == nil, app.session != nil, !app.sessionMin { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { app.sessionMin = true } } })) { s in
                SessionView(pid: s.pid, date: s.date)
                    .environment(app).environment(health)
                    .interactiveDismissDisabled(app.rt.finished)   // the finish screen can't be minimized
                    .background(Color.bBg.ignoresSafeArea())
                    // Like Apple Music: grows from the mini player and shrinks into it, following the finger when dragged down
                    .navigationTransition(.zoom(sourceID: "player", in: playerNS))
            }
            // Mini player: always in place during a session (hidden while the player is open), so when the cover closes
            // the card zooms back into this bar like in Apple Music
            // No separate blur behind the mini player: the screen's bottom blur (BScreen) extends to cover it;
            // two stacked layers made a hard line at the player's edge
            if app.session != nil {
                MiniPlayer(now: app.sessionNow ?? .init(program: "", exercise: tl("Antrenman"), detail: ""), expand: { app.minimizeSession(false) })
                    .matchedTransitionSource(id: "player", in: playerNS) { src in
                        src.clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 20)
                    // stay clear of the tab bar when it's on the side (iPhone Duo)
                    .padding(.leading, max(0, tabInsets.leading - rootInsets.leading))
                    .padding(.trailing, max(0, tabInsets.trailing - rootInsets.trailing))
                    // right above the tab bar; at the bottom of the screen if the bar isn't at the bottom
                    .padding(.bottom, miniBottom)
                    // always ready under the full-screen player: the zoom lands exactly on this bar (no delayed fade)
                    .allowsHitTesting(app.sessionMin)
            }
            // First run: plain canvas while data is checked, then the flow (tabs load behind)
            if onb != .done {
                Group {
                    if onb == .showing { OnboardingView(onFinish: finishOnboarding).gymPaperTheme() }
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
        .sheet(item: sheetBinding) { s in
            Group {
                switch s {
                case .addFood(let d, let m): AddFoodSheet(date: d, meal: m)
                case .cheat(let d): CheatSheet(date: d)
                case .measure(let q): MeasureSheet(quick: q)
                case .importProgram(let p): WkImportSheet(payload: p)
                case .quickLog: QuickLogSheet()
                case .profile: EmptyView()
                }
            }
            .environment(app).environment(health)
        }
        // Profile opens full screen: the wash runs unbroken behind its header (a sheet's bar split it)
        .fullScreenCover(isPresented: profileBinding) {
            NavigationStack { ProfileView(asSheet: true) }.tint(Color.bPrimary)
                .environment(app).environment(health)
        }
        #if DEBUG
        .overlay { if DemoTour.active { TourTouchOverlay() } }   // touch ring for the cover video
        #endif
        .task {
            if let w = GymPaperApp.storageWarning { app.toast(w, kind: .error) }
            Store.dedupe(ctx)
            _ = Store.profile(ctx)
            if StartWorkoutRequest.take() { app.startTodayWorkout(ctx) }   // cold start from a Shortcut / Control Center
            UserMotion.shared.load(ctx)
            FoodImages.shared.load(ctx)
            #if DEBUG
            DemoData.seedIfRequested(ctx: ctx, app: app)
            if DemoTour.active { Task { await DemoTour.run(app: app, ctx: ctx) } }   // kapak videosu gezintisi
            if DemoData.active { onb = DemoData.onboarding ? .showing : .done; return }   // screenshot mode: don't ask for Health access
            #endif
            WidgetSync.applyPending(ctx: ctx)
            LiveSession.endOrphans()             // activity left from the previous run
            // with data on this device or in iCloud (update, new device), the first-run flow is skipped
            if !onboarded, Onboarding.hasData(ctx) { onboarded = true; onb = .done }
            if onboarded { await afterOnboarding() } else { onb = .showing }
        }
        .onChange(of: onb, initial: true) { _, v in TipGate.appReady = (v == .done) }   // no tips during the first-run flow
        .onChange(of: phase) { _, p in
            switch p {
            case .active:
                WidgetSync.applyPending(ctx: ctx)
                Task { await health.refresh(); WidgetSync.update(ctx: ctx, health: health); WatchSync.shared.push(); if AppTab.socialEnabled { SocialService.shared.loadWorkouts(Wk.allDays(ctx)); await SocialService.shared.push(health.weekSteps) } }
                Notifier.openSession(nil)
                Notifier.invalidate()   // permission may have changed in Settings
                Notifier.reschedule(ctx)
                LiveFast.sync(Store.profile(ctx))
            case .background:
                WidgetSync.update(ctx: ctx, health: health)
                Store.save(ctx); WatchSync.shared.push()   // plan changes must reach the watch
                LiveFast.sync(Store.profile(ctx))
                Notifier.reschedule(ctx)
                Notifier.openSession(app.session != nil && !app.rt.finished ? (app.sessionNow?.program ?? tl("Antrenman")) : nil)
            default: break
            }
        }
        // Shared workout: gympaper://p?d=… or https://gympaper.vercel.app/p#…
        .onOpenURL { url in
            // gympaper://start → today's workout
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
            // close an open player or sheet first, then open the import
            let busy = app.sheet != nil || (app.session != nil && !app.sessionMin)
            if app.session != nil { app.sessionMin = true }
            app.sheet = nil
            Task { try? await Task.sleep(for: .milliseconds(busy ? 650 : 50)); app.open(.importProgram(payload: p)) }
        }
        // save errors aren't silent; repeated ones show a single warning
        .onReceive(NotificationCenter.default.publisher(for: .gymPaperSaveFailed).throttle(for: .seconds(10), scheduler: RunLoop.main, latest: false)) { _ in
            app.toast("Değişiklik kaydedilemedi. Tekrar dene; sürerse uygulamayı yeniden başlat.", kind: .error)
        }
        .onReceive(NotificationCenter.default.publisher(for: .gymPaperStartWorkout).receive(on: RunLoop.main)) { _ in
            if StartWorkoutRequest.take() { app.startTodayWorkout(ctx) }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { a in
            if let url = a.webpageURL, let p = WkShare.payload(from: url) { app.open(.importProgram(payload: p)) }
        }
        // passing midnight with the app open must not keep yesterday's steps/active calories
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            Task { await health.refresh(); WidgetSync.update(ctx: ctx, health: health); WatchSync.shared.push() }
            Notifier.reschedule(ctx)
        }
        .onChange(of: app.sessionNow) { _, n in LiveSession.sync(n, active: app.session != nil) }
        // rest end: notification in the background; ends here while minimized
        .onChange(of: app.rt.rest) { _, r in
            if let r, r.left == nil, app.session != nil { RestAlarm.schedule(at: r.end, next: app.rt.restNext ?? app.sessionNow.map { "\($0.exercise) · \($0.setText)" }) }
            else { RestAlarm.cancel() }
        }
        .onReceive(restTick) { t in
            guard app.session != nil, app.sessionMin else { return }
            if let r = app.rt.rest, r.left == nil { RestAlarm.countdown(end: r.end, now: t) }
            if let x = app.rt.timer, x.left == nil { RestAlarm.countdown(end: x.end, now: t) }
            if let r = app.rt.rest, r.left == nil, r.end <= t {
                RestAlarm.beep(); app.rt.rest = nil
                if var n = app.sessionNow { n.restEnd = nil; n.detail = n.setText; app.sessionNow = n }
            }
            if let x = app.rt.timer, x.left == nil, x.end <= t { RestAlarm.beep(); app.rt.timer = nil }
        }
        .onChange(of: app.session, initial: true) { _, s in
            if s == nil { LiveSession.end() }
            // tell the watch: a workout started on the phone shows as a notice on the watch
            WatchSync.shared.setLive(s.flatMap { $0.date == DayKey.today ? "\($0.date)|\($0.pid)" : nil })
        }
        // iCloud changes from other devices: merge duplicates, refresh widgets
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).debounce(for: .seconds(2), scheduler: RunLoop.main)) { _ in
            // with bursts of iCloud changes, all tables are scanned at most every 20 s
            if Date.now.timeIntervalSince(lastDedupe) > 20 { Store.dedupe(ctx); lastDedupe = .now }
            else {
                // also merge the last skipped change
                Task { try? await Task.sleep(for: .seconds(21)); if Date.now.timeIntervalSince(lastDedupe) > 20 { Store.dedupe(ctx); lastDedupe = .now } }
            }
            // if iCloud data arrives during the first-run flow, the flow is unnecessary: close it (nothing local is written until it ends)
            if onb == .showing, !ProcessInfo.processInfo.arguments.contains("-demo"), Onboarding.hasData(ctx) {
                finishOnboarding()
                app.toast("iCloud'daki verilerin yüklendi")
            }
            FoodImages.shared.load(ctx); UserMotion.shared.load(ctx)
            WidgetSync.update(ctx: ctx, health: health)
            WatchSync.shared.push()
        }
        // update widgets on every save (no write when unchanged)
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in
            WidgetSync.update(ctx: ctx, health: health)
            Notifier.reschedule(ctx)
            WatchSync.shared.push()
        }
    }
}

extension RootView {
    /// Health access, step observing, widget and notification permission: after the first-run flow (or on every launch)
    private func afterOnboarding() async {
        // asked on every launch: iOS shows nothing for types already answered, only newly added ones
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

/// Mini player: program, exercise, rest countdown and progress; tap to expand
struct MiniPlayer: View {
    let now: AppState.SessionNow
    var expand: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // fetch the poster once, not on every frame of the 15 fps countdown
        let poster = Motion.poster(now.exercise)
        Button(action: expand) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: BRadius.small, style: .continuous).fill(Color.bPrimary.opacity(0.14))
                    if let img = poster {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
                            .overlay { if now.restEnd != nil { RoundedRectangle(cornerRadius: BRadius.small, style: .continuous).fill(.black.opacity(0.45)) } }
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous).stroke(Color.bFg.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.16), radius: 14, y: 6)
        }
        .buttonStyle(.press)
        .accessibilityLabel("Antrenmana dön: \(now.exercise)")
        .animation(.snappy, value: now)
    }
}

/// Reports the safe area of the tab content (tab bar included)
struct TabInsetReader: ViewModifier {
    @Binding var insets: EdgeInsets
    func body(content: Content) -> some View {
        content.onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { if $0 != insets { insets = $0 } }
    }
}


// MARK: - Launch

/// Starts on the exact frame of the iOS launch screen (lime canvas + dumbbell), holds while the app does its first
/// heavy work, then plays one keyframe animation (render-server driven, no step-by-step sleeps): the logo dips,
/// pops, then grows while the splash fades.
struct SplashOverlay: View {
    var done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var go = 0

    private struct Frame { var scale: CGFloat = 1; var opacity: Double = 1 }

    var body: some View {
        KeyframeAnimator(initialValue: Frame(), trigger: go) { f in
            ZStack {
                Color("LaunchBackground")
                Image("LaunchLogo").scaleEffect(f.scale)
            }
            .compositingGroup()
            .opacity(f.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.86, duration: 0.16)
                SpringKeyframe(1.12, duration: 0.3, spring: .init(response: 0.3, dampingRatio: 0.55))
                CubicKeyframe(2.6, duration: 0.32)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: 0.46)
                CubicKeyframe(0, duration: 0.32)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            // let the first frames of the app settle behind the splash
            try? await Task.sleep(for: .milliseconds(300))
            if reduceMotion { done(); return }
            go += 1
            try? await Task.sleep(for: .milliseconds(800))
            done()
        }
    }
}


/// Figma screenshots (-shot): splits the long modifier chain for the compiler
private struct RootShots: ViewModifier {
    /// Not read from the environment: AppState isn't in the environment yet at this point in RootView
    let app: AppState
    func body(content: Content) -> some View {
        content
            .shot("nut.add") { app.tab = .food; app.sheet = .addFood(date: DayKey.today, meal: nil) }
            .shot("nut.cheat") { app.tab = .food; app.sheet = .cheat(date: DayKey.today) }
            .shot("prof.measureQuick") { app.sheet = .measure(quick: true) }
    }
}
