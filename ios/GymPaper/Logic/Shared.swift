import SwiftUI
import GymPaperKit

// Contracts shared across screens (Today, Workout, Nutrition, Profile).

/// Sheets that can be opened from any screen
enum AppSheet: Identifiable, Hashable {
    case addFood(date: String, meal: Meal?)   // Beslenme › AddFoodSheet(date:meal:)
    case cheat(date: String)                  // Beslenme › CheatSheet(date:)  "Yazarak gir"
    case measure(quick: Bool)                 // Profil › MeasureSheet(quick:)
    case importProgram(payload: String)       // shared workout link / QR
    case quickLog                             // + next to the tab bar
    case profile                              // Today › profile button
    var id: String {
        switch self {
        case .addFood(let d, let m): "addFood-\(d)-\(m?.rawValue ?? "")"
        case .cheat(let d): "cheat-\(d)"
        case .measure(let q): "measure-\(q)"
        case .importProgram(let p): "import-\(p.count)-\(p.hashValue)"
        case .quickLog: "quickLog"
        case .profile: "profile"
        }
    }
}

/// Set-based workout progress
struct WorkoutProgressInfo: Equatable {
    var done: Int, total: Int
    var complete: Bool
    var pct: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

/// All sets if exDone is marked, otherwise the number of completed sets
func exDoneCount(_ e: Exercise, day: DayLog?) -> Int {
    guard let day else { return 0 }
    if let f = day.exDone[e.id] { return f ? e.sets : 0 }
    return min(e.sets, (day.sets[e.id] ?? []).filter(\.done).count)
}

/// The day's workout volume (kg × reps), only for rep-based exercises.
/// done: completed sets; planned: all sets (entered weight/reps, else the program's).
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


// MARK: - Figma screenshot hooks (DEBUG only, `-shot <key>`)

extension View {
    /// Runs once when the view appears if launched with `-shot key` (figma-shots.command)
    @ViewBuilder func shot(_ keys: String..., delay: Double = 1.5, _ act: @escaping @MainActor () -> Void) -> some View {
        #if DEBUG
        if let s = DemoData.shot, keys.contains(s) {
            self.task { try? await Task.sleep(for: .seconds(delay)); act() }
        } else { self }
        #else
        self
        #endif
    }

    /// Pushes the target screen if launched with `-shot key`
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
