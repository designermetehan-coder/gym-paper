import SwiftUI
import PhotosUI
import SwiftData
import BalliKit

// Antrenman sheet'leri (PWA Workout.jsx: ExerciseSheet, ExForm, BlockForm, ExercisePicker, PickProgramSheet, DayPlanSheet, ProgressSheet, ProgramEditSheet)

struct WkNewFor: Hashable { var date: String; var repeats: Bool; var name: String = "" }

enum WkSheet: Identifiable, Hashable {
    case exercise(pid: String, eid: String, date: String)
    case exForm(pid: String, eid: String?, bid: String?, preset: String?)
    case exPicker(pid: String?, bid: String?, newFor: WkNewFor?)
    case blockForm(pid: String, bid: String?)
    case pickProgram(date: String, load: Bool, repeats: Bool?)
    case plan(date: String, pid: String? = nil)
    var id: String {
        switch self {
        case .exercise(let p, let e, let d): "ex-\(p)-\(e)-\(d)"
        case .exForm(let p, let e, let b, let s): "exf-\(p)-\(e ?? "")-\(b ?? "")-\(s ?? "")"
        case .exPicker(let p, let b, let n): "pick-\(p ?? "")-\(b ?? "")-\(n?.date ?? "")"
        case .blockForm(let p, let b): "bf-\(p)-\(b ?? "")"
        case .pickProgram(let d, let l, _): "pp-\(d)-\(l)"
        case .plan(let d, _): "plan-\(d)"
        }
    }
}

/// Sheet yönlendirici: bir sheet başka bir sheet'i açmak için `route`'u değiştirir
struct WkSheetHost: ViewModifier {
    @Binding var route: WkSheet?
    @Environment(AppState.self) private var app
    @Environment(HealthService.self) private var health
    func body(content: Content) -> some View {
        content.sheet(item: $route, onDismiss: {
            // Sıradaki sheet, önceki tamamen kapanınca açılır (sabit gecikme yerine — PR-09)
            if let n = WkPending.next { WkPending.next = nil; route = n }
        }) { s in
            WkSheetView(sheet: s, route: $route).environment(app).environment(health)
        }
    }
}
@MainActor enum WkPending { static var next: WkSheet? }
extension View { func wkSheets(_ route: Binding<WkSheet?>) -> some View { modifier(WkSheetHost(route: route)) } }

private struct WkSheetView: View {
    let sheet: WkSheet
    @Binding var route: WkSheet?
    var body: some View {
        switch sheet {
        case .exercise(let p, let e, let d): WkExerciseSheet(pid: p, eid: e, date: d)
        case .exForm(let p, let e, let b, let s): WkExForm(pid: p, eid: e, bid: b, preset: s)
        case .exPicker(let p, let b, let n): WkExercisePicker(pid: p, bid: b, newFor: n, route: $route)
        case .blockForm(let p, let b): WkBlockForm(pid: p, bid: b)
        case .pickProgram(let d, let l, let r): WkPickProgramSheet(date: d, load: l, repeat0: r, route: $route)
        case .plan(let d, let pid): WkDayPlanSheet(date: d, pid: pid, route: $route)
        }
    }
}

/// Sheet kapanıp yenisi açılsın diye kısa gecikmeli yönlendirme
@MainActor func wkGo(_ route: Binding<WkSheet?>, _ next: WkSheet) {
    WkPending.next = next
    route.wrappedValue = nil
}

// MARK: - Hareket (set kaydı + plan değerleri)

struct WkExerciseSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutProgram.createdAt) private var programs: [WorkoutProgram]
    @Query private var days: [DayLog]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    let pid: String, eid: String, date: String
    /// Yalnız bu program ve gün (PF-03)
    init(pid: String, eid: String, date: String) {
        self.pid = pid; self.eid = eid; self.date = date
        _programs = Query(filter: #Predicate<WorkoutProgram> { $0.pid == pid }, sort: \WorkoutProgram.createdAt)
        _days = Query(filter: #Predicate<DayLog> { $0.date == date })
    }
    @State private var tkg = ""
    @State private var loaded = false
    @AppStorage(WkFav.key) private var favRaw = ""
    /// Ağır hesaplar (geçmiş, öneri, rekor, seviye) gövdede değil, açılışta ve set değişince bir kez (WK-06)
    struct Info { var prev: Wk.Lifted?; var sug: WkProgress.Suggestion?; var hist: [WkSession] = []; var pr = false; var lvl: WkProgress.LevelRow? }
    @State private var info = Info()

    private var prog: WorkoutProgram? { programs.first { $0.pid == pid } }
    private var future: Bool { date > DayKey.today }

    var body: some View {
        if let prog, let e = Wk.findExercise(prog, eid) {
            content(prog, e)
        } else {
            Color.bBg.onAppear { dismiss() }
        }
    }

    @ViewBuilder private func content(_ prog: WorkoutProgram, _ e: Exercise) -> some View {
        let day = days.day(date)
        let S = day?.sets[eid] ?? []
        let done = day.map { exDoneCount(e, day: $0) >= e.sets } ?? false
        let ssB = Wk.supersetOf(prog, eid: eid)
        let prev = info.prev, sug = info.sug, hist = info.hist, pr = info.pr, lvl = info.lvl
        let restNow = ssB?.rest ?? e.rest
        BSheet(title: e.name) {
            MotionPlayer(name: e.name, height: 230, fill: true)
            // Bilgi çipleri: son set, öneri, form videosu
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let fav = WkFav.has(favRaw, e.name)
                    Button { haptic(); favRaw = WkFav.toggled(favRaw, e.name) } label: {
                        wkChip(fav ? "star.fill" : "star", fav ? "Favorilerde" : "Favorilere ekle", tint: fav ? .bPrimary : .bFg)
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel(fav ? "Favorilerden çıkar" : "Favorilere ekle")
                    if let prev { wkChip("clock.arrow.circlepath", String(localized: "Son: \(fmt1(prev.kg)) kg × \(prev.reps ?? e.reps)")) }
                    if let sug {
                        Button { fillSug(e, sug.kg) } label: { wkChip("sparkles", String(localized: "Öneri \(fmt1(sug.kg)) kg · Doldur"), tint: .bPrimary) }.buttonStyle(.press)
                    }
                    Link(destination: wkFormVideoURL(e.name)) {
                        wkChip("play.rectangle.fill", "Form videosu", tint: .bDestructive)
                    }
                }
            }
            .scrollClipDisabled()
            // Plan yalnız gösterilir (set ve tekrar program düzenlemeden değişir); burada yalnız kilo girilir
            HStack(spacing: 8) {
                planStat(ssB != nil ? "Tur" : "Set", "\(e.sets)")
                planStat(e.unit == "tekrar" ? "Tekrar" : e.unit == "sn" ? "Saniye" : "Dakika", "\(e.reps)")
                planStat("Dinlenme", String(localized: "\(restNow) sn"))
            }
            // Setler
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("Set").frame(width: 32, alignment: .leading)
                    Text("Kg").frame(maxWidth: .infinity)
                    Text(tl(e.unit).capitalized(with: .current)).frame(maxWidth: .infinity)
                    Color.clear.frame(width: 44, height: 1)
                }
                .font(.geist(12, .medium, relativeTo: .caption)).foregroundStyle(Color.bMutedFg)
                ForEach(0..<max(0, e.sets), id: \.self) { i in
                    WkSetRow(i: i, log: i < S.count ? S[i] : SetLog(), forceDone: done, future: future,
                             kgPlaceholder: (e.kg ?? 0) > 0 ? fmt1(e.kg!) : prev.map { fmt1($0.kg) } ?? "–", repsPlaceholder: "\(e.reps)", unit: e.unit,
                             onKg: { v in Wk.setLog(ctx, date: date, eid: eid, index: i) { $0.kg = v } },
                             onReps: { v in Wk.setLog(ctx, date: date, eid: eid, index: i) { $0.reps = v } },
                             onToggle: { toggle(e, i, S) })
                }
            }
            .bCard()
            if !hist.isEmpty { history(hist, pr: pr, lvl: lvl).bCard() }
            if !e.note.isEmpty { Text(e.note).font(.bSm).foregroundStyle(Color.bMutedFg) }
        } footer: {
            if future {
                Text("Bu gün henüz gelmedi; plan değerlerini şimdiden ayarlayabilirsin, set kaydı o gün açılır.").font(.bSm).foregroundStyle(Color.bMutedFg)
                    .multilineTextAlignment(.center).padding(.vertical, 8)
            } else {
                Button { markAll() } label: { if done { Text("İşareti kaldır") } else { BLabel("Hareketi yaptım", icon: "check") } }
                    .buttonStyle(.b(done ? .outline : .primary, .large, full: true))
            }
        }
        .onAppear { if !loaded { loaded = true; tkg = (e.kg ?? 0) > 0 ? fmt1(e.kg!) : "" } }
        // set kayıtları değişince kısa gecikmeyle yeniden hesapla (yazarken takılmasın)
        .task(id: S.map { "\($0.kg ?? 0)|\($0.reps ?? 0)|\($0.done)" }.joined(separator: ",") + "\(e.name)") {
            if loaded { try? await Task.sleep(for: .milliseconds(400)) }
            guard !Task.isCancelled else { return }
            info = computeInfo(e)
        }
    }

    private func planStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(tl(label)).font(.geist(12, .medium, relativeTo: .caption)).foregroundStyle(Color.bMutedFg)
            Text(value).font(.bNum(17, relativeTo: .body)).lineLimit(1).foregroundStyle(Color.bFg)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Color.bFg.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func computeInfo(_ e: Exercise) -> Info {
        let hist = e.unit == "tekrar" ? WkProgress.historyOf(ctx, e.name) : []
        return Info(prev: Wk.lastLifted(ctx, eid: eid, before: date),
                    sug: WkProgress.suggestKg(ctx, e, date: date),
                    hist: hist,
                    pr: hist.count > 1 && WkProgress.prsOn(ctx, date).contains { TextNorm.norm($0.name) == TextNorm.norm(e.name) },
                    lvl: e.unit == "tekrar" && profiles.first != nil ? WkProgress.levelOfExercise(ctx, profiles[0], name: e.name) : nil)
    }

    private func history(_ hist: [WkSession], pr: Bool, lvl: WkProgress.LevelRow?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("GEÇMİŞ").font(.geist(12, .medium, relativeTo: .caption)).tracking(0.6).foregroundStyle(Color.bMutedFg)
                if pr { BBadge(variant: .primary) { Ti("trophy", size: 14); Text("Yeni rekor") } }
                Spacer()
                if let lvl { WkLevelChip(idx: lvl.idx) }
            }
            if hist.count > 1 {
                VStack(spacing: 4) {
                    HStack {
                        Text("Tahmini maks. (e1RM)"); Spacer()
                        Text("\(fmt1(hist.last!.best.e1rm)) kg").font(.geist(12, .medium, relativeTo: .caption)).foregroundStyle(Color.bFg)
                    }
                    .font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
                    WkMiniLine(values: hist.suffix(12).map(\.best.e1rm)).frame(height: 72)
                }
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
                .background(Color.bMuted.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            WkListCard {
                ForEach(Array(hist.suffix(5).reversed()), id: \.date) { h in
                    HStack {
                        Text(Wk.longDate(h.date)).foregroundStyle(Color.bMutedFg)
                        Spacer()
                        (Text("\(fmt1(h.best.kg)) kg × \(h.best.reps)").font(.geist(14, .medium, relativeTo: .subheadline)) + Text(" · \(h.sets.count) set").foregroundColor(Color.bMutedFg))
                    }
                    .font(.bSm).monospacedDigit().padding(.horizontal, 12).padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: İşlemler
    private func fillSug(_ e: Exercise, _ kg: Double) {
        guard !future else { return }
        haptic()
        let S = Store.day(ctx, date, create: false)?.sets[eid] ?? []
        for i in 0..<max(0, e.sets) where (i < S.count ? (S[i].kg ?? 0) : 0) <= 0 { Wk.setLog(ctx, date: date, eid: eid, index: i) { $0.kg = kg } }
    }
    private func toggle(_ e: Exercise, _ i: Int, _ S: [SetLog]) {
        guard !future else { return }
        let on = !(i < S.count && S[i].done)
        haptic(on ? .medium : .light)
        if on && e.unit == "tekrar" {
            let s = i < S.count ? S[i] : SetLog()
            let kg = s.kg ?? 0, reps = (s.reps ?? 0) > 0 ? s.reps! : e.reps
            if WkPRShown.mark(date: date, name: e.name, if: WkProgress.beatsPrevBest(ctx, name: e.name, date: date, kg: kg, reps: reps)) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                app.toast(String(localized: "Yeni rekor! \(e.name)"))
            }
        }
        Wk.setLog(ctx, date: date, eid: eid, index: i) { $0.done = on }
    }
    /// Listedeki kutucukla aynı yol: tamamlanma ve işaret kaldırma antrenman durumuna da yansır (PR-07)
    private func markAll() {
        haptic()
        guard let prog, let e = Wk.findExercise(prog, eid) else { return }
        Wk.toggleExDone(ctx, date: date, prog: prog, e: e)
    }
}

/// Favori hareketler (normalize adlar, "|" ile ayrık; @AppStorage ile görünümler anında güncellenir)
enum WkFav {
    static let key = "wk.favs"
    static func set(_ raw: String) -> Set<String> { Set(raw.split(separator: "|").map(String.init)) }
    static func has(_ raw: String, _ name: String) -> Bool { set(raw).contains(TextNorm.norm(name)) }
    static func toggled(_ raw: String, _ name: String) -> String {
        var s = set(raw); let n = TextNorm.norm(name)
        if s.contains(n) { s.remove(n) } else { s.insert(n) }
        return s.sorted().joined(separator: "|")
    }
}

/// Günde hareket başına bir kez "Yeni rekor!"
enum WkPRShown {
    static func mark(date: String, name: String, if cond: Bool) -> Bool {
        guard cond else { return false }
        let k = "wk.pr.\(date)"
        var seen = UserDefaults.standard.stringArray(forKey: k) ?? []
        let n = TextNorm.norm(name)
        guard !seen.contains(n) else { return false }
        seen.append(n); UserDefaults.standard.set(seen, forKey: k)
        return true
    }
}

private struct WkSetRow: View {
    let i: Int
    let log: SetLog
    let forceDone: Bool
    let future: Bool
    let kgPlaceholder: String, repsPlaceholder: String, unit: String
    var onKg: (Double?) -> Void
    var onReps: (Int?) -> Void
    var onToggle: () -> Void
    @State private var reps = ""
    @State private var ready = false
    private enum Field { case kg, reps }
    @FocusState private var focus: Field?
    var body: some View {
        let ok = log.done || forceDone
        HStack(spacing: 8) {
            Text("\(i + 1)").font(.bSm).monospacedDigit().foregroundStyle(Color.bMutedFg).frame(width: 32, alignment: .leading)
            // Kilo oynatıcıdaki gibi: dokununca tekerlekli seçici (4 Kas)
            BPickField(label: "", value: Binding(get: { log.kg ?? 0 }, set: { v in onKg(v == 0 ? nil : v) }),
                       values: SessionView.kgValues, height: 44,
                       zeroText: kgPlaceholder.isEmpty ? "–" : kgPlaceholder,
                       startValue: wkNum(kgPlaceholder) > 0 ? wkNum(kgPlaceholder) : nil,
                       sheetTitle: String(localized: "Set \(i + 1) kilo"))
                .disabled(future)
            // Tekrar burada değiştirilmez; yapılan (ya da planlanan) değer gösterilir
            Text(reps.isEmpty ? repsPlaceholder : reps)
                .font(.geist(16)).monospacedDigit().foregroundStyle(reps.isEmpty ? Color.bMutedFg : Color.bFg)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.bFg.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Set \(i + 1) \(unit): \(reps.isEmpty ? repsPlaceholder : reps)")
            Button(action: onToggle) {
                Ti("check", size: 20)
                    .foregroundStyle(ok ? Color.white : Color.bFg)
                    .frame(width: 44, height: 44)
                    .background(ok ? Color.bSuccess : Color.clear, in: Circle())
                    .overlay { if !ok { Circle().strokeBorder(Color.bBorder, lineWidth: 1) } }
                    .scaleEffect(ok ? 1 : 0.96)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: ok)
            }
                .buttonStyle(.press)
                .disabled(future).opacity(future ? 0.5 : 1)
                .accessibilityLabel("Set \(i + 1) tamam")
        }
        .onAppear {
            guard !ready else { return }
            ready = true
            reps = log.reps.map(String.init) ?? ""
        }
        .onChange(of: reps) { _, v in
            guard ready else { return }
            let n: Int? = v.isEmpty ? nil : min(999, Int(v) ?? 0)
            if n != log.reps { onReps(n) }
        }
        // Dışarıdan değişince (ör. öneriyi doldur) alan odakta değilse güncellensin (WK-08)
        .onChange(of: log.reps) { _, v in if focus != .reps { let t = v.map(String.init) ?? ""; if t != reps { reps = t } } }
    }
}

struct WkMiniLine: View {
    var values: [Double]
    var body: some View {
        GeometryReader { g in
            let P: CGFloat = 6, W = g.size.width, H = g.size.height
            let lo = values.min() ?? 0, hi = values.max() ?? 1, span = (hi - lo) == 0 ? 1 : hi - lo
            let pts = values.enumerated().map { i, v in
                CGPoint(x: P + CGFloat(i) * (W - 2 * P) / CGFloat(max(1, values.count - 1)), y: H - P - CGFloat((v - lo) / span) * (H - 2 * P))
            }
            ZStack {
                Path { p in p.addLines(pts) }.stroke(Color.bPrimary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                ForEach(pts.indices, id: \.self) { i in
                    Circle().fill(Color.bPrimary).frame(width: i == pts.count - 1 ? 8 : 5, height: i == pts.count - 1 ? 8 : 5).position(pts[i])
                }
            }
        }
        .accessibilityLabel("Tahmini maksimum kilo grafiği")
    }
}

// MARK: - Yeni / düzenle hareket

struct WkExForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    let pid: String; let eid: String?; let bid: String?; let preset: String?
    @State private var name = ""
    @State private var unit = "tekrar"
    @State private var sets = "3"
    @State private var reps = "12"
    @State private var rest = "60"
    @State private var kg = ""
    @State private var muscle = ""
    @State private var note = ""
    @State private var loaded = false

    private var prog: WorkoutProgram? { Wk.program(pid, ctx) }
    var body: some View {
        let ss = prog?.blocks.first { $0.kind == .superset && ($0.id == bid || (eid != nil && $0.exs.contains { $0.id == eid })) }
        BSheet(title: eid != nil ? "Hareketi düzenle" : "Yeni hareket") {
            BField(label: "Hareket adı") { TextField("ör. Incline Dumbbell Press", text: $name).textFieldStyle(.b) }
            BField(label: "Birim") { BSegmented(selection: $unit, options: [("tekrar", "Tekrar"), ("sn", "Saniye"), ("dk", "Dakika")]) }
            HStack(alignment: .top, spacing: 12) {
                if ss == nil { BField(label: "Set") { WkNumField(text: $sets) } }
                BField(label: unit == "tekrar" ? "Tekrar" : unit == "sn" ? "Saniye" : "Dakika") { WkNumField(text: $reps) }
                if unit == "tekrar" { BField(label: "Kilo") { WkNumField(placeholder: "–", text: $kg, decimal: true) } }
            }
            if let ss { Text("Süpersette set sayısı tur sayısıdır (\(ss.rounds) tur).").font(.bXs).foregroundStyle(Color.bMutedFg).padding(.top, -8) }
            // Süpersette dinlenme turun sonunda, süperset ayarından gelir (PR-20)
            if ss == nil { BField(label: "Dinlenme (sn)") { WkNumField(text: $rest) } }
        } footer: {
            Button("Kaydet") { save(ss) }.buttonStyle(.b(.primary, .large, full: true)).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            if eid != nil { Button("Hareketi sil") { remove() }.buttonStyle(.b(.ghost, full: true)).bButtonFg(Color.bDestructive) }
        }
        .onAppear(perform: load)
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        if let eid, let e = Wk.findExercise(prog, eid) {
            name = e.name; unit = e.unit; sets = "\(e.sets)"; reps = "\(e.reps)"; rest = "\(e.rest)"
            kg = (e.kg ?? 0) > 0 ? fmt1(e.kg!) : ""; muscle = e.muscle; note = e.note
        } else { name = preset ?? "" }
    }
    private func save(_ ss: Block?) {
        guard let prog else { dismiss(); return }
        let nm = name.trimmingCharacters(in: .whitespaces); guard !nm.isEmpty else { return }
        let k = wkNum(kg)
        var v = Exercise(name: nm, sets: ss.map { max(1, $0.rounds) } ?? wkClamp(sets, 1, 20), reps: wkClamp(reps, 1, 999), unit: unit,
                         rest: ss != nil ? 0 : wkClamp(rest, 0, 900), kg: unit == "tekrar" && k > 0 ? min(999, k) : nil, muscle: muscle, note: note)
        Wk.editBlocks(ctx, prog) { bl in
            if let eid {
                // Adı değişen hareket yeni hareket sayılır; eski adın geçmişi ve rekorları ona geçmesin (PR-06)
                let oldName = bl.allExercises.first { $0.id == eid }?.name ?? nm
                v.id = TextNorm.norm(oldName) == TextNorm.norm(nm) ? eid : UUID().uuidString
                for i in bl.indices {
                    if bl[i].kind == .single, bl[i].ex?.id == eid { bl[i].ex = v; bl[i].rounds = v.sets; bl[i].rest = v.rest }
                    if bl[i].kind == .superset, let j = bl[i].exs.firstIndex(where: { $0.id == eid }) { bl[i].exs[j] = v }
                }
            } else if let bid, let i = bl.firstIndex(where: { $0.id == bid }) {
                bl[i].exs.append(v)
            } else {
                bl.append(Block(single: v))
            }
        }
        haptic(); dismiss()
    }
    private func remove() {
        guard let prog, let eid else { return }
        let nm = Wk.findExercise(prog, eid)?.name ?? "Hareket"
        // Geri al yalnız silineni eski yerine koyar; arada yapılan değişiklikleri ezmez (PR-08)
        let bi = prog.blocks.firstIndex { $0.ex?.id == eid || $0.exs.contains { $0.id == eid } }
        let removedBlock = bi.map { prog.blocks[$0] }
        Wk.editBlocks(ctx, prog) { bl in
            for i in bl.indices.reversed() {
                if bl[i].kind == .single { if bl[i].ex?.id == eid { bl.remove(at: i) } }
                else if let k = bl[i].exs.firstIndex(where: { $0.id == eid }) { bl[i].exs.remove(at: k); if bl[i].exs.isEmpty { bl.remove(at: i) } }
            }
        }
        dismiss()
        app.toast(String(localized: "\(nm) silindi"), kind: .delete) {
            guard let bi, let b = removedBlock, let e = b.exercises.first(where: { $0.id == eid }) else { return }
            var bl = prog.blocks
            guard !bl.contains(where: { $0.ex?.id == eid || $0.exs.contains { $0.id == eid } }) else { return }
            if b.kind == .superset, let i = bl.firstIndex(where: { $0.id == b.id }) {
                let k = b.exs.firstIndex { $0.id == eid } ?? bl[i].exs.count
                bl[i].exs.insert(e, at: min(k, bl[i].exs.count))
            } else if b.kind == .superset {
                bl.insert(Block(id: b.id, superset: [e], rounds: b.rounds, rest: b.rest, tag: b.tag), at: min(bi, bl.count))
            } else {
                bl.insert(b, at: min(bi, bl.count))
            }
            prog.blocks = bl
        }
    }
}

// MARK: - Süperset formu

struct WkBlockForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let pid: String; let bid: String?
    @State private var tag: String = ""
    @State private var rounds = "3"
    @State private var rest = "60"
    @State private var loaded = false
    var body: some View {
        BSheet(title: bid != nil ? "Süperseti düzenle" : "Yeni süperset", description: bid != nil ? nil : "Kaydettikten sonra içine hareket ekle.") {
            BField(label: "Etiket") { BSegmented(selection: $tag, options: [("", "Normal"), ("warm", "Isınma"), ("cool", "Soğuma")]) }
            HStack(alignment: .top, spacing: 12) {
                BField(label: "Tur") { WkNumField(text: $rounds) }
                BField(label: "Tur arası dinlenme (sn)") { WkNumField(text: $rest) }
            }
        } footer: {
            Button("Kaydet") { save() }.buttonStyle(.b(.primary, .large, full: true))
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            if let bid, let b = Wk.program(pid, ctx)?.blocks.first(where: { $0.id == bid }) { tag = b.tag ?? ""; rounds = "\(b.rounds)"; rest = "\(b.rest)" }
        }
    }
    private func save() {
        guard let prog = Wk.program(pid, ctx) else { dismiss(); return }
        let r = wkClamp(rounds, 1, 20), rs = wkClamp(rest, 0, 900), t: String? = tag.isEmpty ? nil : tag
        Wk.editBlocks(ctx, prog) { bl in
            if let bid, let i = bl.firstIndex(where: { $0.id == bid }) {
                bl[i].tag = t; bl[i].rounds = r; bl[i].rest = rs
                for k in bl[i].exs.indices { bl[i].exs[k].sets = r }
            } else {
                bl.append(Block(superset: [], rounds: r, rest: rs, tag: t))
            }
        }
        haptic(); dismiss()
    }
}

// MARK: - Hareket seçici (çoklu seçim)

struct WkExercisePicker: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    let pid: String?; let bid: String?; let newFor: WkNewFor?
    @Binding var route: WkSheet?
    @State private var q = ""
    @State private var group = "all"
    @State private var sel: [String] = []
    @State private var superset = false
    @State private var custom = false
    @State private var dSets = "3"
    @State private var dReps = "12"
    @State private var dKg = ""
    @State private var dRest = "60"
    @State private var lib: [WkLibItem] = []
    @AppStorage(WkFav.key) private var favRaw = ""

    var body: some View {
        let words = TextNorm.norm(q).split(separator: " ").map(String.init)
        let favs = WkFav.set(favRaw)
        let filtered = lib.filter { e in
            (group == "all" || (group == "fav" ? favs.contains(TextNorm.norm(e.name)) : group == "mine" ? (e.mine ?? false) : e.muscle == group)) &&
            (words.isEmpty || { let hay = TextNorm.norm(([e.name] + e.tr + [e.muscle]).joined(separator: " ")); return words.allSatisfy { hay.contains($0) } }())
        }
        // Favoriler listenin başında
        let list = filtered.filter { favs.contains(TextNorm.norm($0.name)) } + filtered.filter { !favs.contains(TextNorm.norm($0.name)) }
        BSheet(title: bid != nil ? "Süpersete hareket ekle" : "Hareket ekle", description: "Birden fazla seçebilirsin; seçim sırasıyla eklenir.") {
            HStack(spacing: 8) {
                Ti("search").foregroundStyle(Color.bMutedFg)
                TextField("Hareket ara (Türkçe ya da İngilizce)", text: $q).font(.geist(16)).autocorrectionDisabled()
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.bInput))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([("all", "Tümü"), ("fav", "★ Favoriler"), ("mine", "Programlarımda")] + WkLibrary.shared.muscles.map { ($0, $0) }, id: \.0) { v, l in
                        Button(l) { group = v }.buttonStyle(.b(group == v ? .primary : .outline, .small))
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
            WkListCard {
                ForEach(list) { e in
                    let i = sel.firstIndex(of: e.name)
                    let fav = favs.contains(TextNorm.norm(e.name))
                    HStack(spacing: 0) {
                    Button { toggle(e.name) } label: {
                        HStack(spacing: 12) {
                            if let i {
                                Text("\(i + 1)").font(.geist(11, .semibold)).monospacedDigit().foregroundStyle(Color.bPrimaryFg)
                                    .frame(width: 20, height: 20).background(Color.bPrimary, in: RoundedRectangle(cornerRadius: 5))
                            } else { BCheck(checked: false) }
                            WkThumb(name: e.name, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name).font(.geist(14, .medium, relativeTo: .subheadline)).lineLimit(1).foregroundStyle(Color.bFg)
                                if let tr = e.tr.first { Text(tr).font(.bXs).lineLimit(1).foregroundStyle(Color.bMutedFg) }
                                Text("\(e.muscle) · \(e.sets) set · \(e.reps) \(e.unit)").font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if e.mine == true {
                                BBadge(variant: .outline) {
                                    Text(e.progs.map { $0.count > 1 ? "\($0[0]) +\($0.count - 1)" : ($0.first ?? "Özel") } ?? "Özel").lineLimit(1)
                                }
                                .frame(maxWidth: 112)
                            }
                        }
                        .padding(.leading, 12).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { haptic(); favRaw = WkFav.toggled(favRaw, e.name) } label: {
                        Image(systemName: fav ? "star.fill" : "star").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(fav ? Color.bPrimary : Color.bMutedFg)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.press)
                    .padding(.trailing, 4)
                    .accessibilityLabel(fav ? "\(e.name) favorilerden çıkar" : "\(e.name) favorilere ekle")
                    }
                }
                if list.isEmpty { Text(group == "fav" ? "Henüz favori yok. Hareketlerin yanındaki yıldıza dokun." : "Bu filtrede hareket yok.").font(.bSm).foregroundStyle(Color.bMutedFg).padding(.horizontal, 16).padding(.vertical, 12) }
            }
            if newFor == nil, let pid {
                let tq = q.trimmingCharacters(in: .whitespaces)
                if !tq.isEmpty && !lib.contains(where: { TextNorm.norm($0.name) == TextNorm.norm(tq) }) {
                    Button { wkGo($route, .exForm(pid: pid, eid: nil, bid: bid, preset: tq)) } label: { BLabel(String(localized: "“\(tq)” adında yeni hareket oluştur"), icon: "plus") }
                        .buttonStyle(.b(.outline, full: true))
                } else if tq.isEmpty {
                    Button("Listede yok mu? Yeni hareket oluştur") { wkGo($route, .exForm(pid: pid, eid: nil, bid: bid, preset: nil)) }
                        .buttonStyle(.b(.ghost, full: true))
                }
            }
        } footer: {
            if !sel.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if bid == nil && sel.count > 1 {
                        Button { superset.toggle() } label: { HStack(spacing: 10) { BCheck(checked: superset); Text("Süperset olarak ekle").font(.bSm) } }.buttonStyle(.plain)
                    }
                    Button { custom.toggle() } label: { HStack(spacing: 10) { BCheck(checked: custom); Text("Set, tekrar ve kiloyu kendim gireyim").font(.bSm) } }.buttonStyle(.plain)
                    if custom {
                        HStack(spacing: 8) {
                            field("Set", $dSets); field("Tekrar", $dReps); field("Kilo", $dKg, decimal: true, ph: "–"); field("Dinl. (sn)", $dRest)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { add() } label: {
                BLabel(sel.isEmpty ? "Hareket seç" : String(localized: "\(sel.count) hareketi \(superset && bid == nil && sel.count > 1 ? tl("süperset olarak ") : "")ekle"), icon: "plus")
            }
            .buttonStyle(.b(.primary, .large, full: true)).disabled(sel.isEmpty)
        }
        .onAppear { if lib.isEmpty { lib = WkLibrary.list(ctx) } }
    }
    private func field(_ l: String, _ t: Binding<String>, decimal: Bool = false, ph: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(tl(l)).font(.bXs).foregroundStyle(Color.bMutedFg); WkNumField(placeholder: ph, text: t, decimal: decimal) }
    }
    private func toggle(_ n: String) { haptic(); if let i = sel.firstIndex(of: n) { sel.remove(at: i) } else { sel.append(n) } }

    private func add() {
        let picked: [Exercise] = sel.compactMap { n in lib.first { $0.name == n } }.map { e in
            Exercise(name: e.name, sets: custom && wkNum(dSets) > 0 ? wkClamp(dSets, 1, 20) : e.sets,
                     reps: custom && e.unit == "tekrar" && wkNum(dReps) > 0 ? wkClamp(dReps, 1, 999) : e.reps,
                     unit: e.unit, rest: custom ? wkClamp(dRest, 0, 900) : e.rest,
                     kg: custom && e.unit == "tekrar" && wkNum(dKg) > 0 ? min(999, wkNum(dKg)) : nil,
                     muscle: e.muscle == "Diğer" ? "" : e.muscle)
        }
        guard !picked.isEmpty else { return }
        var prog: WorkoutProgram?
        var undoNew: (() -> Void)?
        if let newFor {
            let profile = Store.profile(ctx)
            let oldSched = profile.schedule
            let dayLog = Store.day(ctx, newFor.date)
            let oldRaw = dayLog?.programIdRaw
            let p = WorkoutProgram(pid: UUID().uuidString, name: newFor.name.isEmpty ? String(localized: "\(DayKey.dayLong[DayKey.weekday(newFor.date)]) antrenmanı") : newFor.name)
            // Yalnız bu güne özel antrenman listelerde görünmez; Antrenman ekranında düzenlenebilir (GP-11)
            if !(newFor.repeats && newFor.date >= DayKey.today) { p.archived = true }
            ctx.insert(p)
            Wk.assignDay(ctx, profile, date: newFor.date, pid: p.pid, repeats: newFor.repeats && newFor.date >= DayKey.today)
            prog = p
            // Geri al: oluşturulan programı ve plan atamasını tamamen kaldır (WK-11)
            let c = ctx
            undoNew = { profile.schedule = oldSched; dayLog?.programIdRaw = oldRaw; c.delete(p); Store.save(c) }
        } else { prog = Wk.program(pid, ctx) }
        guard let prog else { dismiss(); return }
        let beforeIds = Set(prog.blocks.map(\.id)), beforeEx = Set(prog.blocks.allExercises.map(\.id))
        Wk.editBlocks(ctx, prog) { bl in
            if let bid, let i = bl.firstIndex(where: { $0.id == bid }) {
                let r = max(1, bl[i].rounds)
                bl[i].exs.append(contentsOf: picked.map { var e = $0; e.sets = r; return e })
            } else if superset && picked.count > 1 {
                let rounds = picked.map(\.sets).max() ?? 3
                bl.append(Block(superset: picked.map { var e = $0; e.sets = rounds; e.rest = 0; return e }, rounds: rounds, rest: picked.last?.rest ?? 60))
            } else {
                bl.append(contentsOf: picked.map { Block(single: $0) })
            }
        }
        haptic(); dismiss()
        if let undoNew { app.toast(String(localized: "\(picked.count) hareket eklendi"), undo: undoNew) }
        else {
            // Geri al yalnız eklenenleri kaldırır (PR-08)
            app.toast(String(localized: "\(picked.count) hareket eklendi")) {
                var bl = prog.blocks.filter { beforeIds.contains($0.id) }
                for i in bl.indices where bl[i].kind == .superset { bl[i].exs.removeAll { !beforeEx.contains($0.id) } }
                prog.blocks = bl
            }
        }
    }
}

// MARK: - Güne program seç / hazır plan yükle

struct WkPickProgramSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutProgram.createdAt) private var programs: [WorkoutProgram]
    let date: String; let load: Bool; let repeat0: Bool?
    @Binding var route: WkSheet?
    @State private var name = ""
    @State private var repeatOn = false
    @State private var ready = false

    var body: some View {
        let profile = Store.profile(ctx)
        let cur = Wk.programFor(date, profile: profile, ctx: ctx)
        let rep = repeatOn && date >= DayKey.today
        let dayName = Wk.lower(DayKey.dayLong[DayKey.weekday(date)])
        BSheet(title: load ? "Hazır plan yükle" : "Bu güne antrenman",
               description: rep ? String(localized: "Her \(dayName) tekrar eder; geçmiş günler değişmez.") : "Sadece bu tarih için geçerli; haftalık plan değişmez.") {
            if repeat0 != false { WkRepeatToggle(date: date, value: $repeatOn) }
            if !load {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Yeni antrenman oluştur").font(.geist(16, .medium))
                    TextField("ör. Kol + Karın", text: $name).textFieldStyle(.b)
                    Button { wkGo($route, .exPicker(pid: nil, bid: nil, newFor: WkNewFor(date: date, repeats: rep, name: name.trimmingCharacters(in: .whitespaces)))) } label: { BLabel("Hareket seç", icon: "plus") }
                        .buttonStyle(.b(.primary, full: true))
                }
                .bCard()
            }
            WkSectionTitle("Kayıtlı antrenmanlar")
            WkListCard {
                ForEach(programs.filter { !$0.archived || $0.pid == cur?.pid }) { p in
                    Button { pick(p.pid, rep) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.geist(16, .medium)).foregroundStyle(Color.bFg)
                                Text("\(p.blocks.allExercises.count) hareket").font(.bXs).foregroundStyle(Color.bMutedFg)
                            }
                            Spacer()
                            if cur?.pid == p.pid { Ti("check", size: 20).foregroundStyle(Color.bPrimary) } else { Ti("chevron-right").foregroundStyle(Color.bMutedFg) }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button { pick(nil, rep) } label: {
                    HStack {
                        Text("Dinlenme").font(.geist(16, .medium)).foregroundStyle(Color.bFg)
                        Spacer()
                        if cur == nil { Ti("check", size: 20).foregroundStyle(Color.bPrimary) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            WkSectionTitle("Hazır antrenmanlar")
            Text("Seçtiğin gün kayıtlı antrenmanlarına eklenir ve bu güne atanır.").font(.bSm).foregroundStyle(Color.bMutedFg).padding(.top, -8)
            ForEach(WkTemplate.all) { t in
                VStack(alignment: .leading, spacing: 6) {
                    Text(t.name).font(.geist(12, .medium, relativeTo: .caption)).foregroundStyle(Color.bMutedFg)
                    WkListCard {
                        ForEach(Array(t.programs.enumerated()), id: \.offset) { _, p in
                            Button { pickDefault(p, rep) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.name).font(.geist(16, .medium)).foregroundStyle(Color.bFg)
                                        Text("\(p.blocks.allExercises.count) hareket").font(.bXs).foregroundStyle(Color.bMutedFg)
                                    }
                                    Spacer()
                                    Ti("plus").foregroundStyle(Color.bMutedFg)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear { if !ready { ready = true; repeatOn = repeat0 ?? (date >= DayKey.today) } }
    }
    private func pick(_ pid: String?, _ rep: Bool) {
        haptic()
        Wk.assignDay(ctx, Store.profile(ctx), date: date, pid: pid, repeats: rep)
        dismiss()
    }
    private func pickDefault(_ p: WkTemplateProgram, _ rep: Bool) {
        if let ex = programs.first(where: { $0.name == p.name && !$0.archived }) { return pick(ex.pid, rep) }
        let c = Wk.clone(p); ctx.insert(c)
        Wk.assignDay(ctx, Store.profile(ctx), date: date, pid: c.pid, repeats: rep)
        app.toast(String(localized: "\(p.name) eklendi")); dismiss()
    }
}

/// Boş günde "Antrenman ekle" → hazır plan ya da kendi planı. Yalnız bu güne eklenir; haftalık plan Profil › Antrenmanlarım'dan
/// düzenlenir ve bu güne özel antrenman plandakini ezer (GP-11)
struct WkDayPlanSheet: View {
    let date: String
    /// Bu güne atanmış ama boş bir program varsa hareketler ona eklenir
    var pid: String? = nil
    @Binding var route: WkSheet?
    private let repeatOn = false
    var body: some View {
        BSheet(title: "Antrenman ekle", description: String(localized: "Yalnız \(Wk.longDate(date)) için; haftalık plan değişmez.")) {
            opt(icon: "template", title: "Hazır plan yükle", desc: "Kayıtlı antrenmanların ya da hazır programlardan seç.") {
                wkGo($route, .pickProgram(date: date, load: true, repeats: repeatOn))
            }
            opt(icon: "wand", title: "Kendi planını oluştur", desc: "Hareketleri tek tek seç; plan ancak hareket eklersen kaydedilir.") {
                if let pid { wkGo($route, .exPicker(pid: pid, bid: nil, newFor: nil)) }
                else { wkGo($route, .exPicker(pid: nil, bid: nil, newFor: WkNewFor(date: date, repeats: repeatOn))) }
            }
        }
        .presentationDetents([.medium, .large])
    }
    private func opt(icon: String, title: String, desc: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Ti(icon, size: 24).foregroundStyle(Color.bPrimary).frame(width: 48, height: 48).background(Color.bPrimary.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(tl(title)).font(.geist(16, .semibold)).foregroundStyle(Color.bFg)
                    Text(tl(desc)).font(.bSm).foregroundStyle(Color.bMutedFg).multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Ti("chevron-right").foregroundStyle(Color.bMutedFg)
            }
            .bCard()
        }
        .buttonStyle(.press)
    }
}

// MARK: - İlerleme

struct WkProgressSheet: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query private var days: [DayLog]   // değişince yeniden hesaplansın
    var body: some View {
        let W = WkProgress.weeks(ctx, 8)
        let prs = Array(WkProgress.prList(WkProgress.histories(ctx)).prefix(10))
        let streak = WkProgress.streakWeeks(ctx)
        let _ = days.count
        BSheet(title: "İlerleme", description: "Hacim yalnız tekrar bazlı hareketlerin tamamlanan setlerinden (kilo × tekrar) hesaplanır.") {
            HStack(spacing: 8) {
                stat("Bu hafta", vol(W.last?.vol ?? 0)); stat("Antrenman", String(localized: "\(W.last?.workouts ?? 0) gün")); stat("Seri", String(localized: "\(streak) hafta"))
            }
            VStack(alignment: .leading, spacing: 8) { WkSectionTitle("Haftalık hacim (ton)"); WkVolumeBars(W: W) }
            VStack(alignment: .leading, spacing: 8) {
                WkSectionTitle("Son rekorlar")
                if prs.isEmpty {
                    WkEmpty(icon: "trophy", title: "Henüz rekor yok", text: "Bir hareketi ikinci kez yapıp öncekini geçtiğinde burada görünür.")
                } else {
                    WkListCard {
                        ForEach(prs) { p in
                            HStack(spacing: 12) {
                                Ti("trophy", size: 20).foregroundStyle(Color.bPrimary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.geist(16, .medium)).lineLimit(1)
                                    Text(Wk.longDate(p.date)).font(.bXs).foregroundStyle(Color.bMutedFg)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(fmt1(p.kg)) kg × \(p.reps)").font(.bNum(16))
                                    Text("≈ \(fmt1(p.e1rm)) kg maks.").font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                    }
                }
            }
            if let p = profiles.first { WkStrengthSection(profile: p) }
        }
    }
    private func vol(_ v: Double) -> String { v >= 10000 ? String(localized: "\(fmt1(v / 1000)) t") : String(localized: "\(fmt0(v)) kg") }
    private func stat(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tl(l)).font(.bXs).foregroundStyle(Color.bMutedFg)
            Text(v).font(.bNum(16)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color.bMuted.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct WkVolumeBars: View {
    var W: [WkWeek]
    var body: some View {
        let mx = max(1, W.map(\.vol).max() ?? 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(W.enumerated()), id: \.offset) { i, w in
                VStack(spacing: 4) {
                    Text(w.vol > 0 ? fmt1(w.vol / 1000) : " ").font(.geist(11, relativeTo: .caption2)).monospacedDigit().foregroundStyle(Color.bMutedFg)
                    ZStack(alignment: .bottom) {
                        Color.clear
                        if w.vol > 0 {
                            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                                .fill(i == W.count - 1 ? Color.bPrimary : Color.bFg.opacity(0.25))
                                .frame(height: max(4, 112 * w.vol / mx))
                        }
                    }
                    .frame(height: 112)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.bBorder).frame(height: 1) }
                    Text(Wk.shortDate(w.start).split(separator: " ").first.map(String.init) ?? "").font(.geist(11, relativeTo: .caption2)).monospacedDigit().foregroundStyle(Color.bMutedFg)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.5), value: W.map(\.vol))
        .accessibilityLabel("Son 8 haftanın hacmi")
    }
}

private struct WkStrengthSection: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Bindable var profile: UserProfile
    var body: some View {
        let S = WkProgress.strengthLevels(ctx, profile)
        VStack(alignment: .leading, spacing: 8) {
            WkSectionTitle(title: "Güç seviyesi") { if profile.sex != nil, S.bw > 0 { Text("\(fmt1(S.bw)) kg").font(.bXs).foregroundStyle(Color.bMutedFg) } }
            VStack(alignment: .leading, spacing: 6) {
                Text("Güç standardı").font(.bXs).foregroundStyle(Color.bMutedFg)
                BSegmented(selection: Binding(get: { profile.sex?.rawValue ?? "" }, set: { haptic(); profile.sex = Sex(rawValue: $0) }),
                           options: [("male", "Erkek"), ("female", "Kadın")])
            }
            if S.need == "sex" {
                Text("Seviyeni hesaplamak için hangi standarda göre ölçeceğini seç.").font(.bSm).foregroundStyle(Color.bMutedFg)
            } else if S.need == "bw" && S.rows.isEmpty {
                WkEmpty(icon: "barbell", title: "Kilonu gir", text: "Güç seviyesi, kaldırdığın kilonun vücut ağırlığına oranıyla hesaplanır.") {
                    Button("Kilo gir") { app.open(.measure(quick: true)) }.buttonStyle(.b(.outline))
                }
            } else if !S.rows.isEmpty {
                WkListCard {
                    ForEach(S.rows) { r in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.lift.name).font(.geist(16, .medium)).lineLimit(1)
                                    Text(r.isReps ? "En çok \(Int(r.value)) tekrar" : "≈ \(fmt1(r.value)) kg maks. · \(fmt1(r.ratio))× vücut ağırlığı").font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                WkLevelChip(idx: r.idx)
                            }
                            BProgress(value: r.pct)
                            Text(r.nextLabel.map { String(localized: "\(tl($0)) için \(r.isReps ? String(localized: "+\(Int(r.toNext)) tekrar") : "+\(fmt1(r.toNext)) kg")") } ?? String(localized: "En üst seviyedesin"))
                                .font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }
            } else {
                WkEmpty(icon: "barbell", title: "Henüz ana hareket kaydı yok", text: "Bench press, squat, deadlift, overhead press, barbell row ya da barfiks setlerini tamamladığında seviyen burada görünür.")
            }
            Text("Tahmini maks. (Epley) / vücut ağırlığı; eşikler Strength Level ortalamalarından yuvarlandı. Dumbbell ve makine varyantları sayılmaz.").font(.bXs).foregroundStyle(Color.bMutedFg)
        }
    }
}


/// Fotoğraf yuvası: fotoğraf arşivinden ya da kameradan seç, kaldır
struct WkPhotoSlot: View {
    let title: String
    @Binding var image: UIImage?
    var changed: () -> Void
    @State private var item: PhotosPickerItem?
    @State private var camera = false
    /// PhotosPicker Menu içindeyken açılmıyordu; menüdeki düğme bu bayrakla seçiciyi açar (GP-07)
    @State private var library = false
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Menu {
                    Button { camera = true } label: { Label("Fotoğraf çek", systemImage: "camera") }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    Button { library = true } label: { Label("Fotoğraflardan seç", systemImage: "photo.on.rectangle") }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.bCard)
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 24)).foregroundStyle(Color.bMutedFg)
                                Text("Ekle").font(.bXs).foregroundStyle(Color.bMutedFg)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 120)
                    .clipped()
                }
                if image != nil {
                    Button { withAnimation { image = nil }; changed() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .padding(6).accessibilityLabel("\(title) görselini kaldır")
                }
            }
            if !title.isEmpty { Text(title).font(.bXs).foregroundStyle(Color.bMutedFg) }
        }
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task {
                if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    await MainActor.run { withAnimation { image = UserMotion.shrink(img) ?? img }; changed() }
                }
                item = nil
            }
        }
        .photosPicker(isPresented: $library, selection: $item, matching: .images)
        .fullScreenCover(isPresented: $camera) {
            WkCamera { img in image = UserMotion.shrink(img) ?? img; changed() }.ignoresSafeArea()
        }
    }
}

/// Basit kamera (UIImagePickerController)
struct WkCamera: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController(); c.sourceType = .camera; c.delegate = context.coordinator; return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }
    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let p: WkCamera
        init(_ p: WkCamera) { self.p = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { p.onPick(img) }
            p.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { p.dismiss() }
    }
}

/// Form videosu araması; "&", "+", "=" gibi karakterler de kodlanır (QA-05)
func wkFormVideoURL(_ name: String) -> URL {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&+=?#")
    let q = (name + " exercise form").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    return URL(string: "https://www.youtube.com/results?search_query=\(q)") ?? URL(string: "https://www.youtube.com")!
}

/// Bilgi çipi (seans ve hareket sayfası)
func wkChip(_ icon: String, _ text: String, tint: Color = .bFg) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon).font(.system(size: 13, weight: .semibold))
        Text(tl(text)).font(.geist(13, .medium, relativeTo: .footnote)).monospacedDigit().lineLimit(1)
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 36)   // büyük yazıda kırpılmasın (AX-01)
    .background(Color.bFg.opacity(0.07), in: Capsule())
}
