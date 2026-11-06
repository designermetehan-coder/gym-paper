import SwiftUI
import SwiftData
import BalliKit

/// Saat yalnız antrenman takibi yapar: bugünün antrenmanı ve bu haftanın günleri
struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(WatchWorkout.self) private var wk
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \WorkoutProgram.createdAt) private var allPrograms: [WorkoutProgram]
    @Query private var days: [DayLog]
    /// Uygulama açıkken gece yarısı geçince yeni güne geçsin (WQ-15)
    private var today: String { DayKey.today }
    /// Açık antrenmanı kapatmadan önce onay (TE-11)
    @State private var confirmDiscard = false

    private var programs: [WorkoutProgram] { allPrograms.filter { !$0.archived } }

    var body: some View {
        let p = profiles.first
        let day = days.day(today)
        let prog = p.flatMap { Store.program(for: today, profile: $0, ctx: ctx) }
        List {
            // iPhone'da başlayan antrenman: saatte devam et (4 Kas)
            if let l = PhoneSync.shared.liveToday, !(days.day(l.date)?.workoutDone ?? false),
               let lp = allPrograms.first(where: { $0.pid == l.pid }) {
                Section {
                    NavigationLink(value: WRoute.player(pid: lp.pid, date: l.date)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("iPhone'da başladı", systemImage: "iphone").font(.footnote.weight(.semibold)).foregroundStyle(Color.wOnAction)
                            Text(lp.name).font(.headline.weight(.bold).italic()).foregroundStyle(Color.wOnAction).lineLimit(2)
                            Text("Saatte devam et").font(.caption2).foregroundStyle(Color.wOnAction.opacity(0.8))
                        }
                    }
                    .listItemTint(Color.wAction)
                }
            }
            Section {
                if allPrograms.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iPhone bekleniyor").font(.headline.weight(.bold).italic())
                        Text("iPhone'da GYM Paper'ı aç; programların saate gelir.").font(.footnote).foregroundStyle(.secondary)
                    }
                    #if targetEnvironment(simulator)
                    Button("Örnek programla dene") { WLogic.seedSample(ctx) }
                    #endif
                } else if let prog {
                    workoutCard(prog, date: today, day: day, startable: true)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bugün dinlenme günü").font(.headline.weight(.bold).italic())
                        Text("İstersen bir program seçip başlayabilirsin.").font(.footnote).foregroundStyle(.secondary)
                    }
                    #if targetEnvironment(simulator)
                    Button("Bugüne örnek program koy") { WLogic.seedSample(ctx) }
                    #endif
                }
                if !programs.isEmpty {
                    NavigationLink(value: WRoute.picker(date: today)) {
                        Label(prog == nil ? "Program seç" : "Başka program", systemImage: "list.bullet")
                    }
                }
                if wk.running {
                    Button("Açık antrenmanı kapat", role: .destructive) { confirmDiscard = true }
                        .confirmationDialog("Açık antrenman kaydedilmeden kapansın mı?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                            Button("Kapat", role: .destructive) { wk.discard() }
                            Button("Vazgeç", role: .cancel) {}
                        }
                }
            } header: {
                Text(Self.title(today))
            }

            // Aralıklı oruç (iPhone'da açıksa)
            if let f = PhoneSync.shared.fast {
                Section("Aralıklı oruç") {
                    WatchFastRow(plan: f)
                }
            }

            // Bu hafta: antrenman olan günler
            if let p {
                let week = weekDays(p)
                if !week.isEmpty {
                    Section("Bu hafta") {
                        ForEach(week, id: \.date) { w in
                            NavigationLink(value: WRoute.day(pid: w.pid, date: w.date, startable: w.date == today)) {
                                HStack(spacing: 8) {
                                    Text(Self.dow(w.date)).font(.footnote.weight(.semibold)).frame(width: 30, alignment: .leading)
                                        .foregroundStyle(w.date == today  ? Color.wInk : .secondary)
                                    Text(w.name).font(.footnote).lineLimit(2)
                                    Spacer(minLength: 0)
                                    if w.done { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.wDone).accessibilityLabel("Tamamlandı") }
                                }
                            }
                        }
                    }
                }
            }

            if let at = PhoneSync.shared.syncedAt {
                Text("iPhone ile eşitlendi · \(at.formatted(.relative(presentation: .named).locale(.current)))")
                    .font(.caption2).foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
        }
        #if targetEnvironment(simulator)
        // Ekran görüntüsü: `-demo` ile örnek program (iPhone'daki -demo gibi)
        .onAppear { if allPrograms.isEmpty, ProcessInfo.processInfo.arguments.contains("-demo") { WLogic.seedSample(ctx) } }
        #endif
        .navigationTitle("Bugün")   // tek kelime başlık; tarih bölüm başlığında (TE-11)
        .onAppear { PhoneSync.shared.requestSync() }
    }

    /// Model yerine değer tutulur: eşitleme programı silerse silinmiş kayda erişilmesin (WQ-05)
    private struct WeekDay { var date: String; var pid: String; var name: String; var done: Bool }
    private func weekDays(_ p: UserProfile) -> [WeekDay] {
        let monday = DayKey.shift(today, days: -DayKey.weekday(today))
        return (0..<7).compactMap { i in
            let k = DayKey.shift(monday, days: i)
            guard let pr = Store.program(for: k, profile: p, ctx: ctx) else { return nil }
            return WeekDay(date: k, pid: pr.pid, name: pr.name, done: days.day(k)?.workoutDone ?? false)
        }
    }

    @ViewBuilder private func workoutCard(_ prog: WorkoutProgram, date: String, day: DayLog?, startable: Bool) -> some View {
        let steps = WLogic.steps(prog)
        let done = steps.filter { WLogic.isDone($0, day) }.count
        NavigationLink(value: WRoute.day(pid: prog.pid, date: date, startable: startable)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(prog.name).font(.headline.weight(.bold).italic()).lineLimit(2)
                Text("\(prog.blocks.allExercises.count) hareket · \(steps.count) set").font(.footnote).foregroundStyle(.secondary)
                if done > 0 && !(day?.workoutDone ?? false) {
                    ProgressView(value: Double(done), total: Double(max(1, steps.count))).tint(Color.wInk)
                }
            }
        }
        if day?.workoutDone ?? false {
            Label("Tamamlandı", systemImage: "checkmark.circle.fill").foregroundStyle(Color.wDone)
        } else if startable {
            NavigationLink(value: WRoute.player(pid: prog.pid, date: date)) {
                Label(done > 0 || wk.running ? "Devam et" : "Başlat", systemImage: "play.fill").font(.headline.weight(.bold).italic())
                    .foregroundStyle(Color.wOnAction)   // açık zeminde beyaz yazı okunmuyordu (QA-05)
            }
            .listItemTint(Color.wAction)
        }
    }

    /// Her çizimde yeni DateFormatter oluşturulmasın
    private static let titleFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("dMMMMEEEE")
        return f
    }()
    static func title(_ k: String) -> String {
        guard let d = DayKey.date(k) else { return k }
        return titleFmt.string(from: d)
    }
    static func dow(_ k: String) -> String { DayKey.dayShort[DayKey.weekday(k)] }
}

/// Günün antrenmanı: hareketler, set × tekrar ve kilo; bugünse Başlat
struct DayDetail: View {
    let pid: String
    let date: String
    let startable: Bool
    @Query private var programs: [WorkoutProgram]
    @Query private var days: [DayLog]

    init(pid: String, date: String, startable: Bool) {
        self.pid = pid; self.date = date; self.startable = startable
        _programs = Query(filter: #Predicate<WorkoutProgram> { $0.pid == pid })
        _days = Query(filter: #Predicate<DayLog> { $0.date == date })
    }

    var body: some View {
        let day = days.day(date)
        List {
            if let prog = programs.first {
                Section {
                    if startable && !(day?.workoutDone ?? false) {
                        // İç içe gezinmede zoom geçişi saati donduruyordu; düz itme (4 Kas)
                        NavigationLink(value: WRoute.player(pid: pid, date: date)) {
                            Label("Başlat", systemImage: "play.fill").font(.headline.weight(.bold).italic())
                                .foregroundStyle(Color.wOnAction)
                        }
                        .listItemTint(Color.wAction)
                    } else if day?.workoutDone ?? false {
                        Label("Tamamlandı", systemImage: "checkmark.circle.fill").foregroundStyle(Color.wDone)
                    }
                } header: {
                    Text(HomeView.title(date))
                }
                ForEach(Array(prog.blocks.enumerated()), id: \.element.id) { i, b in
                    Section(b.kind == .superset ? "Süperset · \(b.rounds) tur" : "#\(i + 1)") {
                        ForEach(b.exercises, id: \.id) { e in
                            exRow(e, rounds: b.kind == .superset ? b.rounds : nil, day: day)
                        }
                    }
                }
            }
        }
        .navigationTitle(programs.first?.name ?? "")
    }

    private func exRow(_ e: Exercise, rounds: Int?, day: DayLog?) -> some View {
        let sets = rounds ?? e.sets
        let doneN = (day?.sets[e.id] ?? []).filter(\.done).count
        let all = day?.exDone[e.id] == true || doneN >= sets
        let kg = PhoneSync.shared.lastKg[e.id] ?? e.kg
        let f = WMotion.thumb(e.name).map { [$0] } ?? []
        return HStack(spacing: 8) {
            Group {
                if let i = f.first { Image(uiImage: i).resizable().scaledToFill() }
                else { Image(systemName: "dumbbell.fill").foregroundStyle(.secondary) }
            }
            .frame(width: 34, height: 34).background(.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(e.name).font(.footnote.weight(.medium)).lineLimit(2)
                Text("\(sets) × \(e.reps)\(e.unit == "tekrar" ? "" : " " + e.unit)\(kg.map { $0 > 0 ? " · \($0.kgText) kg" : "" } ?? "")")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            if all { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.wDone).accessibilityLabel("Tamamlandı") }
            else if doneN > 0 { Text("\(doneN)/\(sets)").font(.caption2).foregroundStyle(Color.wInk) }
        }
    }
}

/// Bugün için başka bir program seç
struct ProgramPicker: View {
    let date: String
    /// Kendi sorgusu: ana ekran yeniden çizilince liste ve gezinme sıfırlanmasın (4 Kas)
    @Query(filter: #Predicate<WorkoutProgram> { !$0.archived }, sort: \WorkoutProgram.createdAt) private var programs: [WorkoutProgram]
    var body: some View {
        List(programs, id: \.pid) { p in
            NavigationLink(value: WRoute.day(pid: p.pid, date: date, startable: true)) {
                VStack(alignment: .leading) {
                    Text(p.name).font(.headline.weight(.bold).italic())
                    Text("\(p.blocks.allExercises.count) hareket").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Programlar")
    }
}


/// Saatte oruç durumu: halka + kalan süre; şimdi bitir / sıradaki orucu atla
struct WatchFastRow: View {
    /// Oruç rengi: marka rengi lime; yeme aralığı da aynı, ayrımı ikon yapar (2 Kas)
    static let fastTint = Color.wAction
    let plan: FastPlan
    /// Orucu bitirmeden önce onay (TE-11)
    @State private var confirmEnd = false
    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 30)) { t in
            let ph = plan.phase(at: t.date)
            let (from, to, fasting, key): (Date, Date, Bool, String) = {
                switch ph {
                case let .fasting(s, e, k): return (s, e, true, k)
                case let .eating(s, n, _):
                    // atlanmış günler phase'te geçildiği için anahtar, atlansa da sıradaki orucun günü olmalı (CR-32)
                    let d = DayKey.of(t.date)
                    let k = (plan.start(of: d) ?? t.date) > t.date ? d : DayKey.shift(d, days: 1)
                    return (s, n, false, k)
                }
            }()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ProgressView(timerInterval: from...max(to, from.addingTimeInterval(1)), countsDown: false) { EmptyView() } currentValueLabel: {
                        Image(systemName: fasting ? "moon.stars.fill" : "fork.knife").font(.system(size: 12))
                    }
                    .progressViewStyle(.circular).tint(Self.fastTint).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(fasting ? "Oruç \(plan.label)" : "Yeme aralığı").font(.footnote.weight(.semibold))
                        Text(timerInterval: Date.now...max(to, .now), countsDown: true).font(.system(size: 20, weight: .heavy).italic().monospacedDigit())   // SF Pro, eşit genişlikli rakam (TE-03)
                            .foregroundStyle(Self.fastTint)
                    }
                }
                if fasting {
                    Button("Orucu şimdi bitir") { confirmEnd = true }.font(.footnote)
                        .confirmationDialog("Oruç şimdi bitsin mi?", isPresented: $confirmEnd, titleVisibility: .visible) {
                            Button("Orucu bitir", role: .destructive) { PhoneSync.shared.fastEnd(key) }
                            Button("Vazgeç", role: .cancel) {}
                        }
                } else {
                    Button(plan.skipped.contains(key) ? "Orucu geri al" : "Sıradaki orucu atla") { PhoneSync.shared.fastSkip(key) }.font(.footnote)
                }
            }
        }
    }
}

/// Saat renk belirteçleri: saat hep koyu; saf beyaz yerine kırık beyaz, turuncu yok (TE-11)
extension Color {
    static func wHex(_ h: UInt32) -> Color {
        Color(red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255)
    }
    /// Vurgu: kırık beyaz
    static let wInk = wHex(0xE5E5E7)
    /// Kırık beyaz zemin üstündeki yazı (siyaha yakın)
    static let wOnInk = wHex(0x1C1C1E)
    /// Birincil eylem ve metin butonları: neon lime (iPhone ile aynı), üstünde koyu lacivert yazı
    static let wAction = wHex(0xC6FF3D)
    static let wOnAction = wHex(0x121826)
    /// Tamamlandı / yeme aralığı yeşili (uygulamadaki koyu fitGreen)
    static let wDone = wHex(0x5FE07A)
    /// Nabız kırmızısı
    static let wHeart = wHex(0xFF453A)
    /// Oruç moru (koyu tema)
    static let wFast = wHex(0xA97CFF)
    /// İkincil kontroller
    static let wMuted = wHex(0x8E8E93)
}

#if DEBUG
/// App Store ekran görüntüleri: simülatörde `-shot home|day|player|rest|paused|summary` ile açılır,
/// iPhone'daki demo verisinin aynısını kurar (ios/watch-shots.command).
enum WShot {
    static var screen: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-shot"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    @MainActor static func seed(_ ctx: ModelContext, doneSets: Int) {
        if Store.programs(ctx).isEmpty {
            let p = Store.profile(ctx)
            func ex(_ n: String, _ s: Int, _ r: Int, _ kg: Double?, rest: Int = 90, unit: String = "tekrar") -> Exercise {
                Exercise(name: n, sets: s, reps: r, unit: unit, rest: rest, kg: kg)
            }
            let upper = WorkoutProgram(pid: "demo-upper", name: "Üst vücut", blocks: [
                Block(single: ex("Bench press", 4, 8, 60)),
                Block(single: ex("Barfiks", 4, 6, nil)),
                Block(single: ex("Dumbbell fly", 3, 12, 10, rest: 60)),
                Block(superset: [ex("Omuz press", 3, 10, 16), ex("Kablo row", 3, 12, 40)], rounds: 3, rest: 75),
                Block(single: ex("Plank", 3, 45, nil, rest: 45, unit: "sn")),
            ])
            let lower = WorkoutProgram(pid: "demo-lower", name: "Alt vücut", blocks: [
                Block(single: ex("Squat", 4, 6, 80, rest: 120)),
                Block(single: ex("Romanian deadlift", 3, 10, 60)),
            ])
            ctx.insert(upper); ctx.insert(lower)
            let monday = DayKey.shift(DayKey.today, days: -DayKey.weekday(DayKey.today))
            p.schedule = [ScheduleEntry(from: monday, days: ["0": "demo-upper", "1": "demo-lower", "3": "demo-upper", "4": "demo-lower"])]
            let today = DayKey.weekday(DayKey.today)
            let L = Store.day(ctx, DayKey.today)!
            L.programIdRaw = "demo-upper"
            // Geçmiş günler tamamlanmış görünsün
            for i in 0..<today { if let d = Store.day(ctx, DayKey.shift(monday, days: i)) { d.workoutDone = true } }
            try? ctx.save()
            let steps = WLogic.steps(upper)
            for s in steps.prefix(doneSets) {
                WLogic.mark(ctx, date: DayKey.today, pid: upper.pid, step: s, kg: s.ex.kg ?? 0, reps: s.ex.reps)
            }
        }
        PhoneSync.shared.fast = FastPlan(startMin: 20 * 60, hours: 16)
        PhoneSync.shared.syncedAt = Date().addingTimeInterval(-120)
    }
}

/// Kapak videosu: "seti tamamla" düğmesine dokunma halkası
struct WTourRing: View {
    @State private var on = false
    @State private var pressed = false
    var body: some View {
        GeometryReader { g in
            Circle().fill(Color.white.opacity(0.5))
                .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                .frame(width: 34, height: 34)
                .scaleEffect(pressed ? 0.8 : 1)
                .opacity(on ? 1 : 0)
                .position(x: g.size.width * 0.83, y: g.size.height * 0.857)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task {
            try? await Task.sleep(for: .seconds(1.9))
            withAnimation(.easeOut(duration: 0.18)) { on = true }
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.easeOut(duration: 0.12)) { pressed = true }
            try? await Task.sleep(for: .seconds(0.15))
            withAnimation(.easeOut(duration: 0.15)) { pressed = false }
            try? await Task.sleep(for: .seconds(0.15))
            withAnimation(.easeIn(duration: 0.25)) { on = false }
        }
    }
}

struct WShotRoot: View {
    let screen: String
    @Environment(\.modelContext) private var ctx
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                NavigationStack { content.wRoutes() }
                    .overlay { if screen == "tour" { WTourRing() } }
            } else {
                Color.black
            }
        }
        .task {
            let done = ["player": 4, "tour": 4, "rest": 5, "paused": 9, "summary": 14][screen] ?? 0
            WShot.seed(ctx, doneSets: done)
            ready = true
        }
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case "day": DayDetail(pid: "demo-upper", date: DayKey.today, startable: true)
        case "player", "rest", "paused", "summary", "tour": PlayerView(pid: "demo-upper", date: DayKey.today, shot: screen)
        default: HomeView()
        }
    }
}
#endif


/// Saatte gezinme değer tabanlı: ana ekran yeniden çizilince (antrenman başlayınca, iPhone'dan veri gelince)
/// iç içe "Başka program → Başlat" yığını bozulup saat donmasın (WT-15, 5 Kas)
enum WRoute: Hashable {
    case day(pid: String, date: String, startable: Bool)
    case player(pid: String, date: String)
    case picker(date: String)
}

extension View {
    func wRoutes() -> some View {
        navigationDestination(for: WRoute.self) { r in
            switch r {
            case let .day(pid, date, startable): DayDetail(pid: pid, date: date, startable: startable)
            case let .player(pid, date): PlayerView(pid: pid, date: date)
            case let .picker(date): ProgramPicker(date: date)
            }
        }
    }
}
