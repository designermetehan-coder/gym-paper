import SwiftUI
import SwiftData
import GymPaperKit
import TipKit

/// Workout tab
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
    /// The program as it was when editing began; on "Done" it asks whether to apply to this day or future workouts
    @State private var editSnap: [Block]?
    @State private var askScope = false
    /// Direction of the day change: content slides that way
    @State private var dayDir: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.miniPlayerInset) private var miniInset

    var body: some View {
        let profile = profiles.first ?? Store.profile(ctx)
        let _ = (programs.count, days.count)   // redraw when it changes
        let date = Wk.weekDate(day, wk)
        let future = date > DayKey.today
        let prog = Wk.programFor(date, profile: profile, ctx: ctx)
        let empty = prog == nil ? Wk.assignedProgram(date, profile: profile, ctx: ctx) : nil
        let dayLog = days.day(date)
        let wp = prog.map { workoutProgress($0, day: dayLog) }
        let running = prog != nil && WkSessionClock.load(date) != nil && (dayLog?.workoutSeconds ?? 0) == 0
        // dictionaries from query results for the day strip (no per-day data query)
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
                    BRoundIcon(icon: "template", label: "Antrenmanlarım") { if app.workoutPath.last != .programs { app.workoutPath.append(.programs) } }
                    Menu {
                        Button("Geçen hafta") { wk = -1 }
                        Button("Bu hafta") { wk = 0; day = DayKey.weekday(DayKey.today) }
                        Button("Gelecek hafta") { wk = 1 }
                    } label: { Ti("calendar-week", size: 20).foregroundStyle(Color.bFg).frame(width: 44, height: 44).modifier(BGlassCircle()) }
                    .accessibilityLabel(tl("Hafta seç"))
                }
            }

            WkWeekCircles(value: Binding(get: { day }, set: { n in dayDir = n >= day ? 1 : -1; day = n }),
                          todayIndex: wk == 0 ? DayKey.weekday(DayKey.today) : -1,
                          status: { i in
                              let d = Wk.weekDate(i, wk)
                              guard let p = planFor(d) else { return .rest }
                              return workoutProgress(p, day: dayMap[d]).complete ? .done : .todo
                          })
                .environment(\.wkWeekOffset, wk)

            // Day title: date eyebrow + program name; swap and edit act on this day only
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayEyebrow(date)).font(.bSm).foregroundStyle(Color.bMutedFg)
                    Text(prog.map { $0.name.isEmpty ? tl("Antrenman") : $0.name } ?? tl("Dinlenme günü"))
                        .font(.bDisplay(26, relativeTo: .title)).tracking(-0.4).foregroundStyle(Color.bFg).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                if !edit, prog != nil, date >= DayKey.today {
                    BRoundIcon(icon: "switch-horizontal", label: "Bu güne farklı antrenman") { route = .pickProgram(date: date, load: false, repeats: false) }
                    if let p = prog {
                        // shared programs ask for the scope (this day / future workouts) on Done
                        BRoundIcon(icon: "pencil", label: "Düzenle") { editSnap = p.blocks; withAnimation { edit = true } }
                    }
                }
            }
            .id("head-" + date).transition(dayMove)

            if let prog, let wp, !edit, wp.total > 0 {
                let vol = workoutVolume(prog, day: dayLog)
                let mins = Int(CalorieEngine.estimatedMinutes(sets: prog.blocks.restProfile).rounded())
                HStack(spacing: 10) {
                    statTile("Set", wp.done > 0 ? "\(wp.done)/\(wp.total)" : "\(wp.total)", nil)
                    Button { volInfo = true } label: {
                        statTile("Hacim", vol.planned > 0 ? fmt0(vol.done > 0 ? vol.done : vol.planned) : "–", vol.planned > 0 ? "kg" : nil)
                    }
                    .buttonStyle(.press)
                    .popover(isPresented: $volInfo) {
                        Text("Hacim, her setin kilosu ile tekrar sayısının çarpılıp toplanmasıyla bulunur. Örneğin 60 kg × 8 tekrar = 480 kg. Bu sayı arttıkça daha çok iş yapmışsın demektir.")
                            .font(.bSm).foregroundStyle(Color.bFg).padding(16).frame(width: 280)
                            .fixedSize(horizontal: false, vertical: true)
                            .presentationCompactAdaptation(.popover)
                    }
                    statTile("Süre", dayLog.map { $0.workoutSeconds > 0 ? "\($0.workoutSeconds / 60)" : "~\(mins)" } ?? "~\(mins)", "dk")
                }
                .id("stats-" + date).transition(dayMove)
                if future { Text("Bu gün henüz gelmedi; planı görebilirsin.").font(.bXs).foregroundStyle(Color.bMutedFg).frame(maxWidth: .infinity) }
                if wp.complete && !running {
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
                }
            }

            if prog == nil, !programs.contains(where: { !$0.archived }) {
                // no program at all: same empty state as Today
                BEmpty(symbol: "dumbbell", title: "Henüz programın yok",
                       text: "Hazır bir programla başla ya da kendininkini kur; günlerini haftalık plana yerleştiririz.",
                       action: "Program seç") { if app.workoutPath.last != .programs { app.workoutPath.append(.programs) } }
            } else if prog == nil {
                WkEmpty(icon: "calendar-week", title: "Dinlenme günü",
                        text: date < DayKey.today ? "Bu gün antrenman yoktu." : "Eklediğin antrenman yalnız bu güne özel olur; haftalık planın Profil › Antrenmanlarım'da.") {
                    if date >= DayKey.today {
                        Button {
                            // if there's an empty this-day-only program it's added to that; the shared plan program is untouched
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


            // muscle map: how much each area works per the plan; suggestion for a missing area
            if let prog, let wp, wp.total > 0 {
                WkWeekMuscleSection(prog: prog, date: date, profile: profile, logs: days, canSuggest: date >= DayKey.today && !wp.complete) { muscle in
                    if !prog.archived && !edit { editSnap = prog.blocks; withAnimation { edit = true } }
                    route = .exPicker(pid: prog.pid, bid: nil, newFor: nil, group: muscle)
                }
                    .id("muscle-" + date).transition(dayMove)
            }
        }
        // Start sits above the tab bar, outside the scroll (Figma "Workout · Week")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // not on future days: the note says the day hasn't come; a faded button over the list looked broken
            if let prog, let wp, !edit, !future, wp.total > 0, !(wp.complete && !running) {
                HStack(spacing: 8) {
                    Button { haptic(); app.openSession(.init(pid: prog.pid, date: date)) } label: {
                        let open = app.session?.pid == prog.pid && app.session?.date == date
                        HStack(spacing: 8) {
                            Text(open ? "Antrenmana dön" : (running || wp.done > 0 ? "Devam et" : "Antrenmanı başlat"))
                            Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.b(.primary, .large, full: true)).disabled(future)
                    .popoverTip(TipStartWorkout())
                    if !future {
                        Button {
                            haptic(.medium); app.endSessionIfOn(date); Wk.completeWorkout(ctx, date: date, prog: prog); app.toast("Antrenman tamamlandı")
                        } label: { Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)) }
                        .buttonStyle(BGlassIconStyle(size: 48))
                        .accessibilityLabel("Antrenmanı yaptım olarak işaretle")
                    }
                }
                // stays above the mini player when a workout is minimized
                .padding(.horizontal, 20).padding(.bottom, 8 + miniInset)
                .transition(.opacity)
            }
        }
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.3), value: edit)
        .onChange(of: prog?.pid) { _, v in if v == nil { edit = false } }
        .onChange(of: wk) { _, w in if w == 0 { day = DayKey.weekday(DayKey.today) } }
        // changing the day closes editing; asks for the scope if there are changes
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
        // Figma screenshots (-shot)
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
        // a tab left open across midnight moves to the new day
        .onChange(of: phase) { _, p in if p == .active { rollDay() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in rollDay() }
    }

    /// Remove the done mark; undo brings sets and duration back as they were
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

    /// The selected day slides in 16 pt from its direction and the old one fades; opacity only with Reduce Motion
    private var dayMove: AnyTransition {
        reduce ? .opacity : .asymmetric(insertion: .offset(x: 16 * dayDir).combined(with: .opacity), removal: .opacity.animation(.easeIn(duration: 0.12)))
    }

    /// "Done": close if nothing changed; ask for the scope if the program is used on other days
    private var weekEyebrow: String {
        let label = wk == 0 ? tl("Bu hafta") : wk == -1 ? tl("Geçen hafta") : wk == 1 ? tl("Gelecek hafta")
            : wk < 0 ? String(localized: "\(-wk) hafta önce") : String(localized: "\(wk) hafta sonra")
        return "\(label) · \(Wk.shortDate(Wk.weekDate(0, wk))) – \(Wk.shortDate(Wk.weekDate(6, wk)))"
    }
    private func dayEyebrow(_ d: String) -> String {
        "\(DayKey.dayLong[DayKey.weekday(d)]) · \(trShortDate(d))"
    }
    private func statTile(_ title: String, _ value: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tl(title)).font(.bXs).foregroundStyle(Color.bMutedFg)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.bNum(22, relativeTo: .title3)).foregroundStyle(Color.bFg)
                if let unit { Text(tl(unit)).font(.bXs).foregroundStyle(Color.bMutedFg) }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.bCard, in: RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

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

    /// Adds the suggested exercise; a shared program enters edit mode and "Done" asks for the scope
    private func finishEdit(_ prog: WorkoutProgram, date: String) {
        guard let snap = editSnap, snap != prog.blocks, !prog.archived, usedElsewhere(prog, besides: date) else {
            editSnap = nil; withAnimation { edit = false }; return
        }
        editPid = prog.pid; editDate = date
        askScope = true
    }
    @State private var editPid: String?
    @State private var editDate: String?
    /// Whether the program is used outside this day (weekly plan or other days)
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
        // move the new version to a this-day-only copy and restore the original program
        let copy = WorkoutProgram(pid: UUID().uuidString, name: prog.name, blocks: prog.blocks)
        copy.short = prog.short; copy.archived = true   // hidden from lists, bound to this day only
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

    /// Deletes every exercise in the program; undo restores the old blocks
    private func clearAll(_ prog: WorkoutProgram) {
        let old = prog.blocks
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation { Wk.editBlocks(ctx, prog) { $0.removeAll() } }
        app.toast("Tüm hareketler silindi", kind: .delete) {
            Wk.editBlocks(ctx, prog) { $0 = old }
        }
    }
}
