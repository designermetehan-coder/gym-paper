import SwiftUI
import SwiftData
import BalliKit
import TipKit

/// Antrenman sekmesi — PWA src/screens/Workout.jsx ile aynı
struct WorkoutView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var phase
    @State private var shownToday = DayKey.today
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \WorkoutProgram.createdAt) private var programs: [WorkoutProgram]
    @Query private var days: [DayLog]
    @State private var day = DayKey.weekday(DayKey.today)
    @State private var wk = 0
    @State private var edit = false
    @State private var askClear = false
    @State private var route: WkSheet?
    @State private var volInfo = false
    /// Düzenlemeye girerken programın hali; "Bitti"de yalnız bu gün mü, gelecek antrenmanlar mı sorulur
    @State private var editSnap: [Block]?
    @State private var askScope = false
    /// Gün değişiminin yönü: içerik o yöne kayar (MO-I3)
    @State private var dayDir: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let profile = profiles.first ?? Store.profile(ctx)
        let _ = (programs.count, days.count)   // değişince yeniden çiz
        let date = Wk.weekDate(day, wk)
        let future = date > DayKey.today
        let prog = Wk.programFor(date, profile: profile, ctx: ctx)
        let empty = prog == nil ? Wk.assignedProgram(date, profile: profile, ctx: ctx) : nil
        let dayLog = days.day(date)
        let wp = prog.map { workoutProgress($0, day: dayLog) }
        let running = prog != nil && WkSessionClock.load(date) != nil && (dayLog?.workoutSeconds ?? 0) == 0
        // Gün şeridi için sorgu sonuçlarından sözlükler (gün başına veri sorgusu yok — WK-07)
        let dayMap = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let progMap = Dictionary(programs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let planFor: (String) -> WorkoutProgram? = { d in
            guard let id = Wk.programIdFor(d, profile: profile, day: dayMap[d]), let p = progMap[id], !p.blocks.allExercises.isEmpty else { return nil }
            return p
        }

        BScreen {
            BHeader(title: "Antrenman") {
                if edit && prog != nil {
                    Button("Bitti") { finishEdit(prog!, date: date) }.buttonStyle(.b(.ghost)).fontWeight(.semibold)
                } else {
                    // Antrenman ekranı yalnız görüntüler; programlar ve haftalık plan Profil › Antrenmanlarım'dan düzenlenir (GP-11).
                    // Buradan yapılan her değişiklik yalnız bu güne uygulanır ve plandakini ezer.
                    if prog != nil && date >= DayKey.today { BRoundIcon(icon: "switch-horizontal", label: "Bu güne farklı antrenman") { route = .pickProgram(date: date, load: false, repeats: false) } }
                    // Geçmiş günler düzenlenmez: kayıtlı geçmiş değişmesin (PR-02); yalnız bu güne özel antrenman düzenlenir
                    if let p = prog, p.archived, date >= DayKey.today { BRoundIcon(icon: "pencil", label: "Düzenle") { editSnap = p.blocks; withAnimation { edit = true } } }
                }
            }

            VStack(spacing: 8) {
                WkWeekNav(wk: $wk) { wk = 0; day = DayKey.weekday(DayKey.today) }
                WkDayStrip(value: Binding(get: { day }, set: { n in dayDir = n >= day ? 1 : -1; day = n }), todayIndex: wk == 0 ? DayKey.weekday(DayKey.today) : -1,
                           label: { i in planFor(Wk.weekDate(i, wk)).map { $0.name.isEmpty ? "Antrenman" : $0.name } ?? "–" },   // P-03: programın kendi adı
                           status: { i in
                               let d = Wk.weekDate(i, wk)
                               guard let p = planFor(d) else { return .rest }
                               return workoutProgress(p, day: dayMap[d]).complete ? .done : .todo
                           }, legend: true)
            }

            if let prog, let wp, !edit, wp.total > 0 {
                VStack(spacing: 12) {
                    // Toplam set ve antrenman hacmi (2 Kas): başlamadıysa plan, başladıysa yapılan
                    let vol = workoutVolume(prog, day: dayLog)
                    HStack(spacing: 0) {
                        wkStat("Set", wp.done > 0 ? "\(wp.done)/\(wp.total)" : "\(wp.total)", sub: wp.done > 0 ? "tamamlanan" : "toplam")
                        Rectangle().fill(Color.bBorder).frame(width: 1, height: 36)
                        // Hacim: toplam kaldırılan ağırlık; dokununca nasıl hesaplandığı açıklanır (4 Kas)
                        Button { volInfo = true } label: {
                            wkStat("Hacim ⓘ", vol.planned > 0 ? String(localized: "\(fmt0(vol.done > 0 ? vol.done : vol.planned)) kg") : "–",
                                   sub: vol.planned == 0 ? "ağırlık yok" : vol.done > 0 ? "toplam kaldırılan ağırlık" : "plana göre toplam ağırlık")
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $volInfo) {
                            Text("Hacim, her setin kilosu ile tekrar sayısının çarpılıp toplanmasıyla bulunur. Örneğin 60 kg × 8 tekrar = 480 kg. Bu sayı arttıkça daha çok iş yapmışsın demektir.")
                                .font(.bSm).foregroundStyle(Color.bFg).padding(16).frame(width: 280)
                                .fixedSize(horizontal: false, vertical: true)
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                    .bCard(padding: 12)
                    if future { Text("Bu gün henüz gelmedi; planı görebilirsin.").font(.bXs).foregroundStyle(Color.bMutedFg).frame(maxWidth: .infinity) }
                    HStack(spacing: 8) {
                        if wp.complete && !running {
                            // İşareti kaldırma aynı alanda (P-08)
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.bSuccess)
                                Text("Antrenman tamamlandı").font(.geist(15, .semibold)).foregroundStyle(Color.bFg)
                                Spacer(minLength: 4)
                                if !future {
                                    Button { uncomplete(prog, date: date) } label: {
                                        Text("Geri al").font(.geist(14, .semibold)).foregroundStyle(Color.bFg)
                                            .padding(.horizontal, 14).frame(minHeight: 36)
                                            .background(Color.bFg.opacity(0.08), in: Capsule())
                                    }
                                    .buttonStyle(.press)
                                    .accessibilityLabel("Tamamlandı işaretini kaldır")
                                }
                            }
                            .padding(.leading, 18).padding(.trailing, 6)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color.bSuccess.opacity(0.12), in: Capsule())
                        } else {
                            Button { haptic(); app.openSession(.init(pid: prog.pid, date: date)) } label: {
                                // Açık seans varsa "Antrenmana dön" (P-06)
                                let open = app.session?.pid == prog.pid && app.session?.date == date
                                BLabel(open ? "Antrenmana dön" : (running || wp.done > 0 ? "Devam et" : "Başlat"), icon: "player-play-filled")
                            }
                            .buttonStyle(.b(.primary, .large, full: true)).disabled(future)
                            .popoverTip(TipStartWorkout())
                            if !future {
                                Button {
                                    haptic(.medium); app.endSessionIfOn(date); Wk.completeWorkout(ctx, date: date, prog: prog); app.toast("Antrenman tamamlandı")
                                } label: { BLabel("Tamamlandı", icon: "check") }
                                .buttonStyle(.b(.secondary, .large, full: true))
                                .accessibilityLabel("Antrenmanı yaptım olarak işaretle")
                            }
                        }
                    }
                }
                .id(date).transition(dayMove)
            }

            if prog == nil, !programs.contains(where: { !$0.archived }) {
                // Hiç program yok: Özet'teki boş durumla aynı (TE-12)
                BEmpty(symbol: "dumbbell", title: "Henüz programın yok",
                       text: "Hazır bir programla başla ya da kendininkini kur; günlerini haftalık plana yerleştiririz.",
                       action: "Program seç") { if app.workoutPath.last != .programs { app.workoutPath.append(.programs) } }
            } else if prog == nil {
                WkEmpty(icon: "calendar-week", title: "Dinlenme günü",
                        text: date < DayKey.today ? "Bu gün antrenman yoktu." : "Eklediğin antrenman yalnız bu güne özel olur; haftalık planın Profil › Antrenmanlarım'da.") {
                    if date >= DayKey.today {
                        Button {
                            // Yalnız bu güne özel boş program varsa ona eklenir; plandaki ortak programa dokunulmaz (GP-11)
                            route = .plan(date: date, pid: empty?.archived == true ? empty?.pid : nil)
                        } label: { BLabel("Antrenman ekle", icon: "plus") }   // GP-13
                        .buttonStyle(.b(.primary))
                    }
                }
            } else if let prog, let wp, wp.total == 0 && !edit {
                WkEmpty(icon: "plus", title: "Bu program boş", text: "Bu güne hareket ekleyebilirsin.") {
                    Button {
                        if prog.archived { edit = true; route = .exPicker(pid: prog.pid, bid: nil, newFor: nil) }
                        else { route = .plan(date: date, pid: nil) }
                    } label: { BLabel("Antrenman ekle", icon: "plus") }.buttonStyle(.b(.primary))
                }
            } else if let prog {
                WkBlockList(prog: prog, edit: edit, date: date, future: future, route: $route)
                    .id(date).transition(dayMove)
            }

            if let prog, edit {
                HStack(spacing: 8) {
                    Button { route = .exPicker(pid: prog.pid, bid: nil, newFor: nil) } label: { BLabel("Hareket", icon: "plus") }.buttonStyle(.b(.primary, full: true))
                    Button { route = .blockForm(pid: prog.pid, bid: nil) } label: { BLabel("Süperset", icon: "plus") }.buttonStyle(.b(.outline, full: true))
                }
            }
            if let prog, edit, !prog.blocks.isEmpty {
                Button("Tümünü sil") { askClear = true }
                    .buttonStyle(.b(.ghost, full: true)).bButtonFg(Color.bDestructive)
                    .confirmationDialog("Tüm hareketler silinsin mi?", isPresented: $askClear, titleVisibility: .visible) {
                        Button("Tümünü sil", role: .destructive) { clearAll(prog) }
                        Button("Vazgeç", role: .cancel) {}
                    } message: { Text("\(prog.name) programındaki bütün hareketler silinecek. Hemen ardından geri alabilirsin.") }
            }

        }
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.3), value: edit)
        .onChange(of: prog?.pid) { _, v in if v == nil { edit = false } }
        .onChange(of: wk) { _, w in if w == 0 { day = DayKey.weekday(DayKey.today) } }
        // Gün değişince düzenleme kapanır (PR-14); değişiklik varsa kapsam sorulur
        .onChange(of: date) { old, _ in
            if edit, let p = Wk.programFor(old, profile: profile, ctx: ctx) ?? Wk.assignedProgram(old, profile: profile, ctx: ctx) { finishEdit(p, date: old) }
        }
        .confirmationDialog("Değişiklikler nereye uygulansın?", isPresented: $askScope, titleVisibility: .visible) {
            Button("Yalnız bu antrenman") { applyScope(onlyThisDay: true, date: date) }
            Button("Bu ve gelecek antrenmanlar") { applyScope(onlyThisDay: false, date: date) }
            Button("Değişiklikleri geri al", role: .destructive) { revertEdit() }
        } message: { Text("Bu program başka günlerde de kullanılıyor.") }
        .wkSheets($route)
        .navigationDestination(for: WkRoute.self) { r in WkRouteDestination(route: r) }
        // Figma ekran görüntüleri (-shot)
        .shot("wk.plan") { route = .plan(date: DayKey.today) }
        .shot("wk.pick") { route = .pickProgram(date: DayKey.today, load: true, repeats: false) }
        .shot("wk.swap") { route = .pickProgram(date: DayKey.today, load: false, repeats: false) }
        .shot("wk.exercise") {
            if let p = programs.first(where: { $0.pid == "demo-upper" }), let e = p.blocks.allExercises.dropFirst().first { route = .exercise(pid: p.pid, eid: e.id, date: DayKey.today) }
        }
        .shot("wk.exForm") { route = .exForm(pid: "demo-upper", eid: nil, bid: nil, preset: nil) }
        .shot("wk.exPicker") { route = .exPicker(pid: "demo-upper", bid: nil, newFor: nil) }
        .shot("wk.blockForm") { route = .blockForm(pid: "demo-upper", bid: nil) }
        .shot("wk.edit") { if let p = programs.first(where: { $0.pid == "demo-upper" }) { editSnap = p.blocks; edit = true } }
        .shot("wk.programs") { app.workoutPath = [.programs] }
        .shot("wk.programEdit") { app.workoutPath = [.programs, .programEdit(pid: "demo-upper")] }
        // Gün dönümünde açık kalan sekme yeni güne geçsin (QA-04)
        .onChange(of: phase) { _, p in if p == .active { rollDay() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in rollDay() }
    }

    /// Tamamlandı işaretini kaldır; geri al ile setler ve süre olduğu gibi döner (QA-03, P-08)
    private func uncomplete(_ prog: WorkoutProgram, date: String) {
        haptic()
        app.endSessionIfOn(date)
        let L = Store.day(ctx, date)
        let old = (L?.workoutDone, L?.exDone, L?.sets, L?.workoutSeconds, L?.workoutKcal)
        Wk.uncompleteWorkout(ctx, date: date, prog: prog)
        app.toast("Tamamlandı işareti kaldırıldı", kind: .ok) {
            guard let L else { return }
            L.workoutDone = old.0 ?? false; L.exDone = old.1 ?? [:]; L.sets = old.2 ?? [:]
            L.workoutSeconds = old.3 ?? 0; L.workoutKcal = old.4 ?? 0
        }
    }

    private func rollDay() {
        let t = DayKey.today
        guard t != shownToday else { return }
        if wk == 0 && day == DayKey.weekday(shownToday) { day = DayKey.weekday(t) }
        shownToday = t
    }

    /// Seçilen gün yönünde 16 pt kayarak gelir, eskisi solar; Hareketi Azalt açıkken yalnız opaklık
    private var dayMove: AnyTransition {
        reduce ? .opacity : .asymmetric(insertion: .offset(x: 16 * dayDir).combined(with: .opacity), removal: .opacity.animation(.easeIn(duration: 0.12)))
    }

    /// "Bitti": değişiklik yoksa kapat; program başka günlerde de kullanılıyorsa kapsam sor
    private func wkStat(_ title: String, _ value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tl(title)).font(.bXs).foregroundStyle(Color.bMutedFg)
            Text(value).font(.bNum(20, relativeTo: .title3)).foregroundStyle(Color.bFg).lineLimit(1).minimumScaleFactor(0.6)
            Text(tl(sub)).font(.bXs).foregroundStyle(Color.bMutedFg).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    private func finishEdit(_ prog: WorkoutProgram, date: String) {
        guard let snap = editSnap, snap != prog.blocks, !prog.archived, usedElsewhere(prog, besides: date) else {
            editSnap = nil; withAnimation { edit = false }; return
        }
        editPid = prog.pid; editDate = date
        askScope = true
    }
    @State private var editPid: String?
    @State private var editDate: String?
    /// Program bu gün dışında da (haftalık planda ya da başka günlerde) kullanılıyor mu
    private func usedElsewhere(_ prog: WorkoutProgram, besides date: String) -> Bool {
        let profile = Store.profile(ctx)
        let inPlan = profile.schedule.contains { $0.days.values.contains { $0 == prog.pid } }
        let otherDays = Wk.allDays(ctx).contains { $0.date != date && $0.programIdRaw == prog.pid }
        return inPlan || otherDays
    }
    private func applyScope(onlyThisDay: Bool, date: String) {
        defer { editSnap = nil; editPid = nil; editDate = nil; withAnimation { edit = false } }
        guard onlyThisDay, let snap = editSnap, let pid = editPid, let d = editDate, let prog = Wk.program(pid, ctx) else {
            if !onlyThisDay { app.toast("Gelecek antrenmanlara uygulandı") }
            return
        }
        // Yeni hali yalnız bu güne özel bir kopyaya taşı, asıl programı eski haline döndür
        let copy = WorkoutProgram(pid: UUID().uuidString, name: prog.name, blocks: prog.blocks)
        copy.short = prog.short; copy.archived = true   // listelerde görünmez, yalnız bu güne bağlı
        ctx.insert(copy)
        prog.blocks = snap
        Store.day(ctx, d)?.programIdRaw = copy.pid
        Store.save(ctx)
        app.toast(String(localized: "Yalnız \(Wk.longDate(d)) için kaydedildi"))
    }
    private func revertEdit() {
        if let snap = editSnap, let pid = editPid, let prog = Wk.program(pid, ctx) { prog.blocks = snap }
        editSnap = nil; editPid = nil; editDate = nil
        withAnimation { edit = false }
    }

    /// Programdaki tüm hareketleri siler; geri al eski blokları döndürür
    private func clearAll(_ prog: WorkoutProgram) {
        let old = prog.blocks
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation { Wk.editBlocks(ctx, prog) { $0.removeAll() } }
        app.toast("Tüm hareketler silindi", kind: .delete) {
            Wk.editBlocks(ctx, prog) { $0 = old }
        }
    }
}
