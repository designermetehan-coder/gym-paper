import SwiftUI
import BalliKit

// Ekranlar arası paylaşılan sözleşmeler (Bugün, Antrenman, Beslenme, Profil hepsi kullanır).

/// Her ekrandan açılabilen sheet'ler (PWA `open(kind, props)`)
enum AppSheet: Identifiable, Hashable {
    case addFood(date: String, meal: Meal?)   // Beslenme › AddFoodSheet(date:meal:)
    case cheat(date: String)                  // Beslenme › CheatSheet(date:)  "Yazarak gir"
    case measure(quick: Bool)                 // Profil › MeasureSheet(quick:)
    case importProgram(payload: String)       // Paylaşılan antrenman bağlantısı / QR
    var id: String {
        switch self {
        case .addFood(let d, let m): "addFood-\(d)-\(m?.rawValue ?? "")"
        case .cheat(let d): "cheat-\(d)"
        case .measure(let q): "measure-\(q)"
        case .importProgram(let p): "import-\(p.count)-\(p.hashValue)"
        }
    }
}

/// PWA `workoutProgress`: set bazında ilerleme
struct WorkoutProgressInfo: Equatable {
    var done: Int, total: Int
    var complete: Bool
    var pct: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

/// PWA `exCount`: exDone işaretliyse tüm setler, değilse tamamlanan set sayısı
func exDoneCount(_ e: Exercise, day: DayLog?) -> Int {
    guard let day else { return 0 }
    if let f = day.exDone[e.id] { return f ? e.sets : 0 }
    return min(e.sets, (day.sets[e.id] ?? []).filter(\.done).count)
}

/// Günün antrenman hacmi (kg × tekrar), yalnız "tekrar" birimli hareketler (2 Kas).
/// done: tamamlanan setler; planned: bütün setler (girilen kilo/tekrar, yoksa programdaki).
func workoutVolume(_ prog: WorkoutProgram, day: DayLog?) -> (done: Double, planned: Double) {
    var done = 0.0, planned = 0.0
    let flags = day?.exDone ?? [:]
    let logs = day?.sets ?? [:]
    for ex in prog.blocks.allExercises where ex.unit == "tekrar" {
        let arr = logs[ex.id] ?? []
        for i in 0..<max(0, ex.sets) {
            let log: SetLog? = i < arr.count ? arr[i] : nil
            let kg = max(0, log?.kg ?? ex.kg ?? 0)
            let reps = (log?.reps ?? 0) > 0 ? log!.reps! : ex.reps
            let v = kg * Double(max(0, reps))
            planned += v
            if flags[ex.id] == true || (log?.done ?? false) { done += v }
        }
    }
    return (done, planned)
}

func workoutProgress(_ prog: WorkoutProgram, day: DayLog?) -> WorkoutProgressInfo {
    let ex = prog.blocks.allExercises
    let total = ex.reduce(0) { $0 + $1.sets }
    let done = ex.reduce(0) { $0 + exDoneCount($1, day: day) }
    return WorkoutProgressInfo(done: done, total: total, complete: (day?.workoutDone ?? false) || (total > 0 && done >= total))
}


// MARK: - Figma ekran görüntüsü kancaları (yalnız DEBUG, `-shot <anahtar>`)

extension View {
    /// `-shot key` ile açılmışsa, görünüm belirince bir kez çalışır (figma-shots.command)
    @ViewBuilder func shot(_ keys: String..., delay: Double = 1.5, _ act: @escaping @MainActor () -> Void) -> some View {
        #if DEBUG
        if let s = DemoData.shot, keys.contains(s) {
            self.task { try? await Task.sleep(for: .seconds(delay)); act() }
        } else { self }
        #else
        self
        #endif
    }

    /// `-shot key` ile açılmışsa hedef ekranı iter
    @ViewBuilder func shotPush<D: View>(_ key: String, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        #if DEBUG
        if DemoData.shot == key { modifier(ShotPush(dest: dest)) } else { self }
        #else
        self
        #endif
    }
}

#if DEBUG
private struct ShotPush<D: View>: ViewModifier {
    let dest: () -> D
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: $on) { dest() }
            .task { try? await Task.sleep(for: .seconds(1.2)); on = true }
    }
}
#endif
