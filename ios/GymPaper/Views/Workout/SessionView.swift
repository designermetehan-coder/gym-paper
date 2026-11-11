import SwiftUI
import SwiftData
import AudioToolbox
import Combine
import GymPaperKit
import StoreKit
import TipKit

/// Antrenman modu — PWA src/screens/Session.jsx
struct SessionView: View {
    let pid: String
    let date: String
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Environment(HealthService.self) private var health
    @Environment(\.requestReview) private var requestReview
    @AppStorage("review.asked") private var reviewAsked = false
    @Query(sort: \WorkoutProgram.createdAt) private var programs: [WorkoutProgram]
    @Query private var days: [DayLog]

    /// Only this program and day are loaded; the whole history isn't queried on every set
    init(pid: String, date: String) {
        self.pid = pid; self.date = date
        _programs = Query(filter: #Predicate<WorkoutProgram> { $0.pid == pid }, sort: \WorkoutProgram.createdAt)
        _days = Query(filter: #Predicate<DayLog> { $0.date == date })
    }

    private struct Step { var ex: Exercise; var si: Int; var of: Int; var rest: Int; var label: String; var ssRound: Int?; var ssRounds: Int?; var tag: String? }
    private typealias Countdown = SessionCountdown
    static let kgValues: [Double] = Array(stride(from: 0.0, through: 500.0, by: 0.5))
    static let repValues: [Double] = Array(stride(from: 0.0, through: 100.0, by: 1.0))

    // runtime state lives in AppState: not lost when the cover closes and reopens (minimize/expand)
    private var idx: Int { get { app.rt.idx } nonmutating set { app.rt.idx = newValue } }
    private var rest: Countdown? { get { app.rt.rest } nonmutating set { app.rt.rest = newValue } }
    private var timer: Countdown? { get { app.rt.timer } nonmutating set { app.rt.timer = newValue } }
    private var finished: Bool { get { app.rt.finished } nonmutating set { app.rt.finished = newValue } }
    private var kg: Double { get { app.rt.kg } nonmutating set { app.rt.kg = newValue } }
    private var reps: Double { get { app.rt.reps } nonmutating set { app.rt.reps = newValue } }
    private var kgB: Binding<Double> { Binding(get: { app.rt.kg }, set: { app.rt.kg = $0 }) }
    private var repsB: Binding<Double> { Binding(get: { app.rt.reps }, set: { app.rt.reps = $0 }) }
    @State private var clock: WkSessionClock?
    @State private var now = Date()
    @State private var pop = 0
    @State private var prs: [WkPR] = []
    @State private var doneTick = 0
    /// Body weight is read once so the summary doesn't query the database every second
    @State private var bodyKg: Double = 75
    /// Whether the workout order below the player is open
    @State private var queueOpen = false
    /// Edit sets/reps from the player; saved to the program
    @State private var planEdit: SessionPlanEditValue?
    /// Exercises moved to the end because the machine was taken; the order goes through the others first
    @State private var later: Set<String> = []
    @Environment(\.horizontalSizeClass) private var hsc
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// Rest → next set: the rest view shrinks and fades, the player rises in slightly
    private var restOut: AnyTransition { reduce ? .opacity : .asymmetric(insertion: .opacity, removal: .scale(scale: 0.72).combined(with: .opacity)) }
    private var stepIn: AnyTransition { reduce ? .opacity : .asymmetric(insertion: .offset(y: 14).combined(with: .opacity), removal: .opacity) }
    private let restEase = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.35)
    /// Recompute the layout when the iPhone Duo hinge state changes
    @State private var hingeTick = 0
    /// Computed once per step change (not in the body)
    @State private var stepPrev: Wk.Lifted?
    @State private var stepSug: WkProgress.Suggestion?
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    /// Use the day copy ("program@day") if present: a machine-taken swap affects today only
    private var prog: WorkoutProgram? {
        let copy = ExerciseAlternatives.dayCopyPid(pid, date: date)
        return programs.first { $0.pid == copy } ?? programs.first { $0.pid == pid }
    }
    @State private var altFor: WkAltTarget?
    private var day: DayLog? { days.day(date) }

    private func buildSteps(_ p: WorkoutProgram) -> [Step] {
        var steps: [Step] = [], n = 0
        for b in p.blocks {
            if b.kind == .single, let e = b.ex {
                n += 1
                for i in 0..<max(0, e.sets) { steps.append(Step(ex: e, si: i, of: e.sets, rest: e.rest, label: "#\(n)")) }
            } else if !b.exs.isEmpty {
                n += 1
                let R = max(1, b.rounds)
                for r in 0..<R { for (j, e) in b.exs.enumerated() {
                    steps.append(Step(ex: e, si: r, of: R, rest: j == b.exs.count - 1 ? b.rest : 0, label: "\(n)\(String(UnicodeScalar(97 + j)!))", ssRound: r + 1, ssRounds: R, tag: b.tag))
                } }
            }
        }
        return steps
    }
    private func isDone(_ s: Step) -> Bool {
        guard let d = day else { return false }
        // the list mark works both ways: when removed (false), the sets count as not done
        if let f = d.exDone[s.ex.id] { return f }
        let a = d.sets[s.ex.id] ?? []
        return s.si < a.count && a[s.si].done
    }

    /// Changes when the program's steps change (edit, swap); the current step is found again by id
    private var stepsSignature: String {
        guard let prog else { return "" }
        return buildSteps(prog).map { "\($0.ex.id)\($0.si)" }.joined()
    }

    var body: some View {
        Group {
            if let prog { content(prog, steps: buildSteps(prog)) } else { Color.bBg.onAppear { app.closeSession() } }
        }
        .background(SessionBackdrop())
        .onReceive(tick) { t in onTick(t) }
        .onChange(of: app.sessionMin) { _, m in if m { publishNow() } }
        .onAppear {
            app.rt.use(pid + date); UIApplication.shared.isIdleTimerDisabled = true
            // continue from a newer state on the watch (last 4 hours)
            if let r = LiveBridge.shared.remote, r.at > Date().addingTimeInterval(-4 * 3600) {
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); applyRemote(r) }
            }
            publishNow()
        }
        // keep the Lock Screen / Dynamic Island current
        .onChange(of: app.rt.idx) { publishNow() }
        .onChange(of: app.rt.rest) { publishNow() }
        .onChange(of: app.rt.finished) { publishNow() }
        .onChange(of: app.rt.kg) { publishNow() }
        .onChange(of: app.rt.reps) { publishNow() }
        .onChange(of: clock?.pausedAt) { publishNow() }
        .onChange(of: later) { publishNow() }
        // changes made on the watch (skip set, pause, rest, weight/reps, machine taken) show up here too
        .onChange(of: LiveBridge.shared.remote) { _, s in applyRemote(s) }
        .onChange(of: stepsSignature) { _, _ in
            guard let prog, idx >= 0 else { return }
            let st = buildSteps(prog)
            // find the step again by id; otherwise jump to the first step not done
            if let k = app.rt.stepKey, let j = st.firstIndex(where: { "\($0.ex.id)#\($0.si)" == k }) {
                if j != idx { idx = j; loadStep(st) } else { loadHints(st[j]) }
            } else {
                idx = max(0, st.firstIndex { !isDone($0) } ?? 0); loadStep(st)
            }
        }
        .onDisappear { if app.session != nil { publishNow() }; UIApplication.shared.isIdleTimerDisabled = false }
        // Figma screenshots (-session -shot …)
        .shot("session.rest", delay: 2.5) { if let p = prog { let st = buildSteps(p); if st.indices.contains(idx) { complete(st[idx], st) } } }
        .shot("session.paused", delay: 2.5) { pause() }
        .shot("session.done", delay: 2.5) { timer = nil; rest = nil; withAnimation { finished = true }; loadPRs() }
        .shot("session.queue", delay: 2.5) { queueOpen = true }
        .shot("session.edit", delay: 2.5) { shotEdit() }
    }

    private func shotEdit() {
        guard let p = prog else { return }
        let st = buildSteps(p)
        guard st.indices.contains(idx) else { return }
        let c = st[idx]
        let sets = Double(c.ssRounds ?? c.ex.sets)
        planEdit = SessionPlanEditValue(eid: c.ex.id, name: c.ex.name, sets: sets, reps: Double(c.ex.reps), unit: c.ex.unit, superset: c.ssRounds != nil)
    }

    @ViewBuilder private func content(_ prog: WorkoutProgram, steps: [Step]) -> some View {
        let doneCount = steps.filter(isDone).count
        let paused = clock?.pausedAt != nil
        let elapsed = (day?.workoutSeconds ?? 0) > 0 ? day!.workoutSeconds : (finished ? (clock?.total ?? 0) : (clock?.elapsed(now) ?? 0))
        let step: Step? = idx >= 0 && idx < steps.count ? steps[idx] : nil
        VStack(spacing: 0) {
            Capsule().fill(Color.bFg.opacity(0.25)).frame(width: 40, height: 5).padding(.top, 8)
                .accessibilityHidden(true)
            // Header like a music player: grabber + small info; the menu sits beside the title
            let inStep = !steps.isEmpty && !finished && !paused && rest == nil && step != nil
            // Like Apple Fitness: elapsed time on the left, live
            HStack(spacing: 8) {
                SessionLiveMetric(clock: clock, bodyKg: bodyKg, kind: .time).lineLimit(1).minimumScaleFactor(0.6).frame(width: 76, height: 44, alignment: .leading)
                Text("\(prog.name) · \(min(steps.count, max(1, idx + 1)))/\(steps.count) set\(paused ? tl(" · duraklatıldı") : "")")
                    .font(.geist(13, .medium, relativeTo: .footnote)).monospacedDigit().foregroundStyle(Color.bMutedFg).lineLimit(1)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                if inStep { Color.clear.frame(width: 76, height: 44) } else { sessionMenu(steps).frame(width: 76, alignment: .trailing) }
            }
            .foregroundStyle(Color.bFg)
            .padding(.horizontal, 16).padding(.top, 2)
            // story bar: one segment per exercise (1.2)
            if !steps.isEmpty && !finished {
                storyBar(steps).padding(.horizontal, 20).padding(.top, 12)
            }

            if steps.isEmpty {
                VStack(spacing: 16) {
                    Text("Bu programda hareket yok").font(.geist(18, .semibold))
                    Button("Kapat") { app.closeSession() }.buttonStyle(.b(.outline))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if finished {
                finishView(prog, steps: steps, doneCount: doneCount, elapsed: elapsed)
            // pausing doesn't open the summary: stay in the player; the pause button turns into play
            } else if let r = rest {
                // iPhone Duo half-folded: ring in one half, buttons in the other
                DuoFoldReader { fold in
                    if let fold, fold.width >= fold.height {
                        VStack(spacing: 0) {
                            VStack(spacing: 12) { restTitle; RestRing(end: r.end, total: r.total, frozenLeft: r.left, size: max(120, min(220, fold.minY - 56))) }
                                .frame(maxWidth: .infinity).frame(height: max(0, fold.minY))
                            Color.clear.frame(height: fold.height)
                            VStack(spacing: 24) { restButtons(r); restNext(step) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else if let fold {
                        HStack(spacing: 0) {
                            VStack(spacing: 12) { restTitle; RestRing(end: r.end, total: r.total, frozenLeft: r.left) }
                                .frame(width: max(0, fold.minX)).frame(maxHeight: .infinity)
                            Color.clear.frame(width: fold.width)
                            VStack(spacing: 24) { restButtons(r); restNext(step) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        // Figma "Rest · Next exercise": lime ring, ±15 s, up-next card, ready button
                        VStack(spacing: 20) {
                            Spacer(minLength: 0)
                            RestRing(end: r.end, total: r.total, frozenLeft: r.left, size: 240, labeled: true)
                            restButtons(r)
                            Spacer(minLength: 0)
                            restNext(step)
                            Button { haptic(); withAnimation(restEase) { rest = nil } } label: {
                                HStack(spacing: 8) { Text("Hazırım, başla"); Image(systemName: "play.fill").font(.system(size: 14, weight: .bold)) }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.b(.primary, .large, full: true))
                        }
                        .padding(.horizontal, 20).padding(.bottom, 12)
                        .frame(maxWidth: 560, maxHeight: .infinity)
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(restOut)
            } else if let step {
                stepView(step, steps: steps)
                    .transition(stepIn)
            }
        }
        .overlay {
            if pop > 0 {
                Ti("check", size: 40).foregroundStyle(.white).frame(width: 80, height: 80).background(Color.bSuccess, in: Circle())
                    .shadow(radius: 10).id(pop).transition(.scale(scale: 0.8).combined(with: .opacity))
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 220).allowsHitTesting(false)
            }
        }
        .onAppear { start(steps) }
        .sheet(item: $planEdit) { e in planEditSheet(e) }
        .sheet(item: $altFor) { t in
            WkAltSheet(target: t, exclude: Set(self.prog?.blocks.allExercises.map { TextNorm.norm($0.name) } ?? [])) { name, muscle, alsoProgram in
                swapExercise(t, to: name, muscle: muscle, alsoProgram: alsoProgram)
            } onLater: {
                if let pr = self.prog { let st = buildSteps(pr); if let s0 = st.first(where: { $0.ex.id == t.eid }) { postpone(s0, st) } }
            }
            .presentationDetents([.large])
        }
        // a firm tap when rest ends: you feel the move to the next set
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.8), trigger: rest == nil) { old, new in !old && new }
    }

    private var restTitle: some View {
        Text("DİNLENME").font(.geist(14, .medium, relativeTo: .subheadline)).tracking(0.8).foregroundStyle(Color.bMutedFg)
    }
    private func restButtons(_ r: Countdown) -> some View {
        HStack(spacing: 8) {
            Button { haptic(); rest = Countdown(end: r.end.addingTimeInterval(-15), total: max(15, r.total - 15), left: r.left.map { max(0, $0 - 15) }) } label: { Text("−15 sn").monospacedDigit() }
                .buttonStyle(.b(.outline, .small))
            Button { haptic(); withAnimation(restEase) { rest = nil } } label: {
                HStack(spacing: 6) { Image(systemName: "forward.end.fill").font(.system(size: 12)); Text("Atla") }
            }
            .buttonStyle(.b(.outline, .small))
            Button { haptic(); rest = Countdown(end: r.end.addingTimeInterval(15), total: r.total + 15, left: r.left.map { $0 + 15 }) } label: { Text("+15 sn").monospacedDigit() }
                .buttonStyle(.b(.outline, .small))
        }
    }
    @ViewBuilder private func restNext(_ step: Step?) -> some View {
        if let step {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    // the next exercise's own picture (MoveKit poster); neutral box without one
                    WkThumb(name: step.ex.name, size: 56).clipShape(RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SIRADAKİ").font(.geist(11, .medium, relativeTo: .caption2)).tracking(0.6).foregroundStyle(Color.bHeroMuted)
                        Text(step.ex.name).font(.bDisplay(20, relativeTo: .title3)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Set").font(.bXs).foregroundStyle(Color.bHeroMuted)
                        (Text("\(step.si + 1)").font(.bNum(24)).foregroundColor(Color.bHeroAccent) + Text("/\(step.of)").font(.bXs).foregroundColor(Color.bHeroMuted))
                    }
                }
                if step.ex.unit == "tekrar" {
                    HStack(spacing: 8) {
                        nextTile("Kilo", kg > 0 ? fmt1(kg) : "–", "kg")
                        nextTile("Tekrar", fmt0(reps), tl("tekrar"))
                    }
                    if let prev = stepPrev {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Color.bHeroAccent)
                            Text(stepSug.map { $0.up ? String(localized: "Son \(fmt1(prev.kg)) × \(prev.reps ?? step.ex.reps) · bugün \(fmt1($0.kg)) kg dene") : String(localized: "Son \(fmt1(prev.kg)) × \(prev.reps ?? step.ex.reps)") }
                                 ?? String(localized: "Son \(fmt1(prev.kg)) × \(prev.reps ?? step.ex.reps)"))
                                .font(.bXs).monospacedDigit().foregroundStyle(Color.bHeroMuted)
                        }
                    }
                } else {
                    Text(step.ex.unit == "sn" ? String(localized: "\(step.ex.reps) saniye") : String(localized: "\(step.ex.reps) dakika")).font(.bSm).foregroundStyle(Color.bHeroMuted)
                }
            }
            .bHeroCard(padding: 16)
            .accessibilityElement(children: .combine)
        }
    }
    private func nextTile(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tl(label)).font(.bXs).foregroundStyle(Color.bHeroMuted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.bNum(24, relativeTo: .title2))
                Text(unit).font(.bXs).foregroundStyle(Color.bHeroMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.bHeroFill, in: RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
    }

    /// Session menu (⋯)
    private func sessionMenu(_ steps: [Step]) -> some View {
        return Menu {
            if !finished { Button { timer = nil; rest = nil; withAnimation { finished = true }; loadPRs() } label: { Label("Antrenmanı bitir", systemImage: "flag.checkered") } }
            if !finished { Button { app.minimizeSession(true) } label: { Label("Küçült", systemImage: "chevron.down") } }
            Button(role: .destructive) { WkSessionClock.clear(date); app.closeSession() } label: { Label("Süreyi kaydetmeden kapat", systemImage: "xmark") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).frame(width: 36, height: 36)
                .background(Color.bFg.opacity(0.08), in: Circle())
                .frame(width: 44, height: 44)
        }
        .foregroundStyle(Color.bFg)
        .accessibilityLabel("Diğer")
    }

    /// One segment per exercise: done = ink, current = lime, upcoming = track
    private func storyBar(_ steps: [Step]) -> some View {
        var order: [String] = []
        for st in steps where !order.contains(st.ex.id) { order.append(st.ex.id) }
        let cur = idx >= 0 && idx < steps.count ? steps[idx].ex.id : nil
        return HStack(spacing: 4) {
            ForEach(order, id: \.self) { id in
                let all = steps.filter { $0.ex.id == id }
                let done = all.allSatisfy(isDone)
                Capsule().fill(done ? Color.bPrimary : id == cur ? Color.bAction : Color.bFg.opacity(0.12)).frame(height: 4)
            }
        }
        .animation(.snappy, value: idx)
        .accessibilityElement().accessibilityLabel(tl("Antrenman ilerlemesi"))
        .accessibilityValue(Text("\(order.firstIndex(of: cur ?? "").map { $0 + 1 } ?? 0)/\(order.count)"))
    }

    /// Player + workout order below. Manual scrolling is off; only "Up next" scrolls to the order.
    private func stepView(_ step: Step, steps: [Step]) -> some View {
        ScrollViewReader { sp in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    playerPage(step, steps: steps)
                        .containerRelativeFrame(.vertical)
                        .id("player")
                    // the order only shows after tapping "Up next"; it must not peek like a hint
                    queuePage(step, steps: steps)
                        .containerRelativeFrame(.vertical)
                        .opacity(queueOpen ? 1 : 0)
                        .allowsHitTesting(queueOpen)
                        .animation(.easeOut(duration: 0.25), value: queueOpen)
                        .id("queue")
                }
            }
            .scrollDisabled(true)
            .onChange(of: queueOpen) { _, open in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { sp.scrollTo(open ? "queue" : "player", anchor: .top) }
            }
            .onAppear { if queueOpen { sp.scrollTo("queue", anchor: .top) } }
        }
    }

    /// Workout order: completed sets per exercise; tap to jump to that exercise
    @ViewBuilder private func queuePage(_ step: Step, steps: [Step]) -> some View {
        let order: [Exercise] = steps.reduce(into: [Exercise]()) { acc, st in if !acc.contains(where: { $0.id == st.ex.id }) { acc.append(st.ex) } }
        VStack(spacing: 0) {
            Button { haptic(); queueOpen = false } label: {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.compact.up").font(.system(size: 28, weight: .semibold))
                    Text("Oynatıcıya dön").font(.geist(12, .medium, relativeTo: .caption))
                }
                .foregroundStyle(Color.bMutedFg)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .accessibilityLabel("Oynatıcıya dön")
            HStack {
                Text("ANTRENMAN SIRASI").font(.geist(12, .medium, relativeTo: .caption)).tracking(0.6).foregroundStyle(Color.bMutedFg)
                Spacer()
                Text("\(steps.filter(isDone).count)/\(steps.count) set").font(.geist(12, .medium, relativeTo: .caption)).monospacedDigit().foregroundStyle(Color.bMutedFg)
            }
            .padding(.horizontal, 24).padding(.bottom, 4)
            Text("Alet doluysa istediğin harekete dokunup ona geç; sıra sonra kaldığın yerden devam eder.")
                .font(.bXs).foregroundStyle(Color.bMutedFg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.bottom, 8)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(order.enumerated()), id: \.element.id) { i, ex in
                        let mine = steps.indices.filter { steps[$0].ex.id == ex.id }
                        let doneN = mine.filter { isDone(steps[$0]) }.count
                        let all = doneN == mine.count
                        let current = ex.id == step.ex.id
                        if i > 0 { Rectangle().fill(Color.bBorder).frame(height: 1).padding(.leading, 84) }
                        Button {
                            haptic()
                            if let j = mine.first(where: { !isDone(steps[$0]) }) ?? mine.first {
                                later.remove(ex.id)
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { idx = j; loadStep(steps) }
                            }
                            queueOpen = false
                        } label: {
                            HStack(spacing: 12) {
                                ZStack(alignment: .bottomTrailing) {
                                    WkThumb(name: ex.name, size: 52).opacity(all && !current ? 0.55 : 1)
                                    if all {
                                        Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.bSuccess).offset(x: 5, y: 5)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.name).font(.geist(16, .medium)).lineLimit(1)
                                        .foregroundStyle(all && !current ? Color.bMutedFg : Color.bFg)
                                    Text(current ? "Şu an · \(doneN)/\(mine.count) set" : all ? "Tamamlandı · \(mine.count) set" : later.contains(ex.id) ? "Sona bırakıldı · \(doneN)/\(mine.count) set" : "\(doneN)/\(mine.count) set")
                                        .font(.bXs).monospacedDigit().foregroundStyle(current ? Color.bPrimary : Color.bMutedFg)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if current { Image(systemName: "waveform").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.bPrimary).symbolEffect(.variableColor.iterative, options: .repeating) }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(ex.name), \(doneN) / \(mine.count) set\(current ? tl(", şu an") : "")")
                    }
                }
                .bCard(padding: 0)
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func playerPage(_ step: Step, steps: [Step]) -> some View {
        // iPhone Duo: split on both sides of the fold when half-folded; iPhone layout when flat
        GeometryReader { g in
            let _ = hingeTick
            let fold = DuoFold.region(g)
            if let fold, fold.width < fold.height {
                // Book pose: vertical fold — visual on one page, controls on the other
                HStack(spacing: 0) {
                    playerCover(step).frame(width: max(0, fold.minX)).frame(maxHeight: .infinity)
                    Color.clear.frame(width: fold.width)
                    playerDetails(step, steps: steps).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let fold {
                // Stand / table pose: horizontal fold — large centered visual on top, controls below
                VStack(spacing: 0) {
                    // account for the cover's own padding (horizontal 24, top 18); the visual fills the top half
                    let side = max(0, min(fold.minY - 30, g.size.width - 48))
                    playerCover(step).frame(width: side * 1.05 + 48, height: side + 18)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(0, fold.minY))
                    Color.clear.frame(height: fold.height)
                    playerDetails(step, steps: steps).frame(maxWidth: 720).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    // in a wide but short area (Split View) the cover must not push the controls down
                    // on short screens (Duo outer screen) the cover shrinks so the bottom row fits
                    // iPhone layout on every screen (Duo inner screen too): cover on top, controls below; 560 pt column on wide screens
                    playerCover(step).frame(maxHeight: hsc == .regular ? min(520, g.size.height * 0.45) : (g.size.height < 760 ? g.size.height * 0.4 : nil))
                    Spacer(minLength: 16)
                    playerDetails(step, steps: steps)
                }
                .frame(maxWidth: 560, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
            }
        }
        .modifier(DuoHingeWatcher(tick: $hingeTick))
    }

    @ViewBuilder private func playerCover(_ step: Step) -> some View {
        let paused = clock?.pausedAt != nil
        // Kapak
            GeometryReader { g in
                Group {
                    if Motion.hasVisual(step.ex.name) {
                        MotionPlayer(name: step.ex.name, height: g.size.height, fill: true, paused: paused).id(step.ex.name)
                    } else {
                        RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous).fill(Color.bMuted)
                            .overlay(Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 72)).foregroundStyle(Color.bMutedFg.opacity(0.5)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 24, y: 8)
                .scaleEffect(paused ? 0.86 : 1)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: paused)
            }
            .aspectRatio(1.05, contentMode: .fit)
            .padding(.horizontal, 24).padding(.top, 18)

    }

    @ViewBuilder private func playerDetails(_ step: Step, steps: [Step]) -> some View {
        let prev = stepPrev
        let sug = stepSug
        let ni = nextIdx(idx, steps)
        let upcoming = ni >= 0 && ni != idx ? steps[ni] : nil
        VStack(spacing: 0) {
            // Title + ⋯
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.ex.name).font(.bDisplay(22, relativeTo: .title2)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(subtitle(step)).font(.geist(17, relativeTo: .body)).foregroundStyle(Color.bMutedFg).lineLimit(1)
                }
                Spacer(minLength: 0)
                sessionMenu(steps)
            }
            .padding(.horizontal, 24)

            // Set bar
            VStack(spacing: 6) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.bFg.opacity(0.15))
                        Capsule().fill(Color.bFg.opacity(0.85)).frame(width: max(6, g.size.width * Double(step.si) / Double(max(1, step.of))))
                    }
                }
                .frame(height: 6)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: step.si)
                HStack {
                    Text("Set \(step.si + 1)").monospacedDigit()
                    Spacer()
                    if let prev { Text("son \(fmt1(prev.kg)) kg × \(prev.reps ?? step.ex.reps)").monospacedDigit() }
                    Spacer()
                    Text("\(step.of) set").monospacedDigit()
                }
                .font(.geist(12, .medium, relativeTo: .caption)).foregroundStyle(Color.bMutedFg)
            }
            .padding(.horizontal, 24).padding(.top, 18)

            // Inputs
            Group {
                if step.ex.unit == "tekrar" {
                    HStack(spacing: 8) {
                        BKgField(label: "Kilo", value: kgB, suffix: "kg")  // keyboard entry
                        // Reps and sets edit on tap like weight; the change is saved to the program
                        BPickField(label: "Tekrar", value: Binding(get: { reps }, set: { v in reps = v; applyPlan(step, reps: Int(v)) }),
                                   values: Array(Self.repValues.dropFirst()), format: { fmt0($0) })
                        BPickField(label: "Set", value: Binding(get: { Double(step.of) }, set: { v in applyPlan(step, sets: Int(v)) }),
                                   values: Array(stride(from: Double(step.si + 1), through: 20, by: 1)), format: { "\(step.si + 1)/\(Int($0))" })
                    }
                } else if step.ex.unit == "sn" {
                    let total = Double(step.ex.reps)
                    HStack(spacing: 16) {
                        if let t = timer { RestRing(end: t.end, total: t.total, frozenLeft: t.left, size: 84) }
                        else {
                            Text(Wk.mmss(Int(total))).font(.bNum(36, relativeTo: .largeTitle))
                            Button { timer = Countdown(end: Date().addingTimeInterval(total), total: total) } label: { BLabel("Süreyi başlat") }
                                .buttonStyle(.b(.outline))
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("\(step.ex.reps) dakika · bitirince işaretle").font(.bSm).foregroundStyle(Color.bMutedFg).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24).padding(.top, 14)

            Spacer(minLength: 12)

            // Controls: previous · pause (middle) · complete set and go next; on the last set the right button becomes a green "finish"
            let isLast = upcoming == nil
            let others = steps.contains { $0.ex.id != step.ex.id && !isDone($0) }
            HStack(spacing: 0) {
                Button { haptic(); withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { idx = max(0, idx - 1); loadStep(steps) } } label: {
                    Image(systemName: "backward.end.fill").font(.system(size: 30)).frame(width: 64, height: 64)
                }
                .buttonStyle(MusicControlStyle()).disabled(idx <= 0).accessibilityLabel("Önceki set")
                .frame(maxWidth: .infinity)
                let isPaused = clock?.pausedAt != nil
                Button { isPaused ? resume() : pause() } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill").font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color.bBg)
                        .frame(width: 84, height: 84)
                        .background(Color.bFg, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(MusicControlStyle()).accessibilityLabel(isPaused ? "Devam et" : "Duraklat")
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { complete(step, steps) }; doneTick += 1 } label: {
                    Image(systemName: isLast ? "checkmark" : "forward.end.fill")
                        .font(.system(size: isLast ? 26 : 30, weight: isLast ? .bold : .regular))
                        .foregroundStyle(isLast ? Color.white : Color.bFg)
                        .frame(width: 64, height: 64)
                        .background(isLast ? Color.bSuccess : Color.clear, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isLast)
                }
                .buttonStyle(MusicControlStyle())
                .accessibilityLabel(isLast ? "Son seti tamamla ve antrenmanı bitir" : "Seti tamamla, sonrakine geç")
                .popoverTip(TipCompleteSet(), arrowEdge: .bottom)
                .sensoryFeedback(.success, trigger: doneTick)
                #if DEBUG
                .onReceive(NotificationCenter.default.publisher(for: .tourCompleteSet)) { _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { complete(step, steps) }; doneTick += 1
                }
                #endif
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.bFg)
            .padding(.horizontal, 12)

            Spacer(minLength: 12)

            // Bottom row: suggestion · up next (exercise list) · machine taken
            HStack(spacing: 0) {
                if let sug { Button { haptic(); kg = sug.kg; if let r = sug.reps { reps = Double(r) } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: sug.up ? (sug.assisted ? "arrow.down.circle" : "arrow.up.circle") : "sparkles").font(.system(size: 20))
                        Text(sug.up ? "\(fmt1(sug.kg)) kg × \(sug.reps ?? Progression.resetReps)" : "Öneri \(fmt1(sug.kg)) kg").font(.geist(11, .medium, relativeTo: .caption2)).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .disabled(sug.kg == kg).accessibilityLabel(sug.up ? "Kiloyu artır: \(fmt1(sug.kg)) kilo, \(sug.reps ?? Progression.resetReps) tekrar" : "Önerilen kiloyu yaz") }
                Button { haptic(); queueOpen = true } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "list.bullet").font(.system(size: 20))
                        Text(upcoming.map { $0.ex.name == step.ex.name ? String(localized: "Sıradaki: Set \($0.si + 1)") : String(localized: "Sıradaki: \($0.ex.name)") } ?? String(localized: "Son set"))
                            .font(.geist(11, .medium, relativeTo: .caption2)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .accessibilityLabel("Başka harekete geç: antrenman sırasını göster")
                // Machine taken: alternatives for the same area; leaving it for later is there too
                Button {
                    haptic()
                    let done = steps.filter { $0.ex.id == step.ex.id && isDone($0) }.count
                    altFor = WkAltTarget(eid: step.ex.id, name: step.ex.name, muscle: step.ex.muscle, unit: step.ex.unit, done: done, canLater: others)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "hourglass").font(.system(size: 20))   // machine taken: wait, then do it
                        Text("Alet dolu").font(.geist(11, .medium, relativeTo: .caption2)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .accessibilityLabel("Alet dolu: alternatif hareket öner")
            }
            .foregroundStyle(Color.bMutedFg)
            .buttonStyle(.press)
            // keep the bottom row clear of rounded screen corners
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }

    private func subtitle(_ step: Step) -> String {
        String(localized: "Set \(step.si + 1)/\(step.of)")
    }

    private enum SummaryMode { case paused, finished }
    static func tileColor(_ k: String) -> Color {
        switch k {
        case "Süre": .fitTime
        case "Tahmini kalori": .fitKcal
        case "Tamamlanan set": .bPrimary
        case "Hareket": .fitPurple
        case "Toplam tekrar": .fitBlue
        case "Hacim": .fitGreen
        default: .bFg
        }
    }
    @ViewBuilder private func finishView(_ prog: WorkoutProgram, steps: [Step], doneCount: Int, elapsed: Int) -> some View {
        summaryView(prog, steps: steps, doneCount: doneCount, elapsed: elapsed, mode: .finished)
    }

    /// Pause and finish screen: summary in the header, row-by-row table (title left, bold value right), buttons at the bottom
    @ViewBuilder private func summaryView(_ prog: WorkoutProgram, steps: [Step], doneCount: Int, elapsed: Int, mode: SummaryMode) -> some View {
        let doneSteps = steps.filter(isDone)
        let volume = doneSteps.reduce(0.0) { a, st in
            guard st.ex.unit == "tekrar", let d = day, let arr = d.sets[st.ex.id], st.si < arr.count else { return a }
            let s = arr[st.si]
            return a + max(0, s.kg ?? 0) * Double((s.reps ?? 0) > 0 ? s.reps! : st.ex.reps)
        }
        let reps = doneSteps.reduce(0) { a, st in
            guard st.ex.unit == "tekrar", let d = day, let arr = d.sets[st.ex.id], st.si < arr.count else { return a }
            return a + ((arr[st.si].reps ?? 0) > 0 ? arr[st.si].reps! : st.ex.reps)
        }
        let exDone = Set(doneSteps.map(\.ex.id)).count
        let exTotal = Set(steps.map(\.ex.id)).count
        let topLift = doneSteps.compactMap { st -> (String, Double)? in
            guard let d = day, let arr = d.sets[st.ex.id], st.si < arr.count, let kg = arr[st.si].kg, kg > 0 else { return nil }
            return (st.ex.name, kg)
        }.max { $0.1 < $1.1 }
        let kcal = CalorieEngine.workoutKcal(minutes: Double(elapsed) / 60, weightKg: bodyKg)
        // no estimated calories or heaviest set while paused
        let rows: [(String, String)] = [
            ("Süre", Wk.mmss(elapsed)),
            ("Tamamlanan set", "\(doneCount) / \(steps.count)"),
            ("Hareket", "\(exDone) / \(exTotal)"),
            ("Toplam tekrar", "\(reps)"),
            ("Hacim", String(localized: "\(fmt0(volume)) kg")),
        ] + (mode == .finished ? [("Tahmini kalori", String(localized: "\(fmt0(kcal)) kcal"))] + (topLift.map { [("En ağır set", String(localized: "\($0.0) · \(fmt1($0.1)) kg"))] } ?? []) : [])
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: mode == .finished ? "trophy.fill" : "pause.circle.fill")
                        .font(.system(size: 52)).foregroundStyle(Color.bPrimary)
                        // on finish the trophy pops from small, overshooting by 15%
                        .modifier(BPopIn(from: mode == .finished ? 0.3 : 1))
                        .padding(.top, 24)
                    VStack(spacing: 4) {
                        Text(mode == .finished ? "Antrenman bitti" : "Duraklatıldı").font(.b2xl)
                        Text(prog.name).foregroundStyle(Color.bMutedFg)
                    }
                    // progress ring
                    BRing(value: Double(doneCount) / Double(max(1, steps.count)), size: 88, stroke: 8) {
                        Text("%\(Int((Double(doneCount) / Double(max(1, steps.count)) * 100).rounded()))").font(.bNum(18))
                    }
                    // summary rows: title on the left (secondary), value on the right (primary)
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                            if i > 0 { Rectangle().fill(Color.bBorder).frame(height: 1) }
                            HStack(spacing: 12) {
                                Text(tl(r.0)).font(.bSm).foregroundStyle(Color.bMutedFg).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(r.1).font(.bNum(17, relativeTo: .headline)).foregroundStyle(Color.bFg)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .padding(.horizontal, 16).frame(minHeight: 48)
                            .accessibilityElement(children: .combine)
                            // tiles rise 50 ms apart
                            .modifier(BRise(index: i, step: 0.05, base: 0.22, maxIndex: 8))
                        }
                    }
                    .bCard(padding: 0)
                    // muscles worked in this workout (from done sets)
                    if mode == .finished {
                        let items = MuscleData.done(prog.blocks.allExercises, day: day)
                        if !items.isEmpty {
                            MuscleLoadCard(meta: String(localized: "\(doneCount) set · \(Wk.mmss(elapsed))"), entries: MuscleLoad.load(items, scope: .workout))
                        }
                    }
                    if !prs.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(Array(prs.enumerated()), id: \.element.id) { k, p in
                                HStack(spacing: 12) {
                                    Image(systemName: "trophy.fill").font(.system(size: 20)).foregroundStyle(Color.bPrimary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("YENİ REKOR").font(.geist(12, .semibold, relativeTo: .caption)).tracking(0.6).foregroundStyle(Color.bPrimary)
                                        Text(p.name).font(.geist(16, .medium)).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(fmt1(p.kg)) kg × \(p.reps)").font(.bNum(16))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(Color.bPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
                                .modifier(BPopIn(delay: 0.6 + Double(k) * 0.08, from: 0.8))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
            // buttons pinned at the bottom
            VStack(spacing: 8) {
                if mode == .paused {
                    Button { resume() } label: { BLabel("Devam et") }.buttonStyle(.b(.primary, .large, full: true))
                    Button { timer = nil; rest = nil; withAnimation { finished = true }; loadPRs() } label: { BLabel("Antrenmanı bitir") }.buttonStyle(.b(.outline, .large, full: true))
                } else {
                    Button { save(prog, elapsed: elapsed) } label: { BLabel("Kaydet ve kapat") }.buttonStyle(.b(.primary, .large, full: true))
                    if doneCount < steps.count {
                        Button("Antrenmana dön") {
                            if let f = steps.firstIndex(where: { !isDone($0) }) { idx = f; loadStep(steps) }
                            withAnimation { finished = false }
                        }
                        .buttonStyle(.b(.outline, .large, full: true))
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 12).padding(.top, 8)
        }
        // realistic confetti + haptic; the confetti plays the success haptic
        .overlay { if mode == .finished { ConfettiBurst().ignoresSafeArea() } }
    }

    // MARK: - Logic

    private func start(_ steps: [Step]) {
        // set the session key first: if the parent's onAppear ran later it reset idx to -1 and left the player empty
        app.rt.use(pid + date)
        bodyKg = Store.latestWeight(ctx) ?? Store.profile(ctx).startKg ?? 75
        // the clock persists (UserDefaults): restored when the view is rebuilt after minimize/expand
        if clock == nil {
            // the clock starts when the player opens (so the top-left timer runs right away)
            if var c = WkSessionClock.load(date) {
                if !c.started && c.pausedAt == nil { c.begin(); c.save(date) }
                clock = c
            } else if (day?.workoutSeconds ?? 0) == 0 { var c = WkSessionClock(); c.begin(); c.save(date); clock = c }
        }
        guard idx < 0 else {
            // if the program changed during the session, go back to a valid step
            if let k = app.rt.stepKey, let j = steps.firstIndex(where: { "\($0.ex.id)#\($0.si)" == k }), j != idx { idx = j; loadStep(steps) }
            else if idx >= steps.count || steps.isEmpty { idx = max(0, steps.firstIndex { !isDone($0) } ?? 0); loadStep(steps) }
            else { loadHints(steps[idx]) }
            // don't get stuck on the finish screen if it was unmarked elsewhere
            if finished && (day?.workoutSeconds ?? 0) == 0 && !steps.isEmpty && !steps.contains(where: isDone) { finished = false }
            if finished { loadPRs() }
            return
        }
        idx = max(0, steps.firstIndex { !isDone($0) } ?? 0)
        finished = !steps.isEmpty && steps.allSatisfy(isDone)
        if finished { loadPRs() }
        loadStep(steps)
    }
    /// "last X kg" and suggestion lines (refreshed whenever the view opens)
    private func loadHints(_ st: Step) {
        stepPrev = Wk.lastLifted(ctx, eid: st.ex.id, before: date)
        stepSug = st.ex.unit == "tekrar" ? WkProgress.suggestKg(ctx, st.ex, date: date) : nil
    }
    private func loadStep(_ steps: [Step]) {
        guard idx >= 0, idx < steps.count else { return }
        let st = steps[idx]
        app.rt.stepKey = "\(st.ex.id)#\(st.si)"
        let arr = day?.sets[st.ex.id] ?? []
        let logged = st.si < arr.count ? arr[st.si] : SetLog()
        let prevSet = st.si > 0 && st.si - 1 < arr.count ? arr[st.si - 1] : nil
        loadHints(st)
        kg = [logged.kg, prevSet?.kg, st.ex.kg, stepPrev?.kg].compactMap { $0 }.first { $0 > 0 } ?? 0
        reps = Double((logged.reps ?? 0) > 0 ? logged.reps! : st.ex.reps)
        timer = nil
    }
    private func nextIdx(_ from: Int, _ steps: [Step]) -> Int {
        guard !steps.isEmpty else { return -1 }
        // exercises not moved to the end first; then back to the ones that were
        for k in 1..<max(1, steps.count) { let i = (from + k) % steps.count; if !isDone(steps[i]) && !later.contains(steps[i].ex.id) { return i } }
        for k in 1..<max(1, steps.count) { let i = (from + k) % steps.count; if !isDone(steps[i]) { return i } }
        return -1
    }
    /// Machine taken → alternative: only today changes (the program too when the switch is on); done sets are kept
    private func swapExercise(_ t: WkAltTarget, to name: String, muscle: String, alsoProgram: Bool) {
        WkMemo.clear()
        let newId = ExerciseAlternatives.swappedId(t.eid, name: name)
        let done = t.done
        // move the position to the new exercise's first set not done
        app.rt.stepKey = "\(newId)#0"
        guard let undo = Store.swapForDay(ctx, date: date, pid: pid, eid: t.eid, doneSets: done, to: name, muscle: muscle) else { return }
        var progUndo: (WorkoutProgram, Data)?
        if alsoProgram, let base = Wk.program(pid.split(separator: "@").first.map(String.init), ctx), !base.archived {
            progUndo = (base, base.blocksData)
            Wk.editBlocks(ctx, base) { b in b = ExerciseAlternatives.swap(b, eid: t.eid, doneSets: 0, to: name, muscle: muscle) }
        }
        Store.save(ctx)
        WkMemo.clear()
        #if !LITE
        WatchSync.shared.push()
        #endif
        rest = nil
        app.toast(String(localized: "\(name) ile değiştirildi")) { [ctx, date] in
            Store.undoSwap(ctx, date: date, undo)
            if let pu = progUndo { pu.0.blocksData = pu.1 }
            Store.save(ctx); WkMemo.clear()
            #if !LITE
            WatchSync.shared.push()
            #endif
        }
    }
    /// Machine taken: moves the exercise to the end and goes to the next different exercise
    private func postpone(_ st: Step, _ steps: [Step]) {
        haptic()
        later.insert(st.ex.id)
        if let j = steps.indices.first(where: { steps[$0].ex.id != st.ex.id && !isDone(steps[$0]) && !later.contains(steps[$0].ex.id) })
            ?? steps.indices.first(where: { steps[$0].ex.id != st.ex.id && !isDone(steps[$0]) }) {
            rest = nil
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { idx = j; loadStep(steps) }
        }
        app.toast(String(localized: "\(st.ex.name) sona bırakıldı"))
    }
    private func complete(_ st: Step, _ steps: [Step]) {
        let r = Int(reps)
        let isPr = st.ex.unit == "tekrar" && WkPRShown.mark(date: date, name: st.ex.name, if: WkProgress.beatsPrevBest(ctx, name: st.ex.name, date: date, kg: kg, reps: r))
        Wk.setLog(ctx, date: date, eid: st.ex.id, index: st.si) { s in
            if st.ex.unit == "tekrar" { s.kg = kg > 0 ? kg : nil }   // 0 = bodyweight
            s.reps = r; s.done = true
        }
        // the entered weight is written to the program; later days open with it
        if st.ex.unit == "tekrar" { Wk.rememberLoad(prog, eid: st.ex.id, kg: kg) }
        if var c = clock ?? WkSessionClock.load(date) ?? ((day?.workoutSeconds ?? 0) == 0 ? WkSessionClock() : nil) {
            c.mark(); c.save(date); clock = c
        }
        haptic(.medium)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.55)) { pop += 1 }
        let p = pop
        Task { try? await Task.sleep(for: .milliseconds(520)); if pop == p { withAnimation { pop = 0 } } }
        if isPr { UINotificationFeedbackGenerator().notificationOccurred(.success); app.toast(String(localized: "Yeni rekor! \(st.ex.name)")) }
        let n = nextIdx(idx, steps)
        if n == -1 { timer = nil; rest = nil; withAnimation { finished = true }; loadPRs(); return }
        app.rt.restNext = String(localized: "\(steps[n].ex.name) · Set \(steps[n].si + 1)/\(steps[n].of)")
        if st.rest > 0 { rest = Countdown(end: Date().addingTimeInterval(Double(st.rest)), total: Double(st.rest)) }
        idx = n; loadStep(steps)
    }
    /// Edit sets and reps: saved straight to the program
    /// Set/rep change from the player: always written to the program
    private func applyPlan(_ st: Step, sets: Int? = nil, reps: Int? = nil) {
        guard let prog else { return }
        let eid = st.ex.id
        Wk.editBlocks(ctx, prog) { b in
            if let sets, let i = b.firstIndex(where: { $0.kind == .superset && $0.exs.contains { $0.id == eid } }) { b[i].rounds = sets }
            Wk.updateExercise(&b, eid: eid) { e in
                if let sets { e.sets = sets }
                if let reps { e.reps = reps }
            }
        }
        Store.save(ctx)
        app.toast(String(localized: "\(st.ex.name) programda güncellendi"))
    }

    private func planEditSheet(_ e0: SessionPlanEditValue) -> some View {
        PlanEditSheet(edit: e0) { e in
            guard let prog else { return }
            Wk.editBlocks(ctx, prog) { b in
                if e.superset, let i = b.firstIndex(where: { $0.kind == .superset && $0.exs.contains { $0.id == e.eid } }) {
                    b[i].rounds = Int(e.sets)
                    Wk.updateExercise(&b, eid: e.eid) { $0.reps = Int(e.reps); $0.sets = Int(e.sets) }
                } else {
                    Wk.updateExercise(&b, eid: e.eid) { $0.sets = Int(e.sets); $0.reps = Int(e.reps) }
                }
            }
            Store.save(ctx)
            let steps = buildSteps(prog)
            if idx >= steps.count { idx = max(0, nextIdx(-1, steps)) }
            loadStep(steps)
            app.toast(String(localized: "\(e.name) programda güncellendi"))
        }
    }

    private func pause(quiet: Bool = false) {
        if !quiet { haptic() }
        let t = Date()
        // can still pause before there's a clock (before the first set)
        var c = clock ?? WkSessionClock.load(date) ?? WkSessionClock()
        guard c.pausedAt == nil else { return }
        c.pause(t); c.save(date); clock = c; now = t
        if var r = rest, r.left == nil { r.left = max(0, r.end.timeIntervalSince(t)); rest = r }
        if var x = timer, x.left == nil { x.left = max(0, x.end.timeIntervalSince(t)); timer = x }
    }
    private func resume(quiet: Bool = false) {
        if !quiet { haptic() }
        let t = Date()
        if var c = clock, c.pausedAt != nil { c.resume(t); c.save(date); clock = c }
        if var r = rest, let l = r.left { r.end = t.addingTimeInterval(l); r.left = nil; rest = r }
        if var x = timer, let l = x.left { x.end = t.addingTimeInterval(l); x.left = nil; timer = x }
        now = t
    }
    /// The clock isn't written to state on every tick, so the player isn't redrawn twice a second
    private func onTick(_ t: Date) {
        if let r = rest, r.left == nil { RestAlarm.countdown(end: r.end, now: t) }
        if let x = timer, x.left == nil { RestAlarm.countdown(end: x.end, now: t) }
        // coming back from the background, no delayed second beep (the notification already came)
        if let r = rest, r.left == nil, r.end <= t { if t.timeIntervalSince(r.end) < 2 { beep() }; withAnimation(restEase) { rest = nil } }
        if let x = timer, x.left == nil, x.end <= t { if t.timeIntervalSince(x.end) < 2 { beep() }; timer = nil }
    }
    /// Live info for the mini player
    private func publishNow() {
        guard let prog else { return }
        let steps = buildSteps(prog)
        let step: Step? = idx >= 0 && idx < steps.count ? steps[idx] : nil
        let done = steps.filter(isDone).count
        let n = AppState.SessionNow(
            program: prog.name,
            exercise: finished ? tl("Antrenman bitti") : (step?.ex.name ?? prog.name),
            detail: rest != nil ? tl("Dinlenme") : (step.map { String(localized: "Set \($0.si + 1)/\($0.of)") } ?? ""),
            restEnd: rest?.left == nil ? rest?.end : nil, restTotal: rest?.total ?? 0,
            paused: clock?.pausedAt != nil, progress: Double(done) / Double(max(1, steps.count)),
            setText: step.map { String(localized: "Set \($0.si + 1)/\($0.of)") } ?? "",
            load: step.map { st in
                let r = "\(Int(reps)) \(tl(st.ex.unit))"
                return st.ex.unit == "tekrar" && kg > 0 ? "\(kg.formatted(.number.precision(.fractionLength(0...1)))) kg × \(Int(reps))" : r
            } ?? "",
            done: done, total: steps.count, finished: finished)
        if app.sessionNow != n { app.sessionNow = n }
        // live state to the watch
        if app.session != nil { LiveBridge.shared.publish(liveState()) }
    }
    /// Live state shared with the watch
    private func liveState() -> LiveState {
        LiveState(date: date, pid: pid, key: app.rt.stepKey, paused: clock?.pausedAt != nil,
                  restEnd: rest?.left == nil ? rest?.end : nil, restLeft: rest?.left, restTotal: rest?.total ?? 0,
                  kg: kg, reps: Int(reps), later: Array(later), finished: finished)
    }
    /// Applies live state from the watch; only for this day and program
    private func applyRemote(_ s: LiveState?) {
        guard let s, s.date == date, s.pid == pid, let prog else { return }
        let steps = buildSteps(prog)
        later = Set(s.later)
        if s.paused != (clock?.pausedAt != nil) { if s.paused { pause(quiet: true) } else { resume(quiet: true) } }
        if let k = s.key, let j = steps.firstIndex(where: { "\($0.ex.id)#\($0.si)" == k }), j != idx {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { idx = j; loadStep(steps) }
        }
        kg = s.kg
        if s.reps > 0 { reps = Double(s.reps) }
        if let e = s.restEnd { rest = Countdown(end: e, total: s.restTotal, left: nil) }
        else if let l = s.restLeft { rest = Countdown(end: Date().addingTimeInterval(l), total: s.restTotal, left: l) }
        else if rest != nil { withAnimation(restEase) { rest = nil } }
        if s.finished && !finished { timer = nil; rest = nil; withAnimation { finished = true }; loadPRs() }
        else if !s.finished && finished && !(day?.workoutDone ?? false) { withAnimation { finished = false } }
        // applied state isn't sent back to the watch (no echo loop)
        LiveBridge.shared.settle(liveState())
    }
    private func beep() { RestAlarm.beep() }
    private func loadPRs() { prs = WkProgress.prsOn(ctx, date) }

    private func save(_ prog: WorkoutProgram, elapsed: Int) {
        let steps = buildSteps(prog)
        if steps.allSatisfy(isDone) {
            Wk.completeWorkout(ctx, date: date, prog: prog)
        } else {
            // partial session: only exercises with every set done count as complete
            let doneIds = Set(prog.blocks.allExercises.map(\.id).filter { id in steps.filter { $0.ex.id == id }.allSatisfy(isDone) })
            Wk.completeWorkout(ctx, date: date, prog: prog, only: doneIds)
        }
        let L = Store.day(ctx, date)!
        let start = clock?.startedAt ?? Date().addingTimeInterval(-Double(elapsed))
        // active time already caps gaps; still, at most 4 hours are written
        let safe = min(clock?.total ?? elapsed, 4 * 3600)
        if L.workoutSeconds == 0 && safe > 0 {
            L.workoutSeconds = safe
            let profile = Store.profile(ctx)
            let kgBody = Store.latestWeight(ctx) ?? profile.startKg ?? 75
            let kcal = CalorieEngine.workoutKcal(minutes: Double(safe) / 60, weightKg: kgBody)
            L.workoutKcal = kcal
            // only today's session is written to Health (a past-dated session would land at the wrong time)
            // only that day's session, once per day (unmarking and redoing must not write twice)
            let hkKey = "wk.hk.\(date)"
            if safe > 60 && Date().timeIntervalSince(start) < 86_400 && (date == DayKey.today || DayKey.of(start) == date)
                && !L.hkSaved && !UserDefaults.standard.bool(forKey: hkKey) {
                // the flag is set once the write succeeds and syncs across devices via DayLog
                let from = max(start, Date().addingTimeInterval(-Double(safe)))
                Task { @MainActor in
                    if await health.saveStrengthWorkout(start: from, end: Date(), kcal: kcal) {
                        UserDefaults.standard.set(true, forKey: hkKey)
                        L.hkSaved = true
                        Store.save(ctx)
                    }
                }
            }
        }
        Store.save(ctx)
        WkSessionClock.clear(date)
        app.closeSession()
        app.toast("Antrenman kaydedildi")
        // ask for a rating once, after the 5th finished workout
        if !reviewAsked, ((try? ctx.fetchCount(FetchDescriptor<DayLog>(predicate: #Predicate { $0.workoutDone }))) ?? 0) >= 5 {
            reviewAsked = true
            Task { @MainActor in try? await Task.sleep(for: .seconds(1.5)); requestReview() }
        }
    }
}

/// Rest ring: decreases smoothly with the display refresh (no per-second jumps)
struct RestRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    let end: Date
    let total: Double
    var frozenLeft: Double?
    var size: CGFloat = 220
    /// "REST" above and "/ 1:30" below the time (player rest screen)
    var labeled = false
    /// The timeline stops when time is up (it kept running at 30 fps at 0)
    @State private var ended = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: frozenLeft != nil || ended)) { ctx in
            let left = max(0, frozenLeft ?? end.timeIntervalSince(ctx.date))
            let v = min(1, left / max(1, total))
            // last 3 seconds: the ring turns orange and pulses gently at the start of each second
            let hot = left > 0 && left <= 3
            let beat = hot && !reduce ? 1 + 0.04 * max(0, sin(.pi * 2 * (left.rounded(.up) - left))) : 1
            ZStack {
                Circle().stroke(Color.bFg.opacity(0.10), lineWidth: labeled ? 14 : 8)
                Circle().trim(from: 0, to: v)
                    // lime in the player; the last 3 s turn orange
                    .stroke(hot ? Color.orange : Color.bAction, style: StrokeStyle(lineWidth: labeled ? 14 : 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    if labeled { Text("DİNLENME").font(.geist(11, .medium, relativeTo: .caption2)).tracking(0.8).foregroundStyle(Color.bMutedFg) }
                    Text(Wk.mmss(Int(left.rounded(.up))))
                        .font(.bNum(size * 0.27, relativeTo: .largeTitle))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .foregroundStyle(hot ? Color.orange : Color.bFg)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy(duration: 0.25), value: Int(left.rounded(.up)))
                    if labeled { Text("/ \(Wk.mmss(Int(total)))").font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg) }
                }
            }
            .animation(.easeOut(duration: 0.25), value: hot)
            .padding(4)
            .frame(width: size, height: size)
            .scaleEffect(beat)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dinlenme")
            .accessibilityValue("\(Int(left.rounded(.up))) saniye kaldı")
        }
        .task(id: end) {
            ended = false
            let d = end.timeIntervalSinceNow
            if d > 0 { try? await Task.sleep(for: .seconds(d)) }
            if !Task.isCancelled { ended = true }
        }
    }
}

/// Music player button: shrinks when pressed with a soft circle behind it
struct MusicControlStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .background(Circle().fill(Color.bFg.opacity(c.isPressed ? 0.08 : 0)).scaleEffect(c.isPressed ? 1 : 0.6))
            .scaleEffect(c.isPressed ? 0.88 : 1)
            .opacity(enabled ? 1 : 0.3)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: c.isPressed)
            .contentShape(Circle())
    }
}


// MARK: - iPhone Duo fold (DUO_SDK: enabled with Xcode 27.1; no effect before)

enum DuoFold {
    /// Region of the fold while half-folded (view coordinates); nil when flat/closed
    static func region(_ g: GeometryProxy) -> CGRect? {
        #if DUO_SDK
        if #available(iOS 27.1, *) {
            return g.reservedRegions(kind: .division).first(where: { $0.isActive })?.frame
        }
        #endif
        return nil
    }
}

/// Passes the hinge region (when half-folded) to the content; recomputes when the state changes
struct DuoFoldReader<Content: View>: View {
    @ViewBuilder var content: (CGRect?) -> Content
    @State private var tick = 0
    var body: some View {
        GeometryReader { g in
            let _ = tick
            content(DuoFold.region(g))
        }
        .modifier(DuoHingeWatcher(tick: $tick))
    }
}

/// Refreshes the layout when the hinge state changes (open / half-fold / close)
struct DuoHingeWatcher: ViewModifier {
    @Binding var tick: Int
    func body(content: Content) -> some View {
        #if DUO_SDK
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, _ in tick &+= 1 }
        } else {
            content
        }
        #else
        content
        #endif
    }
}


/// Player top row: live elapsed time / estimated calories (only this small view refreshes every second)
private struct SessionLiveMetric: View {
    enum Kind { case time, kcal }
    let clock: WkSessionClock?
    let bodyKg: Double
    let kind: Kind
    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)) { t in
            let sec = clock?.elapsed(t.date) ?? 0
            Group {
                switch kind {
                case .time:
                    // brand color: lime capsule, dark text (readable in light mode too)
                    Text(Wk.mmss(sec)).foregroundStyle(Color.bActionFg)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(Color.bAction, in: Capsule())
                case .kcal:
                    (Text("\(Int(CalorieEngine.workoutKcal(minutes: Double(sec) / 60, weightKg: bodyKg).rounded()))")
                     + Text(" kcal").font(.system(size: 11, weight: .semibold)))
                        .foregroundStyle(Color.fitKcal)
                }
            }
            .font(.bNum(17, relativeTo: .headline))
            .contentTransition(.numericText())
            .accessibilityLabel(kind == .time ? "Geçen süre \(Wk.mmss(sec))" : "Tahmini kalori")
        }
    }
}


/// Edit sets and reps from the player
private struct PlanEditSheet: View {
    @State var edit: SessionPlanEditValue
    var onSave: (SessionPlanEditValue) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        BSheet(title: edit.name, description: "Değişiklik programa kaydedilir; sonraki antrenmanlar da bu değerlerle açılır.") {
            BField(label: edit.superset ? "Tur" : "Set") { BStepper(value: $edit.sets, step: 1, min: 1, max: 20, format: { fmt0($0) }) }
            BField(label: edit.unit == "tekrar" ? "Tekrar" : "Süre (\(edit.unit))") { BStepper(value: $edit.reps, step: 1, min: 1, max: 600, format: { fmt0($0) }) }
        } footer: {
            Button { onSave(edit); dismiss() } label: { BLabel("Kaydet") }.buttonStyle(.b(.primary, .large, full: true))
        }
        .presentationDetents([.medium])
    }
}
struct SessionPlanEditValue: Identifiable { var id: String { eid }; var eid: String; var name: String; var sets: Double; var reps: Double; var unit: String; var superset: Bool }


// MARK: - Machine taken → alternative exercises

struct WkAltTarget: Identifiable, Hashable {
    var eid: String; var name: String; var muscle: String; var unit: String; var done: Int; var canLater: Bool
    var id: String { eid }
}

/// Exercises that work the same area: different equipment first, ones you've done on top. 4 suggestions + the whole area.
struct WkAltSheet: View {
    let target: WkAltTarget
    let exclude: Set<String>
    let onPick: (_ name: String, _ muscle: String, _ alsoProgram: Bool) -> Void
    let onLater: () -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var all = false
    @State private var alsoProgram = false
    @State private var list: [ExerciseAlternatives.Candidate] = []
    @State private var region = ""
    @State private var last: [String: String] = [:]

    var body: some View {
        BSheet(title: "Alet dolu", description: String(localized: "\(target.name) yerine aynı bölgeyi çalıştıran hareketler") + (region.isEmpty ? "" : " · \(region)")) {
            if list.isEmpty {
                Text("Bu hareket için kütüphanede alternatif bulunamadı. Sona bırakıp sonra yapabilirsin.")
                    .font(.bSm).foregroundStyle(Color.bMutedFg).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                WkListCard {
                    ForEach(all ? list : Array(list.prefix(4)), id: \.name) { c in
                        Button { haptic(); onPick(c.name, c.muscle, alsoProgram); dismiss() } label: {
                            HStack(spacing: 12) {
                                WkThumb(name: c.name, size: 48)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(c.name).font(.geist(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Color.bFg).lineLimit(1)
                                    HStack(spacing: 6) {
                                        BBadge(variant: .outline) { Text(Self.label(c.equipment)) }
                                        Text(last[TextNorm.norm(c.name)] ?? c.alias ?? "").font(.bXs).foregroundStyle(Color.bMutedFg).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Ti("chevron-right", size: 16).foregroundStyle(Color.bMutedFg)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.press)
                        .accessibilityLabel("\(c.name), \(Self.label(c.equipment))")
                    }
                }
                if !all && list.count > 4 {
                    Button { withAnimation(.snappy) { all = true } } label: {
                        Text("Tüm \(region.lowercased(with: Locale(identifier: "tr_TR"))) hareketleri (\(list.count))").font(.bSm)
                    }
                    .buttonStyle(.b(.ghost, .small)).frame(maxWidth: .infinity)
                }
                Toggle(isOn: $alsoProgram) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Programda da değiştir").font(.geist(15, .medium))
                        Text("Kapalıyken yalnız bugünkü antrenman değişir.").font(.bXs).foregroundStyle(Color.bMutedFg)
                    }
                }
                .tint(Color.bPrimary).padding(.top, 4)
            }
        } footer: {
            if target.canLater {
                Button { onLater(); dismiss() } label: { BLabel("Sona bırak, sonra yap", icon: "player-skip-forward") }
                    .buttonStyle(.b(.secondary, .large, full: true))
            }
        }
        .task {
            let lib = WkLibrary.shared.exercises.map { ExerciseAlternatives.Candidate(name: $0.name, alias: $0.tr.first, muscle: $0.muscle, unit: $0.unit) }
            let hist = WkProgress.histories(ctx)
            let r = ExerciseAlternatives.rank(current: target.name, muscle: target.muscle, unit: target.unit, library: lib,
                                              done: Set(hist.keys), exclude: exclude)
            list = r
            region = r.first?.muscle ?? target.muscle
            var m: [String: String] = [:]
            for c in r.prefix(12) {
                if let s = hist[TextNorm.norm(c.name)]?.last {
                    m[TextNorm.norm(c.name)] = s.best.kg > 0 ? String(localized: "Son: \(fmt1(s.best.kg)) kg × \(s.best.reps)") : String(localized: "Son: \(s.best.reps) tekrar")
                }
            }
            last = m
        }
    }

    static func label(_ e: ExerciseAlternatives.Equipment) -> String {
        switch e {
        case .barbell: tl("Bar")
        case .dumbbell: tl("Dambıl")
        case .kettlebell: tl("Kettlebell")
        case .cable: tl("Kablo")
        case .machine: tl("Makine")
        case .band: tl("Lastik")
        case .bodyweight: tl("Vücut ağırlığı")
        case .other: tl("Diğer")
        }
    }
}



/// Player background: canvas + the same top wash as the tabs
private struct SessionBackdrop: View {
    var body: some View {
        ZStack(alignment: .top) { Color.bBg; BWash(style: .dominant) }.ignoresSafeArea()
    }
}
