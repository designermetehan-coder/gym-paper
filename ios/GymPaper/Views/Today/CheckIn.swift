import SwiftUI
import SwiftData
import GymPaperKit

// Weekly check-in (Figma "Check-in"): weigh-in, how the week felt, weekly report, changes for next week.
// Ready on Sunday or once every planned workout of the week is done; stays on Today until reviewed or closed.

struct CheckInRecord: Codable, Hashable {
    var week: String
    var kg: Double?
    var energy = 3, sleep = 3, hunger = 3, difficulty = 3
    var date = Date.now
}

enum CheckInStore {
    private static let recordsKey = "checkin.records"
    private static let dismissedKey = "checkin.dismissed"
    static func records() -> [String: CheckInRecord] {
        guard let d = UserDefaults.standard.data(forKey: recordsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: CheckInRecord].self, from: d)) ?? [:]
    }
    static func save(_ r: CheckInRecord) {
        var all = records(); all[r.week] = r
        let cut = DayKey.shift(DayKey.today, days: -400)
        all = all.filter { $0.key >= cut }
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: recordsKey)
    }
    static func dismissed() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []) }
    static func dismiss(_ week: String) {
        var s = dismissed(); s.insert(week)
        UserDefaults.standard.set(Array(s.sorted().suffix(30)), forKey: dismissedKey)
    }
    static func handled(_ week: String) -> Bool { records()[week] != nil || dismissed().contains(week) }
}

/// Numbers for one week (Monday key)
struct CheckInWeek {
    var start: String
    var planned = 0, done = 0, sets = 0
    var kgChange: Double?
    var kcalDays = 0, loggedDays = 0
    var proteinAvg: Double?
    var entries: [MuscleLoad.Entry] = []

    @MainActor init(_ start: String, profile: UserProfile, ctx: ModelContext, health: HealthService, measures: [BodyMeasure]) {
        self.start = start
        let end = DayKey.shift(start, days: 6)
        let logs = Wk.allDays(ctx).filter { $0.date >= start && $0.date <= end }
        for i in 0..<7 {
            let d = DayKey.shift(start, days: i)
            guard d <= DayKey.today else { break }
            let log = logs.first { $0.date == d }
            if let p = Wk.programFor(d, profile: profile, ctx: ctx) {
                planned += 1
                if let log, log.workoutDone || workoutProgress(p, day: log).complete { done += 1 }
            } else if log?.workoutDone == true { done += 1; planned += 1 }
            if let log, log.eaten.kcal > 0 {
                loggedDays += 1
                let target = Energy.summary(profile: profile, health: health, day: log, latestMeasureKg: nil, isToday: false).target
                if log.eaten.kcal <= target + 100 { kcalDays += 1 }
            }
        }
        let protein = logs.map(\.eaten.p).filter { $0 > 0 }
        proteinAvg = protein.isEmpty ? nil : protein.reduce(0, +) / Double(protein.count)
        let r = MuscleData.range(ctx, logs: logs, from: start, to: end)
        sets = r.sets
        entries = MuscleLoad.load(r.items, scope: .week)
        let startDate = DayKey.date(start) ?? .now, endDate = DayKey.date(DayKey.shift(end, days: 1)) ?? .now
        let inWeek = measures.filter { $0.kg != nil && $0.date >= startDate && $0.date < endDate }.sorted { $0.date < $1.date }
        let before = measures.filter { $0.kg != nil && $0.date < startDate }.max { $0.date < $1.date }
        if let last = inWeek.last?.kg, let ref = before?.kg ?? inWeek.first?.kg, inWeek.count > (before == nil ? 1 : 0) {
            kgChange = last - ref
        }
    }

    var summary: String {
        var parts = [String(localized: "\(done)/\(planned) antrenman"), String(localized: "\(sets) set")]
        if let k = kgChange { parts.append("\(k <= 0 ? "−" : "+")\(fmt1(abs(k))) kg") }
        return parts.joined(separator: " · ")
    }

    /// The week a check-in is offered for: this week once ready, or last week until Tuesday if it was never handled
    @MainActor static func pending(profile: UserProfile, ctx: ModelContext, health: HealthService, measures: [BodyMeasure]) -> CheckInWeek? {
        let today = DayKey.today
        let monday = DayKey.shift(today, days: -DayKey.weekday(today))
        if !CheckInStore.handled(monday) {
            let w = CheckInWeek(monday, profile: profile, ctx: ctx, health: health, measures: measures)
            if DayKey.weekday(today) == 6 || (w.planned > 0 && w.done >= w.planned && w.planned == plannedWholeWeek(monday, profile, ctx)) { return w }
        }
        let last = DayKey.shift(monday, days: -7)
        if DayKey.weekday(today) <= 1, !CheckInStore.handled(last) {
            let w = CheckInWeek(last, profile: profile, ctx: ctx, health: health, measures: measures)
            if w.done > 0 { return w }
        }
        return nil
    }
    @MainActor private static func plannedWholeWeek(_ monday: String, _ p: UserProfile, _ ctx: ModelContext) -> Int {
        (0..<7).filter { Wk.programFor(DayKey.shift(monday, days: $0), profile: p, ctx: ctx) != nil }.count
    }
}

// MARK: - Today card

struct WeeklyCheckInCard: View {
    @Environment(\.modelContext) private var ctx
    @Environment(HealthService.self) private var health
    @Environment(AppState.self) private var app
    @Query(sort: \BodyMeasure.date, order: .reverse) private var measures: [BodyMeasure]
    @Query private var logs: [DayLog]
    let profile: UserProfile
    @State private var open: CheckInWeek?
    /// Computed off the render path: recomputed on appear and when logs, measurements or the dismissal change
    @State private var pending: CheckInWeek?

    var body: some View {
        Group {
            if let w = pending {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Ti("calendar-week", size: 20).foregroundStyle(Color.bHeroOnHi)
                            .frame(width: 40, height: 40).background(Color.bHeroHi, in: RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Haftan bitti, check-in hazır").font(.bDisplay(17, relativeTo: .headline))
                            Text(w.summary).font(.bXs).monospacedDigit().foregroundStyle(Color.bHeroMuted)
                        }
                        Spacer(minLength: 4)
                        Button { haptic(); CheckInStore.dismiss(w.start); withAnimation(.snappy) { pending = nil } } label: { Ti("x", size: 16) }
                            .buttonStyle(BGlassIconStyle(size: 32)).accessibilityLabel(tl("Kapat"))
                    }
                    Button { haptic(); open = w } label: { Text("2 dakikada değerlendir").frame(maxWidth: .infinity) }
                        .buttonStyle(.b(.primary, .large, full: true))
                }
                .bHeroCard()
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .onAppear { recompute() }
        .onChange(of: logs.count) { recompute() }
        .onChange(of: measures.count) { recompute() }
        .fullScreenCover(item: Binding(get: { open.map { IdentWeek(w: $0) } }, set: { if $0 == nil { open = nil; recompute() } })) { iw in
            CheckInFlow(week: iw.w, profile: profile).environment(app).environment(health)
        }
    }
    private func recompute() {
        pending = CheckInWeek.pending(profile: profile, ctx: ctx, health: health, measures: measures)
    }
    private struct IdentWeek: Identifiable { var w: CheckInWeek; var id: String { w.start } }
}

// MARK: - Flow

struct CheckInFlow: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(HealthService.self) private var health
    @Query(sort: \BodyMeasure.date, order: .reverse) private var measures: [BodyMeasure]
    let week: CheckInWeek
    let profile: UserProfile
    @State private var step = 0
    @State private var rec: CheckInRecord
    @State private var kg: Double = 0
    @State private var picks: Set<String> = []

    init(week: CheckInWeek, profile: UserProfile) {
        self.week = week; self.profile = profile
        _rec = State(initialValue: CheckInRecord(week: week.start))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { haptic(); if step == 0 { dismiss() } else { withAnimation(.snappy) { step -= 1 } } } label: { Ti(step == 0 ? "x" : "chevron-left", size: 20) }
                    .buttonStyle(BGlassIconStyle()).accessibilityLabel(tl(step == 0 ? "Kapat" : "Geri"))
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in Capsule().fill(i <= step ? Color.bFg : Color.bFg.opacity(0.12)).frame(height: 4) }
                }
                .accessibilityElement().accessibilityLabel(Text("Adım \(step + 1)/4"))
            }
            .padding(.horizontal, 20).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case 0: weighIn
                    case 1: feelings
                    case 2: report
                    default: changes
                    }
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            Button { next() } label: {
                HStack(spacing: 8) { Text(cta); if step == 3 { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)) } }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.b(.primary, .large, full: true))
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background { ZStack(alignment: .top) { Color.bBg; BWash(style: .dominant) }.ignoresSafeArea() }
        .onAppear { kg = measures.first(where: { $0.kg != nil })?.kg ?? 0 }
    }

    private var cta: String {
        switch step {
        case 0: tl(kg > 0 ? "Devam" : "Atla")
        case 2: tl("Önerileri gör")
        case 3: picks.isEmpty ? tl("Bitir") : String(localized: "\(picks.count) değişikliği uygula")
        default: tl("Devam")
        }
    }

    private func head(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased(with: .current)).font(.geist(12, .medium, relativeTo: .caption)).tracking(0.6).foregroundStyle(Color.bMutedFg)
            Text(title).font(.bDisplay(28, relativeTo: .title)).tracking(-0.5).foregroundStyle(Color.bFg)
        }
    }

    // 1/4 · weigh-in
    private var weighIn: some View {
        VStack(alignment: .leading, spacing: 16) {
            head(String(localized: "Check-in · 1/4"), tl("Haftanın tartısı"))
            Text("Sabah, aç karnına tartılmak en tutarlı sonucu verir.").font(.bSm).foregroundStyle(Color.bMutedFg)
            BKgField(label: tl("Kilo"), value: $kg, suffix: "kg", height: 72)
        }
    }

    // 2/4 · how the week felt
    private var feelings: some View {
        VStack(alignment: .leading, spacing: 12) {
            head(String(localized: "Check-in · 2/4"), tl("Bu hafta nasıldı?"))
            rating("Enerji", "Düşük → Yüksek", $rec.energy)
            rating("Uyku", "Kötü → İyi", $rec.sleep)
            rating("Açlık", "Yok → Çok", $rec.hunger)
            rating("Antrenman zorluğu", "Kolay → Çok zor", $rec.difficulty)
        }
    }
    private func rating(_ title: String, _ hint: String, _ v: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tl(title)).font(.geist(16, .semibold, relativeTo: .headline))
                Spacer()
                Text(tl(hint)).font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { n in
                    Button { haptic(); v.wrappedValue = n } label: {
                        Text("\(n)").font(.geist(16, .semibold)).frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(v.wrappedValue == n ? Color.bSelFg : Color.bFg)
                            .background(v.wrappedValue == n ? Color.bSel : Color.bMuted, in: RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
                    }
                    .buttonStyle(.press)
                    .accessibilityAddTraits(v.wrappedValue == n ? .isSelected : [])
                }
            }
        }
        .foregroundStyle(Color.bFg)
        .bCard()
        .accessibilityElement(children: .contain)
    }

    // 3/4 · weekly report
    private var report: some View {
        let G = GoalState(startKg: profile.startKg, goals: profile.goals, measures: measures)
        let groups = Dictionary(grouping: week.entries) { $0.sets > 20 ? 2 : $0.sets >= 10 ? 1 : 0 }
        return VStack(alignment: .leading, spacing: 16) {
            head(weekTitle, tl("Haftalık rapor"))
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(week.kgChange.map { "\($0 <= 0 ? "−" : "+")\(fmt1(abs($0)))" } ?? "–").font(.bNum(44, relativeTo: .largeTitle))
                    Text("kg").font(.bSm).foregroundStyle(Color.bHeroMuted)
                    Spacer()
                    if G.active != nil {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(localized: "Hedef −\(fmt1(profile.weeklyLossKg)) kg")).font(.bXs)
                            if let k = week.kgChange, profile.weeklyLossKg > 0 {
                                let share = max(0, min(2, -k / profile.weeklyLossKg)).formatted(.percent.precision(.fractionLength(0)))
                                Text(String(localized: "Hedefin \(share)")).font(.bXs).foregroundStyle(Color.bHeroMuted)
                            }
                        }
                    }
                }
                BProgress(value: week.kgChange.map { profile.weeklyLossKg > 0 ? -$0 / profile.weeklyLossKg : 0 } ?? 0, tint: .bHeroHi, track: .bHeroFill, label: "Haftalık kilo hedefi")
            }
            .bHeroCard()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Bu hafta kaslar").font(.bDisplay(17, relativeTo: .headline))
                    Spacer()
                    Text(String(localized: "\(week.sets) set")).font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
                }
                HStack(alignment: .top, spacing: 14) {
                    MuscleMapView(levels: Dictionary(week.entries.map { ($0.muscle, $0.level) }, uniquingKeysWith: { a, _ in a }), figureHeight: 120).frame(width: 130)
                    VStack(alignment: .leading, spacing: 10) {
                        group("Hedefte", groups[1])
                        group("Fazla", groups[2])
                        group("Az", groups[0])
                    }
                }
                HeatLegend(scope: .week)
            }
            .foregroundStyle(Color.bFg)
            .bCard()
            VStack(spacing: 0) {
                reportRow("barbell", "Antrenman", String(localized: "Planlanan \(week.planned) gün"), "\(week.done)/\(week.planned)", ok: week.planned > 0 && week.done >= week.planned)
                ProgressDivider()
                reportRow("flame", "Kalori hedefi", String(localized: "\(week.loggedDays) gün kayıt"), "\(week.kcalDays)/\(max(week.loggedDays, 1))", ok: week.loggedDays > 0 && week.kcalDays >= week.loggedDays - 1)
                ProgressDivider()
                reportRow("tools-kitchen-2", "Protein ortalaması", String(localized: "Hedef \(fmt0(profile.proteinG)) g"),
                          week.proteinAvg.map { "\(fmt0($0)) g" } ?? "–", ok: (week.proteinAvg ?? 0) >= profile.proteinG * 0.9)
            }
            .background(Color.bCard, in: RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
        }
    }
    @ViewBuilder private func group(_ title: String, _ e: [MuscleLoad.Entry]?) -> some View {
        if let e, !e.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(tl(title)).font(.geist(14, .semibold, relativeTo: .subheadline))
                Text(e.map { tl($0.muscle) }.joined(separator: ", ")).font(.bXs).foregroundStyle(Color.bMutedFg).lineLimit(2)
            }
        }
    }
    private func reportRow(_ icon: String, _ title: String, _ sub: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 12) {
            Ti(icon, size: 18).frame(width: 40, height: 40).background(Color.bMuted, in: RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(tl(title)).font(.geist(16, .semibold, relativeTo: .headline))
                Text(sub).font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            Spacer()
            Text(value).font(.bDisplay(16, relativeTo: .body)).monospacedDigit()
            Image(systemName: ok ? "checkmark.circle.fill" : "flag.fill").foregroundStyle(ok ? Color.bSuccess : Color.fitTime)
        }
        .foregroundStyle(Color.bFg)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
    private var weekTitle: String {
        let end = DayKey.shift(week.start, days: 6)
        return "\(trShortDate(week.start)) – \(trShortDate(end))"
    }

    // 4/4 · changes for next week
    private struct Change: Identifiable { var id: String; var kind: String; var title: String; var detail: String; var apply: (() -> Void)? }
    private var suggestions: [Change] {
        var out: [Change] = []
        let target = Energy.summary(profile: profile, health: health, day: nil, latestMeasureKg: kg > 0 ? kg : nil, isToday: false).target
        if let k = week.kgChange, profile.weeklyLossKg > 0 {
            if k > -profile.weeklyLossKg * 0.5, rec.hunger <= 3 {
                let new = (target - 50).rounded()
                out.append(Change(id: "kcal", kind: tl("Kalori"), title: "\(fmt0(target)) → \(fmt0(new)) kcal",
                                  detail: tl("Kilo hedefe göre yavaş iniyor; açlık düşük olduğu için 50 kcal azaltmak güvenli.")) { profile.manualKcal = new })
            } else if k < -profile.weeklyLossKg * 1.5 || rec.hunger >= 5 {
                let new = (target + 100).rounded()
                out.append(Change(id: "kcal", kind: tl("Kalori"), title: "\(fmt0(target)) → \(fmt0(new)) kcal",
                                  detail: tl("Hızlı iniyorsun ya da çok acıkıyorsun; 100 kcal eklemek kası korur.")) { profile.manualKcal = new })
            }
        }
        if let p = week.proteinAvg, p < profile.proteinG * 0.9 {
            out.append(Change(id: "protein", kind: tl("Protein"), title: tl("Kahvaltıya bir protein kaynağı"),
                              detail: String(localized: "Ortalaman \(fmt0(p)) g; günde \(fmt0(profile.proteinG - p)) g daha eklemek hedefe taşır."), apply: nil))
        }
        if let gap = MuscleLoad.gap(week.entries, scope: .week, workouts: max(1, week.done)),
           let (d, prog) = nextWorkout(), let ex = MuscleData.suggested(gap, exclude: prog.blocks.allExercises, ctx: ctx) {
            out.append(Change(id: "workout", kind: tl("Antrenman"), title: "\(DayKey.dayLong[DayKey.weekday(d)]): \(ex.name) · \(MuscleData.dose(ex))",
                              detail: String(localized: "\(tl(gap.muscle)) bu hafta az çalıştı.")) { Wk.editBlocks(ctx, prog) { $0.append(Block(single: ex)) } })
        }
        return out
    }
    private func nextWorkout() -> (String, WorkoutProgram)? {
        let today = DayKey.today
        for i in 1...7 {
            let d = DayKey.shift(today, days: i)
            if let p = Wk.programFor(d, profile: profile, ctx: ctx) { return (d, p) }
        }
        return nil
    }
    private var changes: some View {
        let list = suggestions
        return VStack(alignment: .leading, spacing: 12) {
            head(String(localized: "Check-in · 4/4"), list.isEmpty ? tl("Böyle devam") : String(localized: "Gelecek hafta için \(list.count) değişiklik"))
            if list.isEmpty {
                Text("Bu hafta her şey yolunda; planı aynen sürdür.").font(.bSm).foregroundStyle(Color.bMutedFg)
            }
            ForEach(list) { c in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.kind).font(.bXs).foregroundStyle(Color.bMutedFg)
                        Text(c.title).font(.bDisplay(17, relativeTo: .headline))
                        Text(c.detail).font(.bSm).foregroundStyle(Color.bMutedFg)
                    }
                    Spacer(minLength: 8)
                    if c.apply != nil {
                        Toggle(c.kind, isOn: Binding(get: { picks.contains(c.id) }, set: { on in haptic(); if on { picks.insert(c.id) } else { picks.remove(c.id) } }))
                            .labelsHidden().tint(Color.bSuccess)
                    }
                }
                .foregroundStyle(Color.bFg)
                .bCard()
            }
            Text("Öneriler yalnız öneridir; istediğin zaman Profil'den geri alabilirsin.").font(.bXs).foregroundStyle(Color.bMutedFg)
        }
        .onAppear { if picks.isEmpty { picks = Set(list.filter { $0.apply != nil }.map(\.id)) } }
    }

    private func next() {
        haptic()
        switch step {
        case 0:
            if kg > 0, abs(kg - (measures.first(where: { $0.kg != nil })?.kg ?? 0)) > 0.01 || !Calendar.current.isDateInToday(measures.first?.date ?? .distantPast) {
                ctx.insert(BodyMeasure(date: .now, kg: kg)); Store.save(ctx)
            }
            rec.kg = kg > 0 ? kg : nil
            withAnimation(.snappy) { step = 1 }
        case 3:
            for c in suggestions where picks.contains(c.id) { c.apply?() }
            Store.save(ctx)
            CheckInStore.save(rec)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            app.toast(picks.isEmpty ? tl("Check-in kaydedildi") : String(localized: "Check-in kaydedildi · \(picks.count) değişiklik"))
            dismiss()
        default:
            withAnimation(.snappy) { step += 1 }
        }
    }
}
