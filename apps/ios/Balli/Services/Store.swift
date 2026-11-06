import Foundation
import SwiftData
import BalliKit
import os

extension Notification.Name {
    /// Kayıt başarısız: RootView kullanıcıya uyarı gösterir (CR-14)
    static let balliSaveFailed = Notification.Name("balli.saveFailed")
}

/// Ortak veri yardımcıları
@MainActor
enum Store {
    private static let log = Logger(subsystem: "com.metehankaya.balli", category: "store")

    /// Ortak kayıt: hata sessizce yutulmaz; loglanır ve arayüze bildirilir (CR-14)
    @discardableResult
    static func save(_ ctx: ModelContext) -> Bool {
        guard ctx.hasChanges else { return true }
        do { try ctx.save(); return true } catch {
            log.error("Kayıt başarısız: \(error.localizedDescription, privacy: .public)")
            NotificationCenter.default.post(name: .balliSaveFailed, object: error.localizedDescription)
            return false
        }
    }

    static func profile(_ ctx: ModelContext) -> UserProfile {
        if let p = try? ctx.fetch(FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])).first { return p }
        let p = UserProfile()
        ctx.insert(p)
        return p
    }

    static func day(_ ctx: ModelContext, _ key: String, create: Bool = true) -> DayLog? {
        let d = FetchDescriptor<DayLog>(predicate: #Predicate { $0.date == key })
        // Aynı güne birden çok kayıt varsa (eşitleme) her yerde aynı kopya seçilsin (CR-20)
        if let all = try? ctx.fetch(d), !all.isEmpty { return all.count == 1 ? all[0] : all.min { keepOrder($0, $1) } }
        guard create else { return nil }
        let x = DayLog(date: key)
        ctx.insert(x)
        return x
    }

    static func programs(_ ctx: ModelContext, includeArchived: Bool = false) -> [WorkoutProgram] {
        let all = (try? ctx.fetch(FetchDescriptor<WorkoutProgram>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return includeArchived ? all : all.filter { !$0.archived }
    }

    /// Günün programı: o güne özel seçim, yoksa o tarihte geçerli haftalık plan
    static func program(for key: String, profile: UserProfile, ctx: ModelContext) -> WorkoutProgram? {
        let day = Store.day(ctx, key, create: false)
        let id: String?
        if let raw = day?.programIdRaw { id = raw.isEmpty ? nil : raw } else { id = Schedule.programId(profile.schedule, date: key) }
        guard let id else { return nil }
        return programs(ctx, includeArchived: true).first { $0.pid == id }
    }

    /// iCloud eşitlemesi sonrası çift kayıtları kayıpsız birleştirir (CR-01, CR-07, NU-05)
    /// Tekrarlanan günlerde hangisinin kalacağı: cihazdan bağımsız, kimliğe göre
    nonisolated static func keepOrder(_ a: DayLog, _ b: DayLog) -> Bool {
        if a.uid.isEmpty != b.uid.isEmpty { return !a.uid.isEmpty }
        return a.uid < b.uid
    }

    @discardableResult
    static func dedupe(_ ctx: ModelContext) -> Bool {
        var changed = false
        let days = (try? ctx.fetch(FetchDescriptor<DayLog>())) ?? []
        // Eski kayıtlara kimlik ver; kimliği yeni verilen grup bu turda atlanır (diğer cihaz da aynı kimliği görsün diye)
        var fresh = Set<String>()
        for d in days where d.uid.isEmpty { d.uid = UUID().uuidString; fresh.insert(d.date); changed = true }
        for (date, group) in Dictionary(grouping: days, by: \.date) where group.count > 1 && !fresh.contains(date) {
            // Her cihazda aynı kopya kalır (en küçük uid); diğerleri ona eklenip silinir (CR-20)
            let sorted = group.sorted { keepOrder($0, $1) }
            let keep = sorted[0]
            for o in sorted.dropFirst() {
                keep.entries = DayMerge.entries(keep.entries, o.entries)
                keep.sets = DayMerge.sets(keep.sets, o.sets)
                keep.exDone = DayMerge.flags(keep.exDone, o.exDone)
                // İki cihazda ayrı eklenen su kaybolmasın: kopyalar bağımsız oluştuğu için toplanır (CR-28)
                // İkisi de yedekten açıldıysa aynı yedeğin iki cihazdaki aktarımıdır; toplanırsa su ikiye katlanır → büyüğü (CK-11b)
                let imported = keep.uid.hasPrefix("pwa-") && o.uid.hasPrefix("pwa-")
                keep.waterMl = imported ? max(keep.waterMl, o.waterMl) : min(20_000, keep.waterMl + o.waterMl)
                keep.steps = max(keep.steps, o.steps)
                keep.workoutDone = keep.workoutDone || o.workoutDone
                keep.hkSaved = keep.hkSaved || o.hkSaved
                keep.workoutSeconds = max(keep.workoutSeconds, o.workoutSeconds)
                keep.workoutKcal = max(keep.workoutKcal, o.workoutKcal)
                if keep.programIdRaw == nil { keep.programIdRaw = o.programIdRaw }
                ctx.delete(o)
            }
            changed = true
        }
        // Profil: en eski (iCloud'dan gelen asıl) kalır
        let profiles = (try? ctx.fetch(FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        // Silmeden önce boş alanlar yeni cihazdaki profilden tamamlanır (CR-27)
        if profiles.count > 1, let keep = profiles.first {
            // Yeni cihazda iCloud gelmeden değiştirilen ayarlar kaybolmasın: asıl profilde hâlâ varsayılan duran alan,
            // diğer profilde değiştirildiyse oradan alınır (CR-12)
            let def = UserProfile()
            for p in profiles.dropFirst() {
                if keep.activityRaw == def.activityRaw { keep.activityRaw = p.activityRaw }
                if keep.weeklyLossKg == def.weeklyLossKg { keep.weeklyLossKg = p.weeklyLossKg }
                if keep.useMeasuredActivity == def.useMeasuredActivity { keep.useMeasuredActivity = p.useMeasuredActivity }
                if keep.proteinG == def.proteinG { keep.proteinG = p.proteinG }
                if keep.carbsG == def.carbsG { keep.carbsG = p.carbsG }
                if keep.fatG == def.fatG { keep.fatG = p.fatG }
                if keep.waterMl == def.waterMl { keep.waterMl = p.waterMl }
                if keep.waterStepMl == def.waterStepMl { keep.waterStepMl = p.waterStepMl }
                if keep.stepGoal == def.stepGoal { keep.stepGoal = p.stepGoal }
                if keep.mealsRaw == def.mealsRaw { keep.mealsRaw = p.mealsRaw }
                if !keep.fastOn && p.fastOn { keep.fastOn = true; keep.fastData = p.fastData }
                if keep.birthDate == nil { keep.birthDate = p.birthDate }
                if keep.heightCm == nil { keep.heightCm = p.heightCm }
                if keep.sexRaw == nil { keep.sexRaw = p.sexRaw }
                if keep.startKg == nil { keep.startKg = p.startKg }
                if keep.manualKcal == nil { keep.manualKcal = p.manualKcal }
                if keep.goals.isEmpty { keep.goals = p.goals }
                if keep.schedule.isEmpty { keep.schedule = p.schedule }
                if keep.name == "Ben" { keep.name = p.name }
                ctx.delete(p)
            }
            changed = true
        }
        // Aynı pid'li programlar: en çok bloklu (eşitse en eski) kalır, boş alanlar tamamlanır (CK-14)
        let progs = (try? ctx.fetch(FetchDescriptor<WorkoutProgram>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        for (_, g) in Dictionary(grouping: progs, by: \.pid) where g.count > 1 {
            let counts = g.map { $0.blocks.count }
            let i = counts.firstIndex(of: counts.max()!)!
            let keep = g[i]
            for (j, p) in g.enumerated() where j != i {
                if keep.short == nil { keep.short = p.short }
                keep.archived = keep.archived && p.archived
                ctx.delete(p)
            }
            changed = true
        }
        #if os(iOS)
        // Yeni cihazda iCloud gelmeden ilk açılışta eklenen hazır program kopyaları (QA-03):
        // aynı ad + aynı hareket listesi; plana ve hiçbir güne bağlı olmayan kopya silinir. Yalnız hazır şablon adları.
        let tplNames = Set(WkTemplate.all.flatMap { t in t.programs.map { $0.name } })
        let liveProgs = progs.filter { !$0.isDeleted && !$0.archived && tplNames.contains($0.name) }
        if !liveProgs.isEmpty {
            let prof = (try? ctx.fetch(FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])))?.first
            var used = Set((prof?.schedule ?? []).flatMap { $0.days.values.compactMap { $0 } })
            for d in days where !d.isDeleted { if let p = d.programIdRaw { used.insert(p) } }
            for (_, g) in Dictionary(grouping: liveProgs, by: { "\($0.name)|\($0.blocks.allExercises.map { e in e.name }.joined(separator: ","))" }) where g.count > 1 {
                let unused = g.filter { !used.contains($0.pid) }
                for p in unused.prefix(min(unused.count, g.count - 1)) { ctx.delete(p); changed = true }
            }
        }
        #endif
        if dedupeLibrary(ctx) { changed = true }
        if changed { Store.save(ctx) }
        return changed
    }

    /// Besin, tarif, ölçü ve hareket görseli çiftleri (yedeğin iki cihazda aktarılması, eşitleme) (CK-11)
    private static func dedupeLibrary(_ ctx: ModelContext) -> Bool {
        var changed = false
        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        // Besinler: aynı ad → en eski kalır; barkodu çakışanlar ayrı ürün sayılır
        let foods = (try? ctx.fetch(FetchDescriptor<SavedFood>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        for (_, g) in Dictionary(grouping: foods, by: { norm($0.name) }) where g.count > 1 {
            let keep = g[0]
            for o in g.dropFirst() {
                if let a = keep.barcode, let b = o.barcode, a != b { continue }
                if keep.barcode == nil { keep.barcode = o.barcode }
                if keep.imageData == nil, o.imageData != nil { keep.imageData = o.imageData }
                if keep.per100 == .zero { keep.per100 = o.per100 }
                if !o.portions.isEmpty { keep.portions = o.portions.merging(keep.portions) { _, k in k } }
                ctx.delete(o); changed = true
            }
        }
        // Tarifler: aynı ad → en çok malzemeli (eşitse en eski) kalır
        let recipes = (try? ctx.fetch(FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        for (_, g) in Dictionary(grouping: recipes, by: { norm($0.name) }) where g.count > 1 {
            let counts = g.map { $0.items.count }
            let i = counts.firstIndex(of: counts.max()!)!
            for (j, o) in g.enumerated() where j != i { ctx.delete(o) }
            changed = true
        }
        // Ölçüler: aynı an + çelişmeyen değerler → tek kayıt (aynı gün farklı ölçümler korunur)
        // Kimliksiz eski kayıtlara kimlik verilir, o grup bu turda atlanır (DayLog ile aynı yöntem)
        let measures = (try? ctx.fetch(FetchDescriptor<BodyMeasure>())) ?? []
        var freshDates = Set<Date>()
        for m in measures where m.uid.isEmpty { m.uid = UUID().uuidString; freshDates.insert(m.date); changed = true }
        let fields: [ReferenceWritableKeyPath<BodyMeasure, Double?>] = [\.kg, \.waistCm, \.hipCm, \.chestCm, \.rightArmCm, \.leftArmCm, \.thighCm, \.shoulderCm]
        for (date, g) in Dictionary(grouping: measures, by: \.date) where g.count > 1 && !freshDates.contains(date) {
            var kept: [BodyMeasure] = []
            for m in g.sorted(by: { $0.uid < $1.uid }) {
                let fits = kept.first { k in fields.allSatisfy { f in k[keyPath: f] == nil || m[keyPath: f] == nil || k[keyPath: f] == m[keyPath: f] } }
                guard let k = fits else { kept.append(m); continue }
                for f in fields where k[keyPath: f] == nil { k[keyPath: f] = m[keyPath: f] }
                ctx.delete(m); changed = true
            }
        }
        // Hareket görselleri: aynı anahtar → en son güncellenen kalır, eksik kare diğerinden
        let media = (try? ctx.fetch(FetchDescriptor<ExerciseMedia>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        for (_, g) in Dictionary(grouping: media, by: \.key) where g.count > 1 {
            let keep = g[0]
            for o in g.dropFirst() {
                if keep.frame0 == nil { keep.frame0 = o.frame0 }
                if keep.frame1 == nil { keep.frame1 = o.frame1 }
                ctx.delete(o)
            }
            changed = true
        }
        return changed
    }

    /// Son kilo: tüm ölçüleri çekmeden, yalnız en yeni kilolu kayıt (KR-07)
    static func latestWeight(_ ctx: ModelContext) -> Double? {
        var d = FetchDescriptor<BodyMeasure>(predicate: #Predicate { $0.kg != nil }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 1
        let m = (try? ctx.fetch(d))?.first
        latestWeightAt = m?.date
        return m?.kg
    }
    /// Son ölçü kilosunun tarihi; Sağlık'taki daha eski kilo bunun önüne geçmesin (QA-02)
    static var latestWeightAt: Date?
}

/// PWA yedeğini SwiftData'ya aktarır (program üzerine yazılır; gün ve ölçüler birleştirilir) (CK-12)
@MainActor
enum Importer {
    struct Result { var programs = 0, days = 0, foods = 0, recipes = 0, measures = 0 }

    static func run(_ b: PWABackup, ctx: ModelContext) -> Result {
        var r = Result()
        let p = Store.profile(ctx)
        // Varsayılan "Profil" adı kullanıcının adını ezmesin (CK-12)
        let name = b.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && name != "Profil" { p.name = name }
        p.startKg = b.profile.startKg ?? p.startKg
        if let s = b.profile.sex { p.sex = s }
        if !b.targets.goals.isEmpty { p.goals = b.targets.goals }
        p.proteinG = b.targets.p; p.carbsG = b.targets.c; p.fatG = b.targets.f
        // Kalori hedefi aktarılmaz: iOS'ta kilo/boy/aktiviteden hesaplanır (CR-09)
        p.waterMl = b.targets.water; p.waterStepMl = b.targets.waterStep; p.stepGoal = b.targets.steps
        p.meals = b.targets.meals
        if !b.schedule.isEmpty { p.schedule = b.schedule }

        let existing = Dictionary(Store.programs(ctx, includeArchived: true).map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        for x in b.programs {
            let prog = existing[x.id] ?? { let n = WorkoutProgram(pid: x.id, name: x.name); ctx.insert(n); return n }()
            prog.name = x.name; prog.short = x.short; prog.blocks = x.blocks; prog.archived = x.archived
            r.programs += 1
        }
        for d in b.days {
            // Yeni gün "pwa-" önekli kimlikle açılır: iki cihazda aynı yedek aktarılırsa dedupe suyu toplamaz (CK-11b)
            let day = Store.day(ctx, d.date, create: false) ?? { let n = DayLog(date: d.date); n.uid = "pwa-" + n.uid; ctx.insert(n); return n }()
            // Var olan kayıt ezilmez: listeler birleşir, sayılar büyüğü alır (CK-12)
            if case .some(let v) = d.programId { day.programIdRaw = v ?? "" }
            day.workoutDone = day.workoutDone || d.workoutDone
            day.waterMl = max(day.waterMl, d.water); day.steps = max(day.steps, d.steps)
            day.entries = DayMerge.entries(day.entries, d.entries)
            day.sets = DayMerge.sets(day.sets, d.sets)
            day.exDone = DayMerge.flags(day.exDone, d.exDone)
            if let s = d.durationSec { day.workoutSeconds = max(day.workoutSeconds, s) }
            r.days += 1
        }
        // Ölçüler: aynı gün varsa boş alanlar doldurulur, yoksa eklenir; yedek içi tekrarlar da birleşir (CK-10b)
        var byDay: [String: BodyMeasure] = [:]
        for m in (try? ctx.fetch(FetchDescriptor<BodyMeasure>(sortBy: [SortDescriptor(\.date)]))) ?? [] where byDay[DayKey.of(m.date)] == nil {
            byDay[DayKey.of(m.date)] = m
        }
        for m in b.measures where !m.isEmpty {
            guard let date = DayKey.date(m.date) else { continue }
            let key = DayKey.of(date)
            let x = byDay[key] ?? { let n = BodyMeasure(date: date, kg: nil); ctx.insert(n); byDay[key] = n; r.measures += 1; return n }()
            let vals: [(ReferenceWritableKeyPath<BodyMeasure, Double?>, Double?)] = [
                (\.kg, m.kg), (\.waistCm, m.waist), (\.hipCm, m.hip), (\.chestCm, m.chest),
                (\.rightArmCm, m.rightArm), (\.leftArmCm, m.leftArm), (\.thighCm, m.thigh), (\.shoulderCm, m.shoulder)]
            for (k, v) in vals where x[keyPath: k] == nil { x[keyPath: k] = v }
        }
        // Besin/tarif: ad kümesi döngüde güncellenir, yedek içindeki çiftler iki kez eklenmez (CK-11)
        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var foodNames = Set(((try? ctx.fetch(FetchDescriptor<SavedFood>())) ?? []).map { norm($0.name) })
        for f in b.foods where foodNames.insert(norm(f.name)).inserted {
            ctx.insert(SavedFood(name: f.name, per100: f.per100, portions: f.portions, barcode: f.barcode)); r.foods += 1
        }
        var recipeNames = Set(((try? ctx.fetch(FetchDescriptor<Recipe>())) ?? []).map { norm($0.name) })
        for x in b.recipes where recipeNames.insert(norm(x.name)).inserted {
            ctx.insert(Recipe(name: x.name, servings: x.servings, items: x.items.map { RecipeItem(name: $0.name, g: $0.g, per100: $0.per100) })); r.recipes += 1
        }
        Store.save(ctx)
        return r
    }
}

extension Array where Element == DayLog {
    /// O günün kaydı; eşitleme sırasında iki kopya varsa Store.day ile aynı kopya seçilir (CR-20)
    func day(_ date: String) -> DayLog? {
        var best: DayLog?
        for d in self where d.date == date { if best == nil || Store.keepOrder(d, best!) { best = d } }
        return best
    }
}

