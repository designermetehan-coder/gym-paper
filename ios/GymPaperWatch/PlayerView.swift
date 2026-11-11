import SwiftUI
import SwiftData
import WatchKit
import GymPaperKit

/// Workout player — the watch version of the iPhone player:
/// exercise visual, set bar, last set and suggestion, weight (Digital Crown), reps/sets, previous · pause · complete,
/// rest ring, workout order, pause and finish summary.
struct PlayerView: View {
    let pid: String
    let date: String
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchWorkout.self) private var wk
    @Query private var programs: [WorkoutProgram]
    @Query private var days: [DayLog]
    @State private var idx = -1
    /// Weight and reps live in a separately observed object: each Digital Crown step redraws only the dial, not the whole player
    @State private var input = WInput()
    @Environment(\.isLuminanceReduced) private var dimmed
    @State private var restEnd: Date?
    @State private var restTotal: Double = 60
    @State private var restLeft: Double?          // remaining time when rest is paused
    @State private var timerEnd: Date?             // timed exercise (s)
    @State private var timerTotal: Double = 30
    @State private var paused = false
    @State private var finished = false
    @State private var saving = false
    @State private var showMore = false
    /// Machine taken: exercises moved to the end (same as iPhone)
    @State private var later: Set<String> = []
    @FocusState private var focus: WField?
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var flagTick = 0
    /// Set → rest → next set: screens change with a horizontal push
    private var push: AnyTransition { reduce ? .opacity : .push(from: .trailing) }
    private let flow = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.35)

    /// DEBUG screenshot mode only: "rest" | "paused" | "summary" (WatchShots)
    var shot: String? = nil

    init(pid: String, date: String, shot: String? = nil) {
        self.pid = pid; self.date = date; self.shot = shot
        // the day copy ("program@day") is queried too: a machine-taken swap affects today only
        let copy = ExerciseAlternatives.dayCopyPid(pid, date: date)
        _programs = Query(filter: #Predicate<WorkoutProgram> { $0.pid == pid || $0.pid == copy })
        _days = Query(filter: #Predicate<DayLog> { $0.date == date })
    }

    private var prog: WorkoutProgram? {
        let copy = ExerciseAlternatives.dayCopyPid(pid, date: date)
        return programs.first { $0.pid == copy } ?? programs.first
    }
    /// Alet dolu → alternatifler (P-03)
    @State private var altFor: WStep?
    private var day: DayLog? { days.day(date) }

    var body: some View {
        Group {
            if let prog {
                let steps = WLogic.steps(prog)
                if steps.isEmpty {
                    Text("Bu programda hareket yok").foregroundStyle(.secondary)
                } else if finished {
                    summary(prog, steps: steps, finished: true)
                } else if restEnd != nil || restLeft != nil {
                    // pausing doesn't open the summary; stays on the player/rest screen
                    restView(next: idx >= 0 && idx < steps.count ? steps[idx] : nil, steps: steps)
                        .transition(push)
                } else if idx >= 0 && idx < steps.count {
                    stepPage(steps[idx], steps: steps)
                        .transition(push)
                } else {
                    ProgressView()
                }
            } else {
                Text("Program bulunamadı").foregroundStyle(.secondary)
            }
        }
        // program name in the title, in the brand color
        .navigationTitle { Text(prog?.name ?? "").foregroundStyle(Color.wAction) }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            start()
            // continue from a newer state on iPhone (last 4 hours)
            if shot == nil, let r = LiveBridge.shared.remote, r.at > Date().addingTimeInterval(-4 * 3600) { applyRemote(r) }
            publishLive()
        }
        // two-way sync: every change here goes to iPhone, and iPhone's comes here
        .onChange(of: idx) { publishLive() }
        .onChange(of: paused) { publishLive() }
        .onChange(of: restEnd) { publishLive() }
        .onChange(of: restLeft) { publishLive() }
        .onChange(of: finished) { publishLive() }
        .onChange(of: later) { publishLive() }
        .onChange(of: input.kg) { publishLive() }
        .onChange(of: input.reps) { publishLive() }
        .onChange(of: LiveBridge.shared.remote) { _, r in applyRemote(r) }
        // rest: 3 light ticks in the last 3 seconds, a strong haptic at zero (works with the screen off thanks to the workout session)
        .task(id: restEnd) {
            guard let end = restEnd else { return }
            for mark in [3.0, 2.0, 1.0] {
                let wait = end.timeIntervalSinceNow - mark
                if wait < -0.4 { continue }
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, restEnd == end else { return }
                WKInterfaceDevice.current().play(.click)
            }
            let left = end.timeIntervalSinceNow
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            guard !Task.isCancelled, restEnd == end else { return }
            WKInterfaceDevice.current().play(.notification)
            withAnimation(flow) { restEnd = nil }
        }
        .task(id: timerEnd) {
            guard let end = timerEnd else { return }
            let left = end.timeIntervalSinceNow
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            guard !Task.isCancelled, timerEnd == end else { return }
            WKInterfaceDevice.current().play(.stop)
            timerEnd = nil
        }
    }

    // MARK: Player

    @ViewBuilder private func stepPage(_ s: WStep, steps: [WStep]) -> some View {
        let next = nextIdx(steps)
        let upcoming = next.map { steps[$0] }
        let sug = PhoneSync.shared.sugKg[s.ex.id]
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    statusRow(steps)
                    // square exercise visual on the left, name and muscle · set on the right
                    HStack(spacing: 10) {
                        cover(s.ex.name)
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            // pausing shrinks and stops it like on iPhone; resuming restores it
                            .scaleEffect(paused ? 0.8 : 1)
                            .opacity(paused ? 0.7 : 1)
                            .animation(reduce ? nil : .spring(response: 0.5, dampingFraction: 0.72), value: paused)
                        // exercise name only: set info is in the Set box; long names wrap up to 3 lines
                        Text(s.ex.name).font(.system(size: 13, weight: .bold).italic()).lineLimit(3).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                        // ••• next to the name: machine taken, skip to next, finish
                        Button { showMore = true } label: {
                            Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.wInk)
                                .frame(width: 28, height: 28).background(.white.opacity(0.15), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Diğer")
                    }

                    // inputs: Weight · Reps · Set (the selected box changes with the Digital Crown)
                    if s.ex.unit == "tekrar" {
                        HStack(spacing: 6) {
                            WCrownTile(label: "Ağırlık", value: $input.kg, text: input.kg > 0 ? input.kg.kgText : "–", range: 0...500, step: 1.25,
                                       field: .kg, focus: $focus, highlight: (sug ?? 0) > 0 && input.kg == sug)
                            WCrownTile(label: "Tekrar", value: Binding(get: { Double(input.reps) }, set: { input.reps = max(1, Int($0)) }),
                                       text: "\(input.reps)", range: 1...100, step: 1, field: .reps, focus: $focus)
                            tile("Set", "\(s.si + 1)/\(s.of)")
                        }
                    } else if s.ex.unit == "sn" {
                        if let end = timerEnd {
                            ring(end: end, total: timerTotal, size: 76)
                        } else {
                            HStack(spacing: 6) {
                                Button {
                                    timerTotal = Double(max(1, s.ex.reps)); timerEnd = Date().addingTimeInterval(timerTotal)
                                    WKInterfaceDevice.current().play(.start)
                                } label: {
                                    VStack(spacing: 0) {
                                        Text("Süre").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                                        Label(Self.mmss(s.ex.reps), systemImage: "timer").font(.system(size: 16, weight: .heavy).italic().monospacedDigit())
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                }
                                .buttonStyle(.plain)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .accessibilityLabel("Süreyi başlat")
                                tile("Set", "\(s.si + 1)/\(s.of)")
                            }
                        }
                    } else {
                        Text("\(s.ex.reps) dakika · bitirince işaretle").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }

                    if let prog { queueInline(prog, steps: steps, current: s).id("queue") }
                    Color.clear.frame(height: 52)
                }
                .scenePadding(.horizontal)   // keep off the edges (watchOS margins)
            }
        }
        // progressive blur behind the bottom controls: content fades softly under the bar
        .overlay {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(stops: [.init(color: .black.opacity(0), location: 0),
                                       .init(color: .black.opacity(0.9), location: 0.4),
                                       .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 64)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        // bottom controls: previous · pause/resume · next (complete the set, go on) — wide horizontal capsules
        .overlay(alignment: .bottom) {
            HStack(spacing: 8) {
                barButton("backward.end.fill", label: "Önceki set", disabled: idx <= 0) {
                    idx = max(0, idx - 1); timerEnd = nil; load(steps[idx])
                }
                barButton(paused ? "play.fill" : "pause.fill", label: paused ? "Devam et" : "Duraklat") {
                    paused ? resume() : pause()
                }
                barButton(upcoming == nil ? "checkmark" : "forward.end.fill", label: upcoming == nil ? "Son seti tamamla" : "Seti tamamla, sonrakine geç", primary: true) {
                    withAnimation(flow) { complete(s, steps: steps) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .background(alignment: .bottom) {
                LinearGradient(stops: [.init(color: .black.opacity(0), location: 0), .init(color: .black, location: 0.45)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .tint(Color.wMuted)
        .confirmationDialog(s.ex.name, isPresented: $showMore, titleVisibility: .hidden) {
            Button("Alet dolu") { altFor = s }
            if upcoming != nil { Button("Sıradakine geç") { skip(steps) } }
            Button("Antrenmanı bitir", role: .destructive) { restEnd = nil; restLeft = nil; timerEnd = nil; withAnimation(flow) { finished = true } }
            Button("Vazgeç", role: .cancel) {}
        }
        .sheet(item: $altFor) { t in altSheet(t, steps: steps) }
    }

    /// Machine taken: first 3 alternatives for the same area + move to end; the choice goes to iPhone too
    @ViewBuilder private func altSheet(_ t: WStep, steps: [WStep]) -> some View {
        let exclude = Set(prog?.blocks.allExercises.map { TextNorm.norm($0.name) } ?? [])
        let alts = ExerciseAlternatives.rank(current: t.ex.name, muscle: t.ex.muscle, unit: t.ex.unit, library: WAltLib.all, exclude: exclude, limit: 3)
        List {
            Section {
                ForEach(alts, id: \.name) { c in
                    Button { swap(t, to: c, steps: steps) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.headline).lineLimit(2)
                            Text(c.alias ?? c.muscle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            } header: { Text("Alternatifler") }
            if steps.contains(where: { $0.ex.id != t.ex.id && !WLogic.isDone($0, day) }) {
                Button("Sona bırak") { altFor = nil; postpone(t, steps: steps) }
            }
        }
        .navigationTitle("Alet dolu")
    }

    private func swap(_ t: WStep, to c: ExerciseAlternatives.Candidate, steps: [WStep]) {
        guard let prog else { return }
        let done = steps.filter { $0.ex.id == t.ex.id && WLogic.isDone($0, day) }.count
        let basePid = pid
        Store.swapForDay(ctx, date: date, pid: basePid, eid: t.ex.id, doneSets: done, to: c.name, muscle: c.muscle)
        try? ctx.save()
        PhoneSync.shared.send(WatchEvent(kind: "swap", date: date, eid: t.ex.id, si: done, pid: prog.pid, name: c.name, muscle: c.muscle))
        altFor = nil
        let newId = ExerciseAlternatives.swappedId(t.ex.id, name: c.name)
        // switch to the new exercise when the program query refreshes
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard let p = self.prog else { return }
            let st = WLogic.steps(p)
            if let j = st.firstIndex(where: { $0.ex.id == newId && !WLogic.isDone($0, day) }) {
                withAnimation(flow) { restEnd = nil; restLeft = nil; timerEnd = nil; idx = j; load(st[j]) }
            }
        }
        WKInterfaceDevice.current().play(.success)
    }

    /// Workout order below the player: block by block, done ones with a green check
    @ViewBuilder private func queueInline(_ prog: WorkoutProgram, steps: [WStep], current s: WStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(prog.blocks.enumerated()), id: \.element.id) { i, b in
                Text(b.kind == .superset ? (b.tag == "warm" ? String(localized: "Isınma · \(b.rounds) tur") : b.tag == "cool" ? String(localized: "Soğuma · \(b.rounds) tur") : String(localized: "Süperset · \(b.rounds) tur")) : "#\(i + 1)")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.top, 6).padding(.leading, 4)
                ForEach(b.exercises, id: \.id) { e in
                    queueRow(e, rounds: b.kind == .superset ? b.rounds : nil, steps: steps, current: s)
                }
            }
        }
    }

    private func queueRow(_ e: Exercise, rounds: Int?, steps: [WStep], current s: WStep) -> some View {
        let mine = steps.indices.filter { steps[$0].ex.id == e.id }
        let doneN = mine.filter { WLogic.isDone(steps[$0], day) }.count
        let all = !mine.isEmpty && doneN == mine.count
        let now = e.id == s.ex.id
        let kg = PhoneSync.shared.lastKg[e.id] ?? e.kg
        let sets = rounds ?? e.sets
        return Button {
            if let j = mine.first(where: { !WLogic.isDone(steps[$0], day) }) ?? mine.first {
                withAnimation(flow) { idx = j; timerEnd = nil; restEnd = nil; restLeft = nil; load(steps[j]) }
                WKInterfaceDevice.current().play(.click)
            }
        } label: {
            HStack(spacing: 10) {
                thumb(e.name).opacity(all && !now ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.name).font(.system(size: 15, weight: .medium)).lineLimit(2).foregroundStyle(now ? Color.wAction : .primary)
                    Text("\(sets) × \(e.reps)\(e.unit == "tekrar" ? "" : " " + tl(e.unit))\(kg.map { $0 > 0 ? " · \($0.kgText) kg" : "" } ?? "")")
                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 0)
                if all { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.wDone).accessibilityLabel("Tamamlandı") }
                else if doneN > 0 { Text("\(doneN)/\(mine.count)").font(.caption2).foregroundStyle(Color.wInk) }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ s: WStep) -> String {
        let m = s.ex.muscle.trimmingCharacters(in: .whitespaces)
        var t = m.isEmpty ? String(localized: "\(s.label) · Set \(s.si + 1)/\(s.of)") : String(localized: "\(tl(m)) · Set \(s.si + 1)/\(s.of)")
        if s.ss { t += s.tag == "warm" ? tl(" · Isınma") : s.tag == "cool" ? tl(" · Soğuma") : tl(" · Süperset") }
        return t
    }

    private func statusRow(_ steps: [WStep]) -> some View {
        HStack(spacing: 4) {
            if paused {
                Image(systemName: "pause.fill").foregroundStyle(Color.wAction)
                Text("Duraklatıldı").foregroundStyle(Color.wAction)
            } else if wk.running || shot != nil {
                // sample heart rate in screenshot mode
                let hr = shot != nil ? 128 : wk.heartRate
                Image(systemName: "heart.fill").foregroundStyle(Color.wHeart)
                Text(hr > 0 ? "\(Int(hr))" : "–").fontWeight(.heavy).italic()   // heart rate
            }
            Spacer(minLength: 0)
            let n = steps.filter { WLogic.isDone($0, day) }.count
            Text("\(n)/\(steps.count)").foregroundStyle(Color.wInk)
                .contentTransition(.numericText(value: Double(n)))
                .keyframeAnimator(initialValue: 1.0, trigger: n) { v, k in v.scaleEffect(k) } keyframes: { _ in
                    CubicKeyframe(reduce ? 1.0 : 1.1, duration: 0.1)
                    SpringKeyframe(1.0, duration: 0.25)
                }
        }
        .font(.system(size: 13, weight: .semibold)).monospacedDigit()
    }

    @ViewBuilder private func cover(_ name: String) -> some View {
        let f = WMotion.frames(name)
        Group {
            if f.isEmpty {
                RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.1))
                    .overlay(Image(systemName: "dumbbell.fill").font(.system(size: 24)).foregroundStyle(.secondary))
            } else {
                WFramePlayer(frames: f, paused: dimmed || paused)
            }
        }
        .id(name)
    }

    /// Bottom bar button: wide gray capsule
    private func barButton(_ symbol: String, label: String, disabled: Bool = false, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            action(); WKInterfaceDevice.current().play(.click)
        } label: {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.wInk)
                .opacity(disabled ? 0.35 : 1)
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color(red: 0.165, green: 0.165, blue: 0.165), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(tl(label))
        .modifier(WPrimaryGesture(on: primary))
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(tl(label)).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .heavy).italic().monospacedDigit()).lineLimit(1)   // SF Pro, fixed-width digits
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action(); WKInterfaceDevice.current().play(.click)
        } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).frame(width: 38, height: 38)   // larger touch target
        }
        .buttonStyle(.bordered).buttonBorderShape(.circle)
        .accessibilityLabel(tl(label))
    }

    // MARK: Dinlenme

    private func restView(next: WStep?, steps: [WStep]) -> some View {
        ScrollView {
            VStack(spacing: 6) {
                statusRow(steps)
                if let end = restEnd {
                    ring(end: end, total: restTotal, size: 74)
                } else if let l = restLeft {
                    ring(end: Date().addingTimeInterval(l), total: restTotal, size: 74, frozen: l)
                }
                if let next {
                    VStack(spacing: 0) {
                        Text(next.ex.name).font(.system(size: 15, weight: .bold).italic()).multilineTextAlignment(.center).lineLimit(2)
                        Text(subtitle(next)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                // +15 · Skip; Resume instead of +15 when paused
                HStack(spacing: 8) {
                    if paused {
                        Button { resume() } label: {
                            Image(systemName: "play.fill").frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .accessibilityLabel("Devam et")
                        .buttonStyle(.bordered).tint(Color.wInk).foregroundStyle(Color.wInk)
                    } else {
                        Button {
                            restTotal += 15
                            if let e = restEnd { restEnd = e.addingTimeInterval(15) } else if let l = restLeft { restLeft = l + 15 }
                            WKInterfaceDevice.current().play(.click)
                        } label: {
                            Text("+15").font(.body.weight(.bold)).frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .accessibilityLabel("15 saniye ekle")
                        .buttonStyle(.bordered).tint(Color.wInk).foregroundStyle(Color.wInk)
                    }
                    Button { withAnimation(flow) { restEnd = nil; restLeft = nil } } label: {
                        Text("Atla").font(.body.weight(.bold)).foregroundStyle(Color.wOnAction).frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.wAction)
                }
            }
            .scenePadding(.horizontal)   // keep off the edges (watchOS margins)
        }
    }

    @ViewBuilder private func ring(end: Date, total: Double, size: CGFloat, frozen: Double? = nil) -> some View {
        if dimmed && frozen == nil {
            aodRing(end: end, total: total, size: size)
        } else {
            liveRing(end: end, total: total, size: size, frozen: frozen)
        }
    }

    /// Always On: .animation timing stops when the wrist drops. The system draws the digits (Text(timerInterval:)),
    /// the ring advances with .periodic at a one-second cadence; no pulse or orange.
    private func aodRing(end: Date, total: Double, size: CGFloat) -> some View {
        TimelineView(.periodic(from: end.addingTimeInterval(-total.rounded(.up)), by: 1)) { t in
            let left = max(0, end.timeIntervalSince(t.date))
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 6)
                Circle().trim(from: 0, to: min(1, left / max(1, total)))
                    .stroke(Color.wInk, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                    .font(.system(size: size * 0.28, weight: .heavy).italic().monospacedDigit())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .frame(width: size * 0.8)
            }
            .frame(width: size, height: size)
        }
    }

    private func liveRing(end: Date, total: Double, size: CGFloat, frozen: Double?) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10, paused: frozen != nil)) { t in
            let left = max(0, frozen ?? end.timeIntervalSince(t.date))
            // last 3 seconds: orange with a light pulse at the start of each second
            let hot = left > 0 && left <= 3
            let beat = hot && !reduce ? 1 + 0.05 * max(0, sin(.pi * 2 * (left.rounded(.up) - left))) : 1
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 6)
                Circle().trim(from: 0, to: min(1, left / max(1, total)))
                    .stroke(hot ? Color.orange : Color.wInk, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Self.mmss(Int(left.rounded(.up))))
                    .font(.system(size: size * 0.28, weight: .heavy).italic().monospacedDigit())   // SF Pro, fixed-width digits
                    .foregroundStyle(hot ? Color.orange : .primary)
            }
            .frame(width: size, height: size)
            .scaleEffect(beat)
        }
    }

    // MARK: Workout order

    private func thumb(_ name: String) -> some View {
        let f = WMotion.thumb(name).map { [$0] } ?? []
        return Group {
            if let i = f.first { Image(uiImage: i).resizable().scaledToFill() }
            else { Image(systemName: "dumbbell.fill").foregroundStyle(.secondary) }
        }
        .frame(width: 34, height: 34)
        .background(.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }


    // MARK: Pause / finish summary

    @ViewBuilder private func summary(_ prog: WorkoutProgram, steps: [WStep], finished: Bool) -> some View {
        let done = steps.filter { WLogic.isDone($0, day) }
        let logs: [(WStep, SetLog)] = done.compactMap { st in
            guard let a = day?.sets[st.ex.id], st.si < a.count else { return nil }
            return (st, a[st.si])
        }
        let volume = logs.reduce(0.0) { a, x in x.0.ex.unit == "tekrar" ? a + (x.1.kg ?? 0) * Double(x.1.reps ?? x.0.ex.reps) : a }
        let reps = logs.reduce(0) { a, x in x.0.ex.unit == "tekrar" ? a + (x.1.reps ?? x.0.ex.reps) : a }
        let exDone = Set(done.map(\.ex.id)).count
        let exTotal = Set(steps.map(\.ex.id)).count
        let top = logs.compactMap { x -> (String, Double)? in (x.1.kg ?? 0) > 0 ? (x.0.ex.name, x.1.kg!) : nil }.max { $0.1 < $1.1 }
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: finished ? (done.count == steps.count ? "checkmark.seal.fill" : "flag.checkered") : "pause.circle.fill")
                        .foregroundStyle(finished ? Color.wDone : Color.wInk)
                        .symbolEffect(.bounce, value: flagTick)
                        .onAppear { if finished && !reduce { flagTick += 1 } }
                    Text(finished ? (done.count == steps.count ? "Antrenman bitti" : "Antrenmanı bitir") : "Duraklatıldı").font(.headline.weight(.bold).italic())
                }
                // rows slide in from the left 60 ms apart
                Group {
                    row("Süre", Self.mmss(Int(shot != nil ? 1712 : wk.elapsed))).modifier(WRowIn(index: 0))
                    row("Tamamlanan set", "\(done.count) / \(steps.count)").modifier(WRowIn(index: 1))
                    row("Hareket", "\(exDone) / \(exTotal)").modifier(WRowIn(index: 2))
                    row("Toplam tekrar", "\(reps)").modifier(WRowIn(index: 3))
                    row("Hacim", String(localized: "\(Int(volume.rounded())) kg")).modifier(WRowIn(index: 4))
                    if wk.kcal > 0 { row("Kalori", String(localized: "\(Int(wk.kcal)) kcal")).modifier(WRowIn(index: 5)) }
                    if let top { rowStacked("En ağır set", String(localized: "\(top.0) · \(top.1.kgText) kg")).modifier(WRowIn(index: 6)) }
                }
                if finished {
                    Button { save(prog) } label: {
                        Label("Kaydet ve kapat", systemImage: "square.and.arrow.down").font(.body.weight(.bold).italic())
                            .foregroundStyle(Color.wOnAction).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.wAction).disabled(saving)
                    if done.count < steps.count {
                        Button("Devam et") { self.finished = false; if paused { resume() } }
                    }
                } else {
                    Button {
                        paused = false; wk.resume()
                        if let l = restLeft { restEnd = Date().addingTimeInterval(l); restLeft = nil }
                    } label: {
                        Label("Devam et", systemImage: "play.fill").font(.body.weight(.bold).italic())
                            .foregroundStyle(Color.wOnAction).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.wAction)
                    Button("Antrenmanı bitir") { restEnd = nil; restLeft = nil; timerEnd = nil; self.finished = true }
                }
            }
            .scenePadding(.horizontal)   // keep off the edges (watchOS margins)
        }
    }

    /// Long value: below the label, full width (no truncation)
    private func rowStacked(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(tl(k)).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.system(size: 15, weight: .heavy).italic().monospacedDigit()).lineLimit(2).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(tl(k)).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(v).font(.system(size: 15, weight: .heavy).italic().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)   // summary numbers
        }
        .padding(.vertical, 2)
    }

    // MARK: Flow

    private func start() {
        guard idx < 0, let prog else { return }
        let steps = WLogic.steps(prog)
        guard !steps.isEmpty else { return }
        if let first = steps.firstIndex(where: { !WLogic.isDone($0, day) }) {
            idx = first; load(steps[first])
        } else {
            idx = steps.count - 1; finished = true
        }
        #if DEBUG
        if let shot {
            switch shot {
            case "rest": restTotal = 90; restEnd = Date().addingTimeInterval(64)
            case "paused": paused = true
            case "summary": finished = true
            case "tour":
                // cover video: complete the set after 2.4 s → rest starts
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.4))
                    let st = WLogic.steps(prog)
                    if idx >= 0, idx < st.count { complete(st[idx], steps: st) }
                }
            default: break
            }
            return   // no workout session / Health prompt in screenshots
        }
        #endif
        if !(day?.workoutDone ?? false) && !finished && !wk.running {
            // if another program was picked on the watch it becomes today's workout; iPhone is told too
            if date == DayKey.today { PhoneSync.shared.pick(ctx, date: date, pid: pid) }
            WKInterfaceDevice.current().play(.start)   // make the start felt on the wrist
            Task { await wk.start(owner: date + pid) }
        }
    }

    /// Next step not done (wraps around to skipped ones at the end)
    private func nextIdx(_ steps: [WStep]) -> Int? {
        guard idx >= 0 else { return nil }
        let order = Array(steps.indices.dropFirst(idx + 1)) + Array(steps.indices.prefix(idx))
        // exercises not moved to the end first; then back to the ones that were
        return order.first { !WLogic.isDone(steps[$0], day) && !later.contains(steps[$0].ex.id) }
            ?? order.first { !WLogic.isDone(steps[$0], day) }
    }

    /// Machine taken: moves the exercise to the end and goes to the next different exercise (same as iPhone)
    private func postpone(_ s: WStep, steps: [WStep]) {
        later.insert(s.ex.id)
        if let j = steps.indices.first(where: { steps[$0].ex.id != s.ex.id && !WLogic.isDone(steps[$0], day) && !later.contains(steps[$0].ex.id) })
            ?? steps.indices.first(where: { steps[$0].ex.id != s.ex.id && !WLogic.isDone(steps[$0], day) }) {
            withAnimation(flow) { restEnd = nil; restLeft = nil; timerEnd = nil; idx = j; load(steps[j]) }
        }
        WKInterfaceDevice.current().play(.click)
    }

    /// Skip to next: go on without saving this set
    private func skip(_ steps: [WStep]) {
        guard let n = nextIdx(steps) else { return }
        withAnimation(flow) { restEnd = nil; restLeft = nil; timerEnd = nil; idx = n; load(steps[n]) }
        WKInterfaceDevice.current().play(.click)
    }

    /// Pause: the animation shrinks and stops, the rest timer freezes; no summary
    private func pause() {
        guard !paused else { return }
        withAnimation { paused = true }
        wk.pause()
        if let e = restEnd { restLeft = max(0, e.timeIntervalSinceNow); restEnd = nil }
        timerEnd = nil   // a timed set stops; it restarts on resume
        WKInterfaceDevice.current().play(.stop)
    }
    private func resume() {
        guard paused else { return }
        withAnimation { paused = false }
        wk.resume()
        if let l = restLeft { restEnd = Date().addingTimeInterval(l); restLeft = nil }
        WKInterfaceDevice.current().play(.start)
    }

    /// Live state (same format as iPhone; duration 0 without rest)
    private func liveState() -> LiveState? {
        guard let prog, idx >= 0 else { return nil }
        let steps = WLogic.steps(prog)
        let key = idx < steps.count ? steps[idx].key : nil
        let resting = restEnd != nil || restLeft != nil
        return LiveState(date: date, pid: pid, key: key, paused: paused, restEnd: restEnd, restLeft: restEnd == nil ? restLeft : nil,
                         restTotal: resting ? restTotal : 0, kg: input.kg, reps: input.reps, later: Array(later), finished: finished)
    }
    /// Live state to iPhone
    private func publishLive() {
        guard shot == nil, let s = liveState() else { return }
        LiveBridge.shared.publish(s)
    }

    /// State from iPhone: step, pause, rest, weight/reps, machine taken
    private func applyRemote(_ r: LiveState?) {
        guard shot == nil, let r, r.date == date, r.pid == pid, let prog else { return }
        let steps = WLogic.steps(prog)
        later = Set(r.later)
        if r.paused != paused { if r.paused { withAnimation { paused = true }; wk.pause() } else { withAnimation { paused = false }; wk.resume() } }
        if let k = r.key, let j = steps.firstIndex(where: { $0.key == k }), j != idx {
            withAnimation(flow) { idx = j; timerEnd = nil; load(steps[j]) }
        }
        input.kg = r.kg
        if r.reps > 0 { input.reps = r.reps }
        if r.restTotal > 0 { restTotal = r.restTotal }
        withAnimation(flow) { restEnd = r.restEnd; restLeft = r.restEnd == nil ? r.restLeft : nil }
        if r.finished && !finished { timerEnd = nil; restEnd = nil; restLeft = nil; withAnimation(flow) { finished = true } }
        else if !r.finished && finished && !(day?.workoutDone ?? false) { withAnimation(flow) { finished = false } }
        // applied state isn't sent back (no echo loop)
        if let s = liveState() { LiveBridge.shared.settle(s) }
    }

    private func load(_ s: WStep) {
        input.kg = WLogic.suggestedKg(ctx, s, date: date, day: day)
        input.reps = WLogic.suggestedReps(s, day: day)
    }

    private func complete(_ s: WStep, steps: [WStep]) {
        if paused { resume() }
        WLogic.mark(ctx, date: date, pid: pid, step: s, kg: input.kg, reps: input.reps)
        WKInterfaceDevice.current().play(.success)
        timerEnd = nil
        guard let n = nextIdx(steps) else {
            finished = true
            return
        }
        let keepKg = input.kg
        idx = n
        load(steps[n])
        if steps[n].ex.id == s.ex.id, keepKg > 0 { input.kg = keepKg }
        if s.rest > 0 { restTotal = Double(s.rest); restEnd = Date().addingTimeInterval(restTotal); restLeft = nil }
    }

    private func save(_ prog: WorkoutProgram) {
        saving = true
        Task {
            let r = wk.running ? await wk.finish() : nil
            WLogic.complete(ctx, date: date, prog: prog, seconds: r?.seconds, kcal: r?.kcal)
            WKInterfaceDevice.current().play(.success)
            saving = false
            dismiss()
        }
    }

    static func mmss(_ s: Int) -> String { String(format: "%d:%02d", max(0, s) / 60, max(0, s) % 60) }
}

/// Summary row: slides in 10 pt from the left while fading on first appearance, 60 ms per row
struct WRowIn: ViewModifier {
    var index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(x: shown || reduce ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.35).delay(0.15 + Double(index) * 0.06)) { shown = true }
            }
    }
}

/// Alternates two frames with a soft crossfade (the iPhone exercise animation)
/// MoveKit visuals on black: inverted colors, hue rotated 180° (red highlight kept)
struct WInvert: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.colorInvert().hueRotation(.degrees(180)) } else { content }
    }
}

struct WFramePlayer: View {
    let frames: [UIImage]
    /// Always On / background: the animation stops
    var paused = false
    @State private var i = 0
    var body: some View {
        Color.clear.overlay {
            ZStack {
                if frames.count > 2 {
                    Image(uiImage: frames[min(i, frames.count - 1)]).resizable().scaledToFill()
                } else {
                    ForEach(frames.indices, id: \.self) { k in
                        Image(uiImage: frames[k]).resizable().scaledToFill().opacity(k == i ? 1 : 0)
                    }
                }
            }
        }
        .clipped()
        // two frames: soft crossfade; video frames (MoveKit, 6 fps): no crossfade
        .animation(frames.count > 2 ? nil : .easeInOut(duration: 0.45), value: i)
        .task(id: paused) {
            guard frames.count > 1, !paused else { return }
            let step = frames.count > 2 ? 1.0 / 6 : 1.1
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(step))
                i = (i + 1) % frames.count
            }
        }
    }
}


/// Player inputs: weight and reps
@MainActor @Observable
final class WInput {
    var kg: Double = 0
    var reps = 10
}

/// Weight dial: − / Digital Crown / + and suggestion; redraws only itself
struct WKgDial: View {
    @Bindable var input: WInput
    let sug: Double?
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        let onSug = (sug ?? 0) > 0 && input.kg == sug
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                dialButton("minus", label: "Kiloyu azalt") { input.kg = max(0, input.kg - 1.25) }
                VStack(spacing: 0) {
                    // digits roll as the Crown turns; green at the suggested weight
                    Text(input.kg > 0 ? input.kg.kgText : "–").font(.system(size: 30, weight: .heavy).italic().monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(onSug ? Color.wDone : .primary)
                        .contentTransition(.numericText(value: input.kg))
                        .animation(reduce ? nil : .snappy(duration: 0.2), value: input.kg)
                    Text(onSug ? "önerilen" : "kg").font(.caption2).foregroundStyle(onSug ? Color.wDone : .secondary)
                }
                .frame(maxWidth: .infinity)
                .sensoryFeedback(.success, trigger: onSug) { _, new in new }
                .focusable()
                .modifier(WCrownStepper(value: $input.kg, range: 0...500, step: 1.25))
                dialButton("plus", label: "Kiloyu artır") { input.kg = min(500, input.kg + 1.25) }
            }
            if let sug, sug > 0, sug != input.kg {
                Button { input.kg = sug; WKInterfaceDevice.current().play(.click) } label: {
                    Label("Öneri \(sug.kgText) kg", systemImage: "sparkles").font(.footnote).frame(maxWidth: .infinity)
                }
            }
        }
    }
    private func dialButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button { action(); WKInterfaceDevice.current().play(.click) } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).frame(width: 38, height: 38)
        }
        .buttonStyle(.bordered).buttonBorderShape(.circle)
        .accessibilityLabel(tl(label))
    }
}


/// Selectable box in the player: Weight / Reps. Tap to select; the Digital Crown changes the value
enum WField: Hashable { case kg, reps }

struct WCrownTile: View {
    let label: String
    @Binding var value: Double
    let text: String
    let range: ClosedRange<Double>
    let step: Double
    let field: WField
    var focus: FocusState<WField?>.Binding
    var highlight = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        let on = focus.wrappedValue == field
        VStack(spacing: 0) {
            Text(tl(label)).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 18, weight: .heavy).italic().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(highlight ? Color.wDone : .primary)
                .contentTransition(.numericText(value: value))
                .animation(reduce ? nil : .snappy(duration: 0.2), value: value)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(.white.opacity(on ? 0.1 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? Color.wAction : .clear, lineWidth: 1.5))
        .focusable()
        .focusEffectDisabled()
        .focused(focus, equals: field)
        .modifier(WCrownStepper(value: $value, range: range, step: step))
        .onTapGesture { focus.wrappedValue = field; WKInterfaceDevice.current().play(.click) }
        .accessibilityLabel(tl(label))
        .accessibilityValue(text)
    }
}


/// Double tap on the watch (watchOS 11): bound to the complete set button
struct WPrimaryGesture: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.handGestureShortcut(.primaryAction) } else { content }
    }
}


/// Exercise library on the watch (for alternatives)
enum WAltLib {
    static let all: [ExerciseAlternatives.Candidate] = {
        struct Lib: Decodable { struct E: Decodable { let name: String; let muscle: String; let unit: String?; let tr: [String]? }; let exercises: [E] }
        guard let u = Bundle.main.url(forResource: "exercise-library", withExtension: "json"), let d = try? Data(contentsOf: u),
              let l = try? JSONDecoder().decode(Lib.self, from: d) else { return [] }
        return l.exercises.map { .init(name: $0.name, alias: $0.tr?.first, muscle: $0.muscle, unit: $0.unit ?? "tekrar") }
    }()
}

extension WStep: Identifiable { var id: String { key } }


/// Stepped changes with the Digital Crown: each click is exactly one step
/// Binding the Crown to a wide range like 0–500 spun far too fast (watchOS scales speed to the range).
/// The Crown is bound to a small counter; each click changes the value by one `step`, and the counter recenters near its edges.
struct WCrownStepper: ViewModifier {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @State private var ticks: Double = 10
    @State private var recentering = false
    func body(content: Content) -> some View {
        content
            .digitalCrownRotation($ticks, from: 0, through: 20, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: ticks) { old, new in
                if recentering { recentering = false; return }
                let d = (new - old).rounded()
                if d != 0 {
                    let next = ((value + d * step) / step).rounded() * step
                    value = min(range.upperBound, max(range.lowerBound, next))
                }
                if new <= 4 || new >= 16 { recentering = true; ticks = 10 }
            }
    }
}
