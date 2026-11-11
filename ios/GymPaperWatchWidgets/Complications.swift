import WidgetKit
import SwiftUI
import GymPaperKit

// GYM Paper watch complications: today's workout, calories left, intermittent fasting,
// steps and calorie deficit. On the Nike Globe face: deficit top left, steps bottom left, workout bottom right.
// Corner (accessoryCorner) design follows the Globe face mockup: only the day's workout in the workout corner,
// a calories-left gauge in the nutrition corner (Figma › Apple Watch › Faces).
// Data comes from the WatchSnap the watch app writes to the App Group.

@main
struct GymPaperWatchWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutComplication()
        StepsComplication()
        DeficitComplication()
        NutritionComplication()
        FastComplication()
    }
}

// MARK: - Colors (same as the watch app)

private extension Color {
    static let cInk = Color(red: 0xE5 / 255, green: 0xE5 / 255, blue: 0xE7 / 255)
    static let cDone = Color(red: 0x5F / 255, green: 0xE0 / 255, blue: 0x7A / 255)
    static let cFast = Color(red: 0xA9 / 255, green: 0x7C / 255, blue: 0xFF / 255)
    static let cLime = Color(red: 0xC6 / 255, green: 0xFF / 255, blue: 0x3D / 255)
    static let cBlue = Color(red: 0x40 / 255, green: 0xC8 / 255, blue: 0xFF / 255)
    static let cOrange = Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
    static let cPink = Color(red: 0xFF / 255, green: 0x37 / 255, blue: 0x5F / 255)
}

/// Two-tone rings like Apple's complications on the Modular face
private enum CGrad {
    /// Workout is neutral (off-white); lime is reserved for fasting so they don't mix on the face
    static let workout = Gradient(colors: [.cInk, .cInk])
    static let fast = Gradient(colors: [.cBlue, .cFast])
    static let eat = Gradient(colors: [.cDone, .cLime])
    static let kcal = Gradient(colors: [.cOrange, .cPink])
    static let steps = Gradient(colors: [.cBlue, .cDone])
}

private extension Font {
    /// Bold italic title, heavy italic number (design language)
    static func cTitle(_ s: CGFloat) -> Font { .system(size: s, weight: .bold).italic() }
    static func cNum(_ s: CGFloat) -> Font { .system(size: s, weight: .heavy).italic().monospacedDigit() }
}

// MARK: - Today's workout

struct WorkoutEntry: TimelineEntry {
    let date: Date
    /// nil: the watch app hasn't written today yet
    let snap: WatchSnap?
}

struct WorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutEntry {
        WorkoutEntry(date: .now, snap: WatchSnap(date: DayKey.today, program: "Üst vücut", done: 8, total: 20))
    }
    func getSnapshot(in context: Context, completion: @escaping (WorkoutEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(.now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        // at midnight yesterday's progress isn't shown: the new day starts empty and fills once the app opens
        let midnight = (DayKey.calendar.date(byAdding: .day, value: 1, to: DayKey.calendar.startOfDay(for: .now)) ?? .now.addingTimeInterval(86_400)).addingTimeInterval(1)   // midnight on 23/25-hour days too
        completion(Timeline(entries: [entry(.now), entry(midnight)], policy: .after(midnight)))
    }
    private func entry(_ d: Date) -> WorkoutEntry {
        let s = WatchSnap.load()
        return WorkoutEntry(date: d, snap: s?.date == DayKey.of(d) ? s : nil)
    }
}

struct WorkoutComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch.workout", provider: WorkoutProvider()) { e in
            WorkoutComplicationView(e: e).italic().containerBackground(.clear, for: .widget)   // all text italic
        }
        .configurationDisplayName("Bugünkü antrenman")
        .description("Programın ve tamamlanan setler.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct WorkoutComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let e: WorkoutEntry

    private var rest: Bool { e.snap != nil && e.snap?.program == nil }
    private var done: Bool { e.snap?.workoutDone ?? false }
    private var symbol: String { done ? "checkmark" : rest ? "bed.double.fill" : "dumbbell.fill" }
    private var tint: Color { done ? .cDone : .cInk }
    private var setsText: String {
        guard let s = e.snap, s.program != nil else { return "" }
        return done ? tl("Tamamlandı") : String(localized: "\(s.done)/\(s.total) set")
    }
    private var title: String { e.snap?.program ?? (rest ? tl("Dinlenme günü") : tl("Bugün")) }
    /// Fits the corner arc: one word on a rest day
    private var cornerTitle: String { done ? tl("Tamamlandı") : e.snap?.programShort ?? e.snap?.program ?? (rest ? tl("Dinlenme") : tl("Bugün")) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            // like the open ring on the Modular face: done sets in the middle, icon and total at the ends
            if let s = e.snap, s.program != nil, !done {
                Gauge(value: Double(s.done), in: 0...Double(max(1, s.total))) {
                    Image(systemName: "dumbbell.fill")
                } currentValueLabel: {
                    Text("\(s.done)").font(.cNum(18))
                } minimumValueLabel: {
                    Text(Image(systemName: "dumbbell.fill")).font(.system(size: 8, weight: .bold))
                } maximumValueLabel: {
                    Text("\(s.total)").font(.system(size: 9, weight: .bold))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(CGrad.workout)
                .widgetAccentable()
                .accessibilityLabel("\(title), \(setsText)")
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(done ? Color.cDone : .cInk).widgetAccentable()
                        Text(done ? "Tamam" : rest ? "Dinlen" : "Bugün").font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .accessibilityLabel(rest ? "Dinlenme günü" : done ? "Antrenman tamamlandı" : "Bugünkü antrenman")
            }
        case .accessoryCorner:
            // only the workout name along the corner; "Rest" otherwise
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .widgetAccentable()
                .widgetLabel { Text(cornerTitle) }
        case .accessoryInline:
            if rest || e.snap == nil {
                Label(title, systemImage: symbol)
            } else {
                Label("\(title) · \(setsText)", systemImage: symbol)
            }
        default:
            // large rectangular: colored title on top + sets on the right, program name in the middle, progress at the bottom
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                    Text(done ? "TAMAMLANDI" : rest ? "DİNLENME" : "BUGÜN").font(.system(size: 12, weight: .bold))
                    Spacer(minLength: 4)
                    if let s = e.snap, s.program != nil, !done { Text("\(s.done)/\(s.total) set").font(.system(size: 12, weight: .semibold)).monospacedDigit() }
                }
                .foregroundStyle(done ? Color.cDone : .cInk)
                .widgetAccentable()
                Text(rest ? "Dinlenme günü" : title).font(.cTitle(18)).lineLimit(1).minimumScaleFactor(0.65)
                if let s = e.snap, s.program != nil {
                    Gauge(value: s.progress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(done ? Gradient(colors: [.cDone, .cDone]) : CGrad.workout)
                } else if e.snap == nil {
                    Text("Saatte GYM Paper'ı aç").font(.system(size: 13)).foregroundStyle(.secondary)
                } else {
                    Text("Bugün antrenman yok · toparlan").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Beslenme (kalan kalori)

struct NutritionEntry: TimelineEntry {
    let date: Date
    let target: Double?
    let eaten: Double
}

struct NutritionProvider: TimelineProvider {
    func placeholder(in context: Context) -> NutritionEntry { NutritionEntry(date: .now, target: 1989, eaten: 891) }
    func getSnapshot(in context: Context, completion: @escaping (NutritionEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(.now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionEntry>) -> Void) {
        // eaten resets at midnight; updates when iPhone sends the new value
        let midnight = (DayKey.calendar.date(byAdding: .day, value: 1, to: DayKey.calendar.startOfDay(for: .now)) ?? .now.addingTimeInterval(86_400)).addingTimeInterval(1)   // midnight on 23/25-hour days too
        completion(Timeline(entries: [entry(.now), entry(midnight)], policy: .after(midnight)))
    }
    private func entry(_ d: Date) -> NutritionEntry {
        let s = WatchSnap.load()
        let today = s?.date == DayKey.of(d)
        return NutritionEntry(date: d, target: s?.kcalTarget, eaten: today ? (s?.kcalEaten ?? 0) : 0)
    }
}

struct NutritionComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch.nutrition", provider: NutritionProvider()) { e in
            NutritionComplicationView(e: e).italic().containerBackground(.clear, for: .widget)   // all text italic
        }
        .configurationDisplayName("Kalan kalori")
        .description("Bugün kalan kalori.")
        .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NutritionComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let e: NutritionEntry

    private static func int(_ x: Double) -> String {
        guard x.isFinite, abs(x) < 1e9 else { return "–" }
        return Int(x.rounded()).formatted(.number.locale(.current))
    }

    var body: some View {
        if let target = e.target, target > 0 {
            let left = target - e.eaten
            let over = left < 0
            let leftText = over ? "+" + Self.int(-left) : Self.int(left)
            let eaten = min(max(0, e.eaten), target)
            switch family {
            case .accessoryCorner:
                // icon in the corner; a gauge filling along the edge: calories left at one end, "kcal" at the other
                Image(systemName: "fork.knife").font(.system(size: 18, weight: .semibold))
                    .widgetAccentable()
                    .widgetLabel {
                        Gauge(value: eaten, in: 0...target) {
                            Text("kcal")
                        } currentValueLabel: {
                            Text(leftText)
                        } minimumValueLabel: {
                            Text("kcal")
                        } maximumValueLabel: {
                            Text(leftText)
                        }
                        .tint(over ? .red : .cInk)
                    }
                    .accessibilityLabel(over ? "\(leftText) kalori aşıldı" : "\(leftText) kalori kaldı")
            case .accessoryCircular:
                // open ring: calories left in the middle, fork and knife and "kcal" at the ends
                Gauge(value: eaten, in: 0...target) {
                    Image(systemName: "fork.knife")
                } currentValueLabel: {
                    Text(leftText).font(.cNum(15)).minimumScaleFactor(0.45).lineLimit(1)
                } minimumValueLabel: {
                    Text(Image(systemName: "fork.knife")).font(.system(size: 8, weight: .bold))
                } maximumValueLabel: {
                    Text("kcal").font(.system(size: 8, weight: .bold))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(over ? Gradient(colors: [.red, .red]) : CGrad.kcal)
                .widgetAccentable()
            case .accessoryInline:
                Label(over ? "\(Self.int(-left)) kcal aşıldı" : "\(leftText) kcal kaldı", systemImage: "fork.knife")
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Beslenme", systemImage: "fork.knife").font(.system(size: 13, weight: .semibold)).widgetAccentable()
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(leftText).font(.cNum(22))
                        Text(over ? "kcal aşıldı" : "kcal kaldı").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Gauge(value: eaten, in: 0...target) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).tint(over ? .red : .cInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch family {
            case .accessoryInline: Label("iPhone'da GYM Paper'ı aç", systemImage: "fork.knife")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Beslenme", systemImage: "fork.knife").font(.system(size: 13, weight: .semibold))
                    Text("iPhone'da GYM Paper'ı aç").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default: Image(systemName: "fork.knife").font(.system(size: 18)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Intermittent fasting

struct FastEntry: TimelineEntry {
    let date: Date
    let plan: FastPlan?
}

struct FastProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastEntry { FastEntry(date: .now, plan: nil) }
    func getSnapshot(in context: Context, completion: @escaping (FastEntry) -> Void) {
        completion(FastEntry(date: .now, plan: WatchSnap.load()?.fast))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FastEntry>) -> Void) {
        let plan = WatchSnap.load()?.fast
        var entries = [FastEntry(date: .now, plan: plan)]
        // for the h:mm left in round and corner: once a minute for the next 3 hours
        if plan != nil {
            let start = DayKey.calendar.dateInterval(of: .minute, for: .now)?.start ?? .now
            for i in 1...180 { entries.append(FastEntry(date: start.addingTimeInterval(Double(i) * 60), plan: plan)) }
        }
        // new entries at phase boundaries (fast starts / ends): countdown and color change on their own
        if let plan {
            var t = Date.now
            for _ in 0..<4 {
                let next: Date = {
                    switch plan.phase(at: t) {
                    case let .fasting(_, end, _): return end
                    case let .eating(_, nextFast, _): return nextFast
                    }
                }()
                guard next > t else { break }
                t = next.addingTimeInterval(1)
                entries.append(FastEntry(date: t, plan: plan))
            }
        }
        entries.sort { $0.date < $1.date }
        completion(Timeline(entries: entries, policy: .after(Date.now.addingTimeInterval(3 * 3600))))
    }
}

struct FastComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch.fast", provider: FastProvider()) { e in
            FastComplicationView(e: e).italic().containerBackground(.clear, for: .widget)   // all text italic
        }
        .configurationDisplayName("Aralıklı oruç")
        .description("Oruç ve yeme aralığı için geri sayım.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct FastComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let e: FastEntry
    static func dur(_ s: TimeInterval) -> String {
        let m = Int(s / 60); return m >= 60 ? String(localized: "\(m / 60) saat \(m % 60) dakika") : String(localized: "\(m) dakika")
    }
    /// Time left "5:07" (hours:minutes, rounded up); "42 min" under an hour
    static func hm(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded(.up))
        return m >= 60 ? String(format: "%d:%02d", m / 60, m % 60) : String(localized: "\(m) dk")
    }

    var body: some View {
        if let plan = e.plan {
            let (from, to, fasting): (Date, Date, Bool) = {
                switch plan.phase(at: e.date) {
                case let .fasting(s, end, _): return (s, end, true)
                case let .eating(s, n, _): return (s, n, false)
                }
            }()
            // fasting and eating window use the brand color (lime); the icon tells them apart
            let tint: Color = .cLime
            // hourglass while fasting, fork and knife in the eating window
            let symbol = fasting ? "hourglass" : "fork.knife"
            let range = from...max(to, from.addingTimeInterval(1))
            switch family {
            case .accessoryCircular:
                // small round: the phase's progress ring, icon and time left in the middle (h:mm, refreshed every minute)
                let left = max(0, to.timeIntervalSince(e.date))
                let total = max(1, to.timeIntervalSince(from))
                Gauge(value: min(total, max(0, e.date.timeIntervalSince(from))), in: 0...total) {
                    Image(systemName: symbol)
                } currentValueLabel: {
                    VStack(spacing: -1) {
                        Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                        Text(FastComplicationView.hm(left)).font(.cNum(15)).minimumScaleFactor(0.5).lineLimit(1)
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(tint)
                .widgetAccentable()
                .accessibilityLabel(fasting ? "Oruç bitişine \(FastComplicationView.dur(left))" : "Yeme aralığının bitişine \(FastComplicationView.dur(left))")
            case .accessoryCorner:
                // corner: icon; the phase's progress along the arc, time left at the ends
                let left = max(0, to.timeIntervalSince(e.date))
                let total = max(1, to.timeIntervalSince(from))
                Image(systemName: symbol).font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint).widgetAccentable()
                    .widgetLabel {
                        Gauge(value: min(total, max(0, e.date.timeIntervalSince(from))), in: 0...total) {
                            Text(FastComplicationView.hm(left))
                        } currentValueLabel: {
                            Text(FastComplicationView.hm(left))
                        } minimumValueLabel: {
                            Text(FastComplicationView.hm(left))
                        } maximumValueLabel: {
                            Text(fasting ? "oruç" : "yeme")
                        }
                        .tint(tint)
                    }
                    .accessibilityLabel(fasting ? "Oruç bitişine \(FastComplicationView.dur(left))" : "Yeme aralığının bitişine \(FastComplicationView.dur(left))")
            case .accessoryInline:
                Label {
                    Text(fasting ? "Oruç bitişine " : "Oruca ") + Text(timerInterval: Date.now...max(to, .now), countsDown: true)
                } icon: { Image(systemName: symbol) }
            default:
                // large rectangular: colored title + end time, live countdown, the phase's progress line
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                        Text(fasting ? "ORUÇ · \(plan.label)" : "YEME ARALIĞI").font(.system(size: 12, weight: .bold))
                        Spacer(minLength: 4)
                        Text(fasting ? "bitiş \(to.formatted(date: .omitted, time: .shortened))" : "oruç \(to.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    }
                    .foregroundStyle(tint).widgetAccentable()
                    Text(timerInterval: Date.now...max(to, .now), countsDown: true)
                        .font(.cNum(24)).lineLimit(1).minimumScaleFactor(0.7)
                    ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(Color.cLime)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch family {
            case .accessoryInline: Label("Oruç kapalı", systemImage: "moon.stars")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Aralıklı oruç", systemImage: "moon.stars").font(.system(size: 13, weight: .semibold))
                    Text("iPhone'da Profil › Aralıklı oruç").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default: Image(systemName: "moon.stars").font(.system(size: 18)).foregroundStyle(.secondary)
            }
        }
    }
}


// MARK: - Steps

private func trInt(_ x: Double) -> String {
    guard x.isFinite, abs(x) < 1e9 else { return "–" }
    return Int(x.rounded()).formatted(.number.locale(.current))
}

/// The first instant after midnight (correct on 23/25-hour days too)
private func nextMidnight(_ d: Date = .now) -> Date {
    (DayKey.calendar.date(byAdding: .day, value: 1, to: DayKey.calendar.startOfDay(for: d)) ?? d.addingTimeInterval(86_400)).addingTimeInterval(1)
}

struct StepsEntry: TimelineEntry {
    let date: Date
    let steps: Int?
    let goal: Int
}

struct StepsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StepsEntry { StepsEntry(date: .now, steps: 10663, goal: 10000) }
    func getSnapshot(in context: Context, completion: @escaping (StepsEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(.now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsEntry>) -> Void) {
        // the watch app reads Health in the background and refreshes; starts from zero at midnight
        let mid = nextMidnight()
        completion(Timeline(entries: [entry(.now), StepsEntry(date: mid, steps: 0, goal: entry(.now).goal)], policy: .after(min(mid, .now.addingTimeInterval(30 * 60)))))
    }
    private func entry(_ d: Date) -> StepsEntry {
        let s = WatchSnap.load()
        let today = s?.date == DayKey.of(d)
        return StepsEntry(date: d, steps: s == nil ? nil : (today ? (s?.steps ?? 0) : 0), goal: max(1, s?.stepGoal ?? 10_000))
    }
}

struct StepsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch.steps", provider: StepsProvider()) { e in
            StepsComplicationView(e: e).italic().containerBackground(.clear, for: .widget)   // all text italic
        }
        .configurationDisplayName("Adım")
        .description("Bugünkü adımın ve adım hedefin.")
        .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StepsComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let e: StepsEntry
    var body: some View {
        let n = Double(e.steps ?? 0), goal = Double(e.goal)
        let reached = n >= goal
        let text = e.steps.map { trInt(Double($0)) } ?? "–"
        let tint: Color = reached ? .cDone : .cInk
        switch family {
        case .accessoryCorner:
            // walking icon in the corner; a gauge filling toward the goal along the arc and the step count
            Image(systemName: "figure.walk").font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint).widgetAccentable()
                .widgetLabel {
                    Gauge(value: min(n, goal), in: 0...goal) {
                        Text("adım")
                    } currentValueLabel: {
                        Text(text)
                    } minimumValueLabel: {
                        Text(text)
                    } maximumValueLabel: {
                        Text("")
                    }
                    .tint(tint)
                }
                .accessibilityLabel("\(text) adım, hedef \(trInt(goal))")
        case .accessoryCircular:
            // half-circle gauge on top (fills left to right toward the goal), icon and steps below
            let p = min(1, max(0, n / goal))
            ZStack {
                AccessoryWidgetBackground()
                ZStack {
                    Circle().trim(from: 0, to: 0.5)
                        .stroke(Color.cInk.opacity(0.22), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    Circle().trim(from: 0, to: 0.5 * p)
                        .stroke(reached ? Color.cDone : .cBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .widgetAccentable()
                }
                .rotationEffect(.degrees(180))
                .padding(5)
                VStack(spacing: 0) {
                    Image(systemName: "figure.walk").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(reached ? Color.cDone : .cBlue).widgetAccentable()
                    Text(text).font(.cNum(14)).minimumScaleFactor(0.5).lineLimit(1)
                }
                .padding(.horizontal, 6).offset(y: 4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(text) adım, hedef \(trInt(goal))")
        case .accessoryInline:
            Label("\(text) adım", systemImage: "figure.walk")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label("Adım", systemImage: "figure.walk").font(.system(size: 13, weight: .semibold)).foregroundStyle(tint).widgetAccentable()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(text).font(.cNum(22))
                    Text("/ \(trInt(goal))").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Gauge(value: min(n, goal), in: 0...goal) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).tint(tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Calorie deficit

/// Deficit = burned (basal metabolism for the elapsed part of the day + active calories) − eaten.
/// Basal accrues through the day, so the morning doesn't show a big deficit; it reaches the full day by evening.
struct DeficitEntry: TimelineEntry {
    let date: Date
    let bmr: Double?
    let active: Double
    let eaten: Double
    var burned: Double? {
        guard let bmr, bmr > 0 else { return nil }
        let start = DayKey.calendar.startOfDay(for: date)
        let frac = min(1, max(0, date.timeIntervalSince(start) / 86_400))
        return bmr * frac + active
    }
    var deficit: Double? { burned.map { $0 - eaten } }
}

struct DeficitProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeficitEntry { DeficitEntry(date: .now, bmr: 1850, active: 420, eaten: 1100) }
    func getSnapshot(in context: Context, completion: @escaping (DeficitEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(.now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DeficitEntry>) -> Void) {
        // the basal part grows over time: an entry every half hour until midnight (rebuilt when new data arrives)
        let mid = nextMidnight()
        var entries: [DeficitEntry] = []
        var t = Date.now
        while t < mid && entries.count < 48 { entries.append(entry(t)); t = t.addingTimeInterval(30 * 60) }
        entries.append(entry(mid))
        completion(Timeline(entries: entries, policy: .after(min(mid, .now.addingTimeInterval(60 * 60)))))
    }
    private func entry(_ d: Date) -> DeficitEntry {
        let s = WatchSnap.load()
        let today = s?.date == DayKey.of(d)
        return DeficitEntry(date: d, bmr: s?.kcalBmr, active: today ? (s?.kcalActive ?? 0) : 0, eaten: today ? (s?.kcalEaten ?? 0) : 0)
    }
}

struct DeficitComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch.deficit", provider: DeficitProvider()) { e in
            DeficitComplicationView(e: e).italic().containerBackground(.clear, for: .widget)   // all text italic
        }
        .configurationDisplayName("Kalori açığı")
        .description("Bugün yaktığın ile yediğin arasındaki fark.")
        .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct DeficitComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let e: DeficitEntry
    var body: some View {
        if let d = e.deficit {
            let surplus = d < 0
            let num = trInt(abs(d))
            let word = surplus ? tl("fazla") : tl("açık")
            let tint: Color = surplus ? .red : .cDone
            switch family {
            case .accessoryCorner:
                Image(systemName: "flame.fill").font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint).widgetAccentable()
                    .widgetLabel { Text("\(num) kcal \(word)") }
                    .accessibilityLabel("\(num) kalori \(word)")
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(tint).widgetAccentable()
                    Text((surplus ? "+" : "−") + num).font(.cNum(15)).minimumScaleFactor(0.5).lineLimit(1)
                    Text(word).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
            case .accessoryInline:
                Label("\(num) kcal \(word)", systemImage: "flame.fill")
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Kalori açığı", systemImage: "flame.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(tint).widgetAccentable()
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(num).font(.cNum(22))
                        Text("kcal \(word)").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Text("Yakılan \(trInt(e.burned ?? 0)) · yenen \(trInt(e.eaten))").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch family {
            case .accessoryInline: Label("iPhone'da GYM Paper'ı aç", systemImage: "flame")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Kalori açığı", systemImage: "flame").font(.system(size: 13, weight: .semibold))
                    Text("Profil'de boy, kilo, yaş eksik ya da iPhone'da açılmadı").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default: Image(systemName: "flame").font(.system(size: 18)).foregroundStyle(.secondary)
            }
        }
    }
}
