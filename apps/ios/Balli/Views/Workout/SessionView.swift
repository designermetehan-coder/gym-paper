import SwiftUI
import SwiftData
import AudioToolbox
import Combine
import BalliKit
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

    /// Yalnız bu program ve bu gün yüklenir; her set kaydında bütün geçmiş yeniden sorgulanmaz (PF-03)
    init(pid: String, date: String) {
        self.pid = pid; self.date = date
        _programs = Query(filter: #Predicate<WorkoutProgram> { $0.pid == pid }, sort: \WorkoutProgram.createdAt)
        _days = Query(filter: #Predicate<DayLog> { $0.date == date })
    }

    private struct Step { var ex: Exercise; var si: Int; var of: Int; var rest: Int; var label: String; var ssRound: Int?; var ssRounds: Int?; var tag: String? }
    private typealias Countdown = SessionCountdown
    static let kgValues: [Double] = Array(stride(from: 0.0, through: 500.0, by: 0.5))
    static let repValues: [Double] = Array(stride(from: 0.0, through: 100.0, by: 1.0))

    // Çalışma durumu AppState'te: sheet kapanıp açılınca (küçült/büyüt) kaybolmaz
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
    /// Vücut ağırlığı bir kez okunur; özet ekranı saniyede veritabanı sorgulamasın (QA-14)
    @State private var bodyKg: Double = 75
    /// Oynatıcının altındaki antrenman sırası açık mı
    @State private var queueOpen = false
    /// Oynatıcıdan set/tekrar düzenleme; programa kaydedilir (4 Kas)
    @State private var planEdit: SessionPlanEditValue?
    /// Alet dolu olduğu için sona bırakılan hareketler (P-02); sıra önce diğerlerini dolaşır
    @State private var later: Set<String> = []
    @Environment(\.horizontalSizeClass) private var hsc
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// Dinlenme → sıradaki set geçişi: dinlenme küçülüp solar, oynatıcı hafif yükselerek gelir (MO-I2)
    private var restOut: AnyTransition { reduce ? .opacity : .asymmetric(insertion: .opacity, removal: .scale(scale: 0.72).combined(with: .opacity)) }
    private var stepIn: AnyTransition { reduce ? .opacity : .asymmetric(insertion: .offset(y: 14).combined(with: .opacity), removal: .opacity) }
    private let restEase = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.35)
    /// iPhone Duo menteşe durumu değişince yerleşim yeniden hesaplansın
    @State private var hingeTick = 0
    /// Adım değişince bir kez hesaplanır (gövdede değil — WK-05)
    @State private var stepPrev: Wk.Lifted?
    @State private var stepSug: WkProgress.Suggestion?
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var prog: WorkoutProgram? { programs.first { $0.pid == pid } }
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
        // Listedeki işaret iki yönde de geçerli: kaldırılmışsa (false) setler yapılmamış sayılır (QA-01)
        if let f = d.exDone[s.ex.id] { return f }
        let a = d.sets[s.ex.id] ?? []
        return s.si < a.count && a[s.si].done
    }

    var body: some View {
        Group {
            if let prog { content(prog, steps: buildSteps(prog)) } else { Color.bBg.onAppear { app.closeSession() } }
        }
        .background(Color.bBg.ignoresSafeArea())
        .onReceive(tick) { t in onTick(t) }
        .onChange(of: app.sessionMin) { _, m in if m { publishNow() } }
        .onAppear { app.rt.use(pid + date); UIApplication.shared.isIdleTimerDisabled = true; publishNow() }
        // Kilit ekranı / Dynamic Island güncel kalsın
        .onChange(of: app.rt.idx) { publishNow() }
        .onChange(of: app.rt.rest) { publishNow() }
        .onChange(of: app.rt.finished) { publishNow() }
        .onChange(of: app.rt.kg) { publishNow() }
        .onChange(of: app.rt.reps) { publishNow() }
        .onChange(of: clock?.pausedAt) { publishNow() }
        .onChange(of: prog.map { buildSteps($0).map { "\($0.ex.id)\($0.si)" }.joined() }) { _, _ in
            guard let prog, idx >= 0 else { return }
            let st = buildSteps(prog)
            // Adımı kimliğiyle yeniden bul; bulunamazsa ilk yapılmamış adıma geç (QA-07)
            if let k = app.rt.stepKey, let j = st.firstIndex(where: { "\($0.ex.id)#\($0.si)" == k }) {
                if j != idx { idx = j; loadStep(st) } else { loadHints(st[j]) }
            } else {
                idx = max(0, st.firstIndex { !isDone($0) } ?? 0); loadStep(st)
            }
        }
        .onDisappear { if app.session != nil { publishNow() }; UIApplication.shared.isIdleTimerDisabled = false }
        // Figma ekran görüntüleri (-session -shot …)
        .shot("session.rest", delay: 2.5) { if let p = prog { let st = buildSteps(p); if st.indices.contains(idx) { complete(st[idx], st) } } }
        .shot("session.paused", delay: 2.5) { pause() }
        .shot("session.done", delay: 2.5) { timer = nil; rest = nil; withAnimation { finished = true }; loadPRs() }
        .shot("session.queue", delay: 2.5) { queueOpen = true }
        .shot("session.edit", delay: 2.5) {
            if let p = prog { let st = buildSteps(p); if st.indices.contains(idx) { let c = st[idx]
                planEdit = SessionPlanEditValue(eid: c.ex.id, name: c.ex.name, sets: Double(c.ssRounds ?? c.ex.sets), reps: Double(c.ex.reps), unit: c.ex.unit, superset: c.ssRounds != nil) } }
        }
    }

    @ViewBuilder private func content(_ prog: WorkoutProgram, steps: [Step]) -> some View {
        let doneCount = steps.filter(isDone).count
        let paused = clock?.pausedAt != nil
        let elapsed = (day?.workoutSeconds ?? 0) > 0 ? day!.workoutSeconds : (finished ? (clock?.total ?? 0) : (clock?.elapsed(now) ?? 0))
        let step: Step? = idx >= 0 && idx < steps.count ? steps[idx] : nil
        VStack(spacing: 0) {
            Capsule().fill(Color.bFg.opacity(0.25)).frame(width: 40, height: 5).padding(.top, 8)
                .accessibilityHidden(true)
            // Üst bilgi (müzik çalardaki gibi yalnız tutamaç + küçük bilgi; menü başlığın yanında)
            let inStep = !steps.isEmpty && !finished && !paused && rest == nil && step != nil
            // Apple Fitness gibi: solda geçen süre (sarı), sağda yakılan kalori (kırmızı) — canlı
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

            if steps.isEmpty {
                VStack(spacing: 16) {
                    Text("Bu programda hareket yok").font(.geist(18, .semibold))
                    Button("Kapat") { app.closeSession() }.buttonStyle(.b(.outline))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if finished {
                finishView(prog, steps: steps, doneCount: doneCount, elapsed: elapsed)
            // Duraklatınca özet ekranı açılmaz: oynatıcıda kalınır, durdur düğmesi oynat'a döner (4 Kas)
            } else if let r = rest {
                VStack(spacing: 32) {
                    Text("DİNLENME").font(.geist(14, .medium, relativeTo: .subheadline)).tracking(0.8).foregroundStyle(Color.bMutedFg)
                    RestRing(end: r.end, total: r.total, frozenLeft: r.left)
                    HStack(spacing: 8) {
                        Button { rest = Countdown(end: r.end.addingTimeInterval(15), total: r.total + 15, left: r.left.map { $0 + 15 }) } label: { BLabel("+15 sn") }
                            .buttonStyle(.b(.outline, .large))
                        // Dinlenmeyi duraklat / sürdür
                        Button {
                            haptic()
                            if let l = r.left { rest = Countdown(end: Date().addingTimeInterval(l), total: r.total, left: nil) }
                            else { rest = Countdown(end: r.end, total: r.total, left: max(0, r.end.timeIntervalSinceNow)) }
                        } label: {
                            Image(systemName: r.left == nil ? "pause.fill" : "play.fill").font(.system(size: 18, weight: .semibold))
                        }
                        .buttonStyle(.b(.outline, .iconLarge)).frame(height: 48)
                        .accessibilityLabel(r.left == nil ? "Dinlenmeyi duraklat" : "Dinlenmeye devam et")
                        Button { withAnimation(restEase) { rest = nil } } label: { BLabel("Atla") }.buttonStyle(.b(.primary, .large))
                    }
                    if let step {
                        VStack(spacing: 2) {
                            Text("Sıradaki").font(.bXs).foregroundStyle(Color.bMutedFg)
                            Text("\(step.ex.name) · Set \(step.si + 1)").font(.geist(16, .medium))
                        }
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
        // Dinlenme bitince sert bir tık: sıradaki sete geçildiği bileğe/ele hissedilir (MO-I2)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.8), trigger: rest == nil) { old, new in !old && new }
    }

    /// Seans menüsü (⋯)
    private func sessionMenu(_ steps: [Step]) -> some View {
        return Menu {
            // Alet dolu, başka harekete geç ve set/tekrar düzenleme oynatıcının kendisinde (4 Kas)
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

    /// Oynatıcı + altında antrenman sırası. Elle kaydırma kapalı; yalnız "Sıradaki" düğmesi sıraya kaydırır.
    private func stepView(_ step: Step, steps: [Step]) -> some View {
        ScrollViewReader { sp in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    playerPage(step, steps: steps)
                        .containerRelativeFrame(.vertical)
                        .id("player")
                    // Sıra yalnız "Sıradaki"ye basınca görünür; altta ipucu gibi görünmesin
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

    /// Antrenman sırası: hareket başına tamamlanan set; dokununca o harekete geçer
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

    /// Apple Music çalar düzeni: büyük kapak, solda başlık + ⋯, set çubuğu, girişler, önceki · duraklat · tamamla, alt satır
    @ViewBuilder private func playerPage(_ step: Step, steps: [Step]) -> some View {
        // iPhone Duo: yarı katlıyken katlama çizgisinin iki yanına ayrılır; düz açıkken iPhone düzeni
        GeometryReader { g in
            let _ = hingeTick
            let fold = DuoFold.region(g)
            if let fold, fold.width < fold.height {
                // Kitap pozu: dikey katlama — görsel bir sayfada, kontroller diğerinde
                HStack(spacing: 0) {
                    playerCover(step).frame(width: max(0, fold.minX)).frame(maxHeight: .infinity)
                    Color.clear.frame(width: fold.width)
                    playerDetails(step, steps: steps).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let fold {
                // Masa / stand pozu: yatay katlama — görsel üstte, kontroller altta
                VStack(spacing: 0) {
                    playerCover(step).frame(height: max(0, fold.minY))
                    Color.clear.frame(height: fold.height)
                    playerDetails(step, steps: steps).frame(maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    // Geniş ama dar oranlı alanda (Split View) kapak kontrolleri aşağı itmesin
                    // Kısa ekranlarda (Duo dış ekranı) kapak küçülür; alt satır sığsın
                    // Her ekranda iPhone düzeni (Duo iç ekranı dahil): üstte kapak, altında kontroller; geniş ekranda sütun 560 pt (2 Kas)
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
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.bMuted)
                            .overlay(Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 72)).foregroundStyle(Color.bMutedFg.opacity(0.5)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            // Başlık + ⋯
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.ex.name).font(.bDisplay(22, relativeTo: .title2)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(subtitle(step)).font(.geist(17, relativeTo: .body)).foregroundStyle(Color.bMutedFg).lineLimit(1)
                }
                Spacer(minLength: 0)
                sessionMenu(steps)
            }
            .padding(.horizontal, 24)

            // Set çubuğu
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

            // Girişler
            Group {
                if step.ex.unit == "tekrar" {
                    HStack(spacing: 8) {
                        BPickField(label: "Kilo", value: kgB, values: Self.kgValues, suffix: "kg", zeroText: "–")
                        // Tekrar ve set de kilo gibi dokununca düzenlenir; değişiklik programa kaydolur (4 Kas)
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

            // Kontroller: önceki · duraklat (ortada) · seti tamamla ve sonrakine geç; son sette sağdaki düğme yeşil "bitir" olur
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

            // Alt satır: öneri · sıradaki (hareket listesi) · alet dolu (4 Kas: form videosu kaldırıldı, üstteki iki ikon buraya taşındı)
            HStack(spacing: 0) {
                if let sug { Button { haptic(); kg = sug.kg } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "sparkles").font(.system(size: 20))
                        Text("Öneri \(fmt1(sug.kg)) kg").font(.geist(11, .medium, relativeTo: .caption2)).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .disabled(sug.kg == kg).accessibilityLabel("Önerilen kiloyu yaz") }
                Button { haptic(); queueOpen = true } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "list.bullet").font(.system(size: 20))
                        Text(upcoming.map { $0.ex.name == step.ex.name ? String(localized: "Sıradaki: Set \($0.si + 1)") : String(localized: "Sıradaki: \($0.ex.name)") } ?? String(localized: "Son set"))   // TE-10
                            .font(.geist(11, .medium, relativeTo: .caption2)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .accessibilityLabel("Başka harekete geç: antrenman sırasını göster")
                // Alet dolu: bu hareketi sona bırak, sıradakine geç (P-02); form videosu yerine (4 Kas)
                Button { postpone(step, steps) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "hourglass").font(.system(size: 20))   // alet dolu: bekle, sonra yap
                        Text("Alet dolu").font(.geist(11, .medium, relativeTo: .caption2)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .disabled(!others).opacity(others ? 1 : 0.4)
                .accessibilityLabel("Alet dolu, bu hareketi sona bırak")
            }
            .foregroundStyle(Color.bMutedFg)
            .buttonStyle(.press)
            // Köşesi yuvarlak ekranlarda alt satır kırpılmasın
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

    /// Duraklatma ve bitiş ekranı: başlıkta özet, satır satır tablo (solda başlık, sağda kalın değer), düğmeler altta
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
        // Duraklatmada tahmini kalori ve en ağır set yazılmaz (GP-03)
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
                        // Bitişte kupa küçükten %15 aşarak patlar (MO-I5)
                        .modifier(BPopIn(from: mode == .finished ? 0.3 : 1))
                        .padding(.top, 24)
                        .onAppear { if mode == .finished { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
                    VStack(spacing: 4) {
                        Text(mode == .finished ? "Antrenman bitti" : "Duraklatıldı").font(.b2xl)
                        Text(prog.name).foregroundStyle(Color.bMutedFg)
                    }
                    // İlerleme halkası
                    BRing(value: Double(doneCount) / Double(max(1, steps.count)), size: 88, stroke: 8) {
                        Text("%\(Int((Double(doneCount) / Double(max(1, steps.count)) * 100).rounded()))").font(.bNum(18))
                    }
                    // Özet satırları: solda başlık (ikincil), sağda değer (birincil) — GP-01
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
                            // Kutucuklar 50 ms arayla yükselir (MO-I5)
                            .modifier(BRise(index: i, step: 0.05, base: 0.22, maxIndex: 8))
                        }
                    }
                    .bCard(padding: 0)
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
                                .background(Color.bPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .modifier(BPopIn(delay: 0.6 + Double(k) * 0.08, from: 0.8))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
            // Düğmeler altta sabit
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
        // Konfeti kaldırıldı (4 Kas): bitiş özeti sade kalır
        .onAppear { if mode == .finished { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    }

    // MARK: - Mantık

    private func start(_ steps: [Step]) {
        bodyKg = Store.latestWeight(ctx) ?? Store.profile(ctx).startKg ?? 75
        // Saat kalıcı (UserDefaults): küçült/büyüt sonrası görünüm yeniden kurulunca da geri yüklenir (WK-01)
        if clock == nil {
            // Süre oynatıcı açılınca başlar (sol üstteki sayaç hemen işlesin)
            if var c = WkSessionClock.load(date) {
                if !c.started && c.pausedAt == nil { c.begin(); c.save(date) }
                clock = c
            } else if (day?.workoutSeconds ?? 0) == 0 { var c = WkSessionClock(); c.begin(); c.save(date); clock = c }
        }
        guard idx < 0 else {
            // Program seans sırasında değiştiyse geçerli bir adıma dön (WK-05, QA-07)
            if let k = app.rt.stepKey, let j = steps.firstIndex(where: { "\($0.ex.id)#\($0.si)" == k }), j != idx { idx = j; loadStep(steps) }
            else if idx >= steps.count || steps.isEmpty { idx = max(0, steps.firstIndex { !isDone($0) } ?? 0); loadStep(steps) }
            else { loadHints(steps[idx]) }
            // Dışarıdan işaret kaldırıldıysa bitiş ekranında takılı kalma
            if finished && (day?.workoutSeconds ?? 0) == 0 && !steps.isEmpty && !steps.contains(where: isDone) { finished = false }
            if finished { loadPRs() }
            return
        }
        idx = max(0, steps.firstIndex { !isDone($0) } ?? 0)
        finished = !steps.isEmpty && steps.allSatisfy(isDone)
        if finished { loadPRs() }
        loadStep(steps)
    }
    /// "son X kg" ve öneri satırları (görünüm her açıldığında tazelenir — WK-04)
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
        // Önce sona bırakılmamış hareketler; onlar bitince bırakılanlara dönülür (P-02)
        for k in 1..<max(1, steps.count) { let i = (from + k) % steps.count; if !isDone(steps[i]) && !later.contains(steps[i].ex.id) { return i } }
        for k in 1..<max(1, steps.count) { let i = (from + k) % steps.count; if !isDone(steps[i]) { return i } }
        return -1
    }
    /// Alet dolu: hareketi sona bırakır, sıradaki farklı harekete geçer (P-02)
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
            if st.ex.unit == "tekrar" { s.kg = kg > 0 ? kg : nil }   // 0 = vücut ağırlığı (QA-12)
            s.reps = r; s.done = true
        }
        // Girilen kilo programa yazılır; sonraki günler bu kiloyla açılır (4 Kas)
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
    /// Set ve tekrar düzenleme: değişiklik doğrudan programa kaydedilir (4 Kas)
    /// Oynatıcıdan set/tekrar değişikliği: her zaman programa yazılır (GP-05, 4 Kas)
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

    private func pause() {
        haptic(); let t = Date()
        // Saat henüz yoksa (ilk setten önce) yine de duraklatılabilsin
        var c = clock ?? WkSessionClock.load(date) ?? WkSessionClock()
        guard c.pausedAt == nil else { return }
        c.pause(t); c.save(date); clock = c; now = t
        if var r = rest, r.left == nil { r.left = max(0, r.end.timeIntervalSince(t)); rest = r }
        if var x = timer, x.left == nil { x.left = max(0, x.end.timeIntervalSince(t)); timer = x }
    }
    private func resume() {
        haptic(); let t = Date()
        if var c = clock, c.pausedAt != nil { c.resume(t); c.save(date); clock = c }
        if var r = rest, let l = r.left { r.end = t.addingTimeInterval(l); r.left = nil; rest = r }
        if var x = timer, let l = x.left { x.end = t.addingTimeInterval(l); x.left = nil; timer = x }
        now = t
    }
    /// Saat her tikte state'e yazılmaz: oynatıcı saniyede 2 kez baştan çizilmesin (PF-01)
    private func onTick(_ t: Date) {
        // Arka plandan dönünce gecikmiş ikinci bip çalmasın (bildirim zaten geldi) — QA-10
        if let r = rest, r.left == nil, r.end <= t { if t.timeIntervalSince(r.end) < 2 { beep() }; withAnimation(restEase) { rest = nil } }
        if let x = timer, x.left == nil, x.end <= t { if t.timeIntervalSince(x.end) < 2 { beep() }; timer = nil }
    }
    /// Mini oynatıcı için anlık bilgi
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
    }
    private func beep() { RestAlarm.beep() }
    private func loadPRs() { prs = WkProgress.prsOn(ctx, date) }

    private func save(_ prog: WorkoutProgram, elapsed: Int) {
        let steps = buildSteps(prog)
        if steps.allSatisfy(isDone) {
            Wk.completeWorkout(ctx, date: date, prog: prog)
        } else {
            // Yarım seans: yalnız bütün setleri yapılan hareketler tamamlandı sayılır (WK-09)
            let doneIds = Set(prog.blocks.allExercises.map(\.id).filter { id in steps.filter { $0.ex.id == id }.allSatisfy(isDone) })
            Wk.completeWorkout(ctx, date: date, prog: prog, only: doneIds)
        }
        let L = Store.day(ctx, date)!
        let start = clock?.startedAt ?? Date().addingTimeInterval(-Double(elapsed))
        // Aktif süre zaten boşlukları sınırlıyor; yine de en çok 4 saat yazılır
        let safe = min(clock?.total ?? elapsed, 4 * 3600)
        if L.workoutSeconds == 0 && safe > 0 {
            L.workoutSeconds = safe
            let profile = Store.profile(ctx)
            let kgBody = Store.latestWeight(ctx) ?? profile.startKg ?? 75
            let kcal = CalorieEngine.workoutKcal(minutes: Double(safe) / 60, weightKg: kgBody)
            L.workoutKcal = kcal
            // Sağlık'a yalnız bugünün seansı yazılır (geçmiş tarihli seans yanlış zamana düşmesin)
            // Yalnız o günün seansı ve gün başına bir kez (işaret kaldırıp yeniden yapınca çift yazılmasın — QA-04/05)
            let hkKey = "wk.hk.\(date)"
            if safe > 60 && Date().timeIntervalSince(start) < 86_400 && (date == DayKey.today || DayKey.of(start) == date)
                && !L.hkSaved && !UserDefaults.standard.bool(forKey: hkKey) {
                // İşaret yazma başarılı olunca konur ve DayLog ile cihazlar arası eşitlenir (CR-22)
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
        // 5. tamamlanan antrenmandan sonra bir kez puanlama istenir (IY-02)
        if !reviewAsked, ((try? ctx.fetchCount(FetchDescriptor<DayLog>(predicate: #Predicate { $0.workoutDone }))) ?? 0) >= 5 {
            reviewAsked = true
            Task { @MainActor in try? await Task.sleep(for: .seconds(1.5)); requestReview() }
        }
    }
}

/// Dinlenme halkası: ekran yenilemesiyle akıcı azalır (saniyelik sıçrama yok)
struct RestRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    let end: Date
    let total: Double
    var frozenLeft: Double?
    var size: CGFloat = 220
    /// Süre bitince zaman çizelgesi durur; 0'da saniyede 30 kare akmaya devam ediyordu (CR-06)
    @State private var ended = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: frozenLeft != nil || ended)) { ctx in
            let left = max(0, frozenLeft ?? end.timeIntervalSince(ctx.date))
            let v = min(1, left / max(1, total))
            // Son 3 saniye: halka turuncuya döner ve her saniye başında hafifçe nabız atar (MO-I2)
            let hot = left > 0 && left <= 3
            let beat = hot && !reduce ? 1 + 0.04 * max(0, sin(.pi * 2 * (left.rounded(.up) - left))) : 1
            ZStack {
                Circle().stroke(Color.bFg.opacity(0.10), lineWidth: 8)
                Circle().trim(from: 0, to: v)
                    .stroke(hot ? Color.orange : Color.bPrimary, style: StrokeStyle(lineWidth: 8, lineCap: .round))   // ana renk; son 3 sn turuncu (MO-I2) (siyaha yakın / koyuda kırık beyaz), lime değil (2 Kas)
                    .rotationEffect(.degrees(-90))
                Text(Wk.mmss(Int(left.rounded(.up))))
                    .font(.bNum(size * 0.27, relativeTo: .largeTitle))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(hot ? Color.orange : Color.bFg)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.25), value: Int(left.rounded(.up)))
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

/// Müzik çalar düğmesi: basınca küçülür ve arkasında yumuşak daire belirir
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


// MARK: - iPhone Duo katlama (DUO_SDK: Xcode 27.1 ile açılır; öncesinde etkisiz)

enum DuoFold {
    /// Yarı katlıyken katlama çizgisinin bölgesi (görünüm koordinatlarında); düz/kapalıyken nil
    static func region(_ g: GeometryProxy) -> CGRect? {
        #if DUO_SDK
        if #available(iOS 27.1, *) {
            return g.reservedRegions(kind: .division).first(where: { $0.isActive })?.frame
        }
        #endif
        return nil
    }
}

/// Menteşe durumu değişince (aç / yarı katla / kapat) yerleşimi tazeler
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


/// Oynatıcı üst satırı: canlı geçen süre / tahmini kalori (yalnız bu küçük görünüm saniyede bir yenilenir)
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
                    // Marka rengi: lime kapsül, koyu yazı (açık temada da okunur — GP-04)
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


/// Antrenman bitince bir kez patlayan konfeti (GP-05). Erişilebilirlikte "hareketi azalt" açıksa gösterilmez.
struct ConfettiBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    private struct Piece { let x: Double; let vx: Double; let vy: Double; let spin: Double; let color: Color; let w: Double; let h: Double; let delay: Double }
    private static let colors: [Color] = [.bAction, .fitKcal, .fitBlue, .fitPurple, .fitTime, .fitGreen]
    @State private var pieces: [Piece] = (0..<90).map { _ in
        Piece(x: Double.random(in: 0.3...0.7), vx: Double.random(in: -0.55...0.55), vy: Double.random(in: -1.25 ... -0.7),
              spin: Double.random(in: -9...9), color: ConfettiBurst.colors.randomElement()!, w: Double.random(in: 6...10), h: Double.random(in: 10...16),
              delay: Double.random(in: 0...0.25))
    }
    private let life: Double = 3.2
    /// Süre dolunca zaman çizelgesi durur; bitiş ekranı açık kaldıkça kare çizilmez
    @State private var done = false
    var body: some View {
        if reduceMotion || done { Color.clear } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
                let t0 = tl.date.timeIntervalSince(start)
                Canvas { c, size in
                    for p in pieces {
                        let t = max(0, t0 - p.delay)
                        guard t > 0 else { continue }
                        // Yukarı fırlar, yerçekimiyle düşer; sona doğru solar
                        let x = (p.x + p.vx * t * 0.6) * size.width
                        let y = size.height * 0.42 + (p.vy * t + 0.9 * t * t) * size.height * 0.5
                        let alpha = max(0, min(1, (life - t) / 0.8))
                        var ctx = c
                        ctx.opacity = alpha
                        ctx.translateBy(x: x, y: y)
                        ctx.rotate(by: .radians(p.spin * t))
                        ctx.scaleBy(x: 1, y: abs(cos(p.spin * t * 0.7)) * 0.8 + 0.2)
                        ctx.fill(Path(roundedRect: CGRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h), cornerRadius: 2), with: .color(p.color))
                    }
                }
            }
            .onAppear { start = Date() }
            .task { try? await Task.sleep(for: .seconds(life + 0.4)); done = true }
            .accessibilityHidden(true)
        }
    }
}

/// Oynatıcıdan set ve tekrar düzenleme sayfası (4 Kas)
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
