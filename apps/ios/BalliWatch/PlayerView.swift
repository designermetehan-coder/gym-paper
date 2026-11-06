import SwiftUI
import SwiftData
import WatchKit
import BalliKit

/// Antrenman oynatıcısı — iPhone oynatıcısının saat sürümü:
/// hareket görseli, set çubuğu, son set ve öneri, kilo (Digital Crown), tekrar/set, önceki · duraklat · tamamla,
/// dinlenme halkası, antrenman sırası, duraklatma ve bitiş özeti.
struct PlayerView: View {
    let pid: String
    let date: String
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchWorkout.self) private var wk
    @Query private var programs: [WorkoutProgram]
    @Query private var days: [DayLog]
    @State private var idx = -1
    /// Kilo ve tekrar ayrı gözlenen nesnede: Digital Crown her adımda yalnız kadranı çizer, tüm oynatıcıyı değil (WQ-01)
    @State private var input = WInput()
    @Environment(\.isLuminanceReduced) private var dimmed
    @State private var restEnd: Date?
    @State private var restTotal: Double = 60
    @State private var restLeft: Double?          // dinlenme duraklatıldıysa kalan
    @State private var timerEnd: Date?             // süreli hareket (sn)
    @State private var timerTotal: Double = 30
    @State private var paused = false
    @State private var finished = false
    @State private var saving = false
    @State private var showQueue = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var flagTick = 0
    /// Set → dinlenme → sıradaki set: ekranlar yatay itilerek değişir (MO-S3)
    private var push: AnyTransition { reduce ? .opacity : .push(from: .trailing) }
    private let flow = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.35)

    /// Yalnız DEBUG ekran görüntüsü modu: "rest" | "paused" | "summary" (WatchShots)
    var shot: String? = nil

    init(pid: String, date: String, shot: String? = nil) {
        self.pid = pid; self.date = date; self.shot = shot
        _programs = Query(filter: #Predicate<WorkoutProgram> { $0.pid == pid })
        _days = Query(filter: #Predicate<DayLog> { $0.date == date })
    }

    private var prog: WorkoutProgram? { programs.first }
    private var day: DayLog? { days.day(date) }

    var body: some View {
        Group {
            if let prog {
                let steps = WLogic.steps(prog)
                if steps.isEmpty {
                    Text("Bu programda hareket yok").foregroundStyle(.secondary)
                } else if finished {
                    summary(prog, steps: steps, finished: true)
                } else if paused {
                    summary(prog, steps: steps, finished: false)
                } else if restEnd != nil || restLeft != nil {
                    restView(next: idx >= 0 && idx < steps.count ? steps[idx] : nil)
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
        // Başlık yok: ekranın sağında tek başına duran program adı yer kaplıyordu; adı içerik gösteriyor
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: start)
        .sheet(isPresented: $showQueue) {
            if let prog { queueView(WLogic.steps(prog)) }
        }
        // Dinlenme bitince titreşim (antrenman oturumu sayesinde ekran kapalıyken de çalar)
        .task(id: restEnd) {
            guard let end = restEnd else { return }
            let left = end.timeIntervalSinceNow
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            guard !Task.isCancelled, restEnd == end else { return }
            WKInterfaceDevice.current().play(.stop)
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

    // MARK: Oynatıcı

    @ViewBuilder private func stepPage(_ s: WStep, steps: [WStep]) -> some View {
        let next = nextIdx(steps)
        let upcoming = next.map { steps[$0] }
        let last = PhoneSync.shared.lastKg[s.ex.id]
        let lastReps = PhoneSync.shared.lastReps[s.ex.id]
        let sug = PhoneSync.shared.sugKg[s.ex.id]
        ScrollView {
            VStack(spacing: 8) {
                statusRow(steps)
                // Kapak: hareket görseli
                cover(s.ex.name)

                // Başlık
                VStack(spacing: 1) {
                    Text(s.ex.name).font(.headline.weight(.bold).italic()).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.75)
                    Text(subtitle(s)).font(.footnote).foregroundStyle(.secondary)
                }

                // Set çubuğu + son set
                VStack(spacing: 3) {
                    ProgressView(value: Double(s.si), total: Double(max(1, s.of)))
                        .progressViewStyle(.linear).tint(Color.wInk)
                    HStack {
                        Text("Set \(s.si + 1)")
                        Spacer(minLength: 2)
                        if let last, last > 0 { Text("son \(last.kgText) kg × \(lastReps ?? s.ex.reps)").lineLimit(1).minimumScaleFactor(0.7) }
                        Spacer(minLength: 2)
                        Text("\(s.of) set")
                    }
                    .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                }

                // Girişler: yalnız kilo değişir
                if s.ex.unit == "tekrar" {
                    WKgDial(input: input, sug: sug)
                    HStack(spacing: 6) {
                        tile("Tekrar", "\(input.reps)")
                        tile("Set", "\(s.si + 1)/\(s.of)")
                    }
                } else if s.ex.unit == "sn" {
                    if let end = timerEnd {
                        ring(end: end, total: timerTotal, size: 76)
                    } else {
                        Button {
                            timerTotal = Double(max(1, s.ex.reps)); timerEnd = Date().addingTimeInterval(timerTotal)
                            WKInterfaceDevice.current().play(.start)
                        } label: {
                            Label("\(Self.mmss(s.ex.reps)) · Başlat", systemImage: "timer").frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    Text("\(s.ex.reps) dakika · bitirince işaretle").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }


                // Alt satır: sıradaki (öneri düğmesi kadranın içinde, WQ-01)
                Button { showQueue = true } label: {
                    Label(upcoming.map { $0.ex.id == s.ex.id ? String(localized: "Sıradaki: aynı hareket") : String(localized: "Sıradaki: \($0.ex.name)") } ?? String(localized: "Son set"),
                          systemImage: "list.bullet")
                        .font(.footnote).lineLimit(1).frame(maxWidth: .infinity)
                }
            }
            .scenePadding(.horizontal)   // kenarlara yapışmasın (watchOS kenar boşluğu)
        }
        // Alt kontroller arkasında kademeli bulanıklık: içerik çubuğun altına yumuşakça kaybolur
        .overlay {
            // Yumuşak geçiş ekranın en altına sabitlenir: içerik yalnız düğmelerin arkasında siyaha karışır
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
        // Alt kontroller: önceki · duraklat · tamamla — ekranın altında sabit, küçük, gri
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    idx = max(0, idx - 1); timerEnd = nil; load(steps[idx])
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Image(systemName: "backward.end.fill").foregroundStyle(Color.wInk)
                }
                .disabled(idx <= 0)
                .accessibilityLabel("Önceki set")
                Button {
                    paused = true; wk.pause(); restLeft = restLeft ?? restEnd.map { max(0, $0.timeIntervalSinceNow) }; restEnd = nil
                    WKInterfaceDevice.current().play(.stop)
                } label: {
                    Image(systemName: "pause.fill").foregroundStyle(Color.wInk)
                }
                .accessibilityLabel("Duraklat")
                Button {
                    withAnimation(flow) { complete(s, steps: steps) }
                } label: {
                    Image(systemName: upcoming == nil ? "checkmark" : "forward.end.fill").foregroundStyle(Color.wInk)
                }
                .accessibilityLabel(upcoming == nil ? "Son seti tamamla" : "Seti tamamla, sonrakine geç")
            }
        }
        .tint(Color.wMuted)
    }

    private func subtitle(_ s: WStep) -> String {
        var t = String(localized: "\(s.label) · Set \(s.si + 1)/\(s.of)")
        if s.ss { t += s.tag == "warm" ? tl(" · Isınma") : s.tag == "cool" ? tl(" · Soğuma") : tl(" · Süperset") }
        return t
    }

    private func statusRow(_ steps: [WStep]) -> some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)) { _ in
            HStack(spacing: 4) {
                if wk.running || shot != nil {
                    // Ekran görüntüsü modunda örnek nabız ve süre
                    let hr = shot != nil ? 128 : wk.heartRate, el = shot != nil ? 1712 : wk.elapsed
                    Image(systemName: "heart.fill").foregroundStyle(Color.wHeart)
                    Text(hr > 0 ? "\(Int(hr))" : "–").fontWeight(.heavy).italic()   // nabız sayısı (TE-03)
                    Text(Self.mmss(Int(el))).foregroundStyle(.secondary).padding(.leading, 4)
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
            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
    }

    @ViewBuilder private func cover(_ name: String) -> some View {
        let f = WMotion.frames(name)
        Group {
            if f.isEmpty {
                RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1))
                    .overlay(Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 34)).foregroundStyle(.secondary))
            } else {
                WFramePlayer(frames: f, paused: dimmed)
            }
        }
        .frame(height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .id(name)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(tl(label)).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .heavy).italic().monospacedDigit()).lineLimit(1)   // SF Pro, eşit genişlikli rakam (TE-03)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action(); WKInterfaceDevice.current().play(.click)
        } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).frame(width: 38, height: 38)   // dokunma hedefi büyüdü (TE-11)
        }
        .buttonStyle(.bordered).buttonBorderShape(.circle)
        .accessibilityLabel(tl(label))
    }

    // MARK: Dinlenme

    private func restView(next: WStep?) -> some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("DİNLENME").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                if let end = restEnd {
                    ring(end: end, total: restTotal, size: 76)
                } else if let l = restLeft {
                    ring(end: Date().addingTimeInterval(l), total: restTotal, size: 76, frozen: l)
                }
                if let next {
                    VStack(spacing: 0) {
                        Text("Sıradaki").font(.caption2).foregroundStyle(.secondary)
                        Text("\(next.ex.name) · Set \(next.si + 1)").font(.footnote.weight(.medium)).multilineTextAlignment(.center).lineLimit(2)
                    }
                }
                // Tek sıra: +15 · duraklat · Atla — ekrana kaydırmadan sığar (TE-11)
                HStack(spacing: 6) {
                    Button {
                        restTotal += 15
                        if let e = restEnd { restEnd = e.addingTimeInterval(15) } else if let l = restLeft { restLeft = l + 15 }
                    } label: {
                        Text("+15").font(.footnote.weight(.bold).italic()).frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .accessibilityLabel("15 saniye ekle")
                    .buttonStyle(.bordered).foregroundStyle(Color.wInk).tint(Color.wInk)
                    Button {
                        if let l = restLeft { restEnd = Date().addingTimeInterval(l); restLeft = nil }
                        else if let e = restEnd { restLeft = max(0, e.timeIntervalSinceNow); restEnd = nil }
                    } label: {
                        Image(systemName: restLeft == nil ? "pause.fill" : "play.fill").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .accessibilityLabel(restLeft == nil ? "Dinlenmeyi duraklat" : "Dinlenmeye devam et")
                    .buttonStyle(.bordered).foregroundStyle(Color.wInk).tint(Color.wInk)
                    Button { withAnimation(flow) { restEnd = nil; restLeft = nil } } label: {
                        Text("Atla").font(.footnote.weight(.bold).italic()).foregroundStyle(Color.wOnAction).frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.wAction)
                }
            }
            .scenePadding(.horizontal)   // kenarlara yapışmasın (watchOS kenar boşluğu)
        }
    }

    private func ring(end: Date, total: Double, size: CGFloat, frozen: Double? = nil) -> some View {
        // Bilek indirilince (Always On) saniyede bir çizilir; saat yorulmasın (WQ-03)
        TimelineView(.animation(minimumInterval: dimmed ? 1 : 1.0 / 10, paused: frozen != nil)) { t in
            let left = max(0, frozen ?? end.timeIntervalSince(t.date))
            // Son 3 saniye: turuncu ve saniye başında hafif nabız (MO-S3)
            let hot = left > 0 && left <= 3
            let beat = hot && !reduce ? 1 + 0.05 * max(0, sin(.pi * 2 * (left.rounded(.up) - left))) : 1
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 6)
                Circle().trim(from: 0, to: min(1, left / max(1, total)))
                    .stroke(hot ? Color.orange : Color.wInk, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Self.mmss(Int(left.rounded(.up))))
                    .font(.system(size: size * 0.28, weight: .heavy).italic().monospacedDigit())   // SF Pro, eşit genişlikli rakam (TE-03)
                    .foregroundStyle(hot ? Color.orange : .primary)
            }
            .frame(width: size, height: size)
            .scaleEffect(beat)
        }
    }

    // MARK: Antrenman sırası

    private func queueView(_ steps: [WStep]) -> some View {
        let order: [Exercise] = steps.reduce(into: [Exercise]()) { a, st in if !a.contains(where: { $0.id == st.ex.id }) { a.append(st.ex) } }
        let current = idx >= 0 && idx < steps.count ? steps[idx].ex.id : nil
        return List {
            ForEach(order, id: \.id) { ex in
                let mine = steps.indices.filter { steps[$0].ex.id == ex.id }
                let doneN = mine.filter { WLogic.isDone(steps[$0], day) }.count
                let all = doneN == mine.count
                Button {
                    if let j = mine.first(where: { !WLogic.isDone(steps[$0], day) }) ?? mine.first {
                        idx = j; timerEnd = nil; load(steps[j])
                    }
                    showQueue = false
                } label: {
                    HStack(spacing: 8) {
                        thumb(ex.name).opacity(all && ex.id != current ? 0.5 : 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ex.name).font(.footnote.weight(.medium)).lineLimit(2)
                            Text(ex.id == current ? "Şu an · \(doneN)/\(mine.count) set" : all ? "Tamamlandı" : "\(doneN)/\(mine.count) set")
                                .font(.caption2).foregroundStyle(ex.id == current  ? Color.wInk : .secondary)
                        }
                        Spacer(minLength: 0)
                        if all { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.wDone) }
                    }
                }
            }
        }
        .navigationTitle("Sıra")
    }

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


    // MARK: Duraklatma / bitiş özeti

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
                // Satırlar 60 ms arayla soldan girer (MO-S4)
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
                        Button("Devam et") { self.finished = false; paused = false; wk.resume() }
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
            .scenePadding(.horizontal)   // kenarlara yapışmasın (watchOS kenar boşluğu)
        }
    }

    /// Uzun değer: etiketin altında, tam genişlik (kesilmesin)
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
            Text(v).font(.system(size: 15, weight: .heavy).italic().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)   // özet sayıları (TE-03)
        }
        .padding(.vertical, 2)
    }

    // MARK: Akış

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
                // Kapak videosu: 2,4 sn sonra seti tamamla → dinlenme başlar
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.4))
                    let st = WLogic.steps(prog)
                    if idx >= 0, idx < st.count { complete(st[idx], steps: st) }
                }
            default: break
            }
            return   // ekran görüntüsünde antrenman oturumu / Sağlık izni açılmasın
        }
        #endif
        if !(day?.workoutDone ?? false) && !finished && !wk.running {
            // Saatte başka program seçildiyse bugünün antrenmanı o olsun; iPhone'a da bildirilir (WT-16)
            if date == DayKey.today { PhoneSync.shared.pick(ctx, date: date, pid: pid) }
            WKInterfaceDevice.current().play(.start)   // başlangıç bileğe hissedilsin (MO-S1)
            Task { await wk.start(owner: date + pid) }
        }
    }

    /// Sıradaki yapılmamış adım (sona gelince baştan atlananlara döner)
    private func nextIdx(_ steps: [WStep]) -> Int? {
        guard idx >= 0 else { return nil }
        let order = Array(steps.indices.dropFirst(idx + 1)) + Array(steps.indices.prefix(idx))
        return order.first { !WLogic.isDone(steps[$0], day) }
    }

    private func load(_ s: WStep) {
        input.kg = WLogic.suggestedKg(ctx, s, date: date, day: day)
        input.reps = WLogic.suggestedReps(s, day: day)
    }

    private func complete(_ s: WStep, steps: [WStep]) {
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

/// Özet satırı: ilk görünüşte 10 pt soldan solarak girer, sıra başına 60 ms gecikme (MO-S4)
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

/// İki kareyi yumuşak geçişle dönüşümlü gösterir (iPhone'daki hareket animasyonu)
/// MoveKit görselleri siyah zeminde: ters renk, ton 180° (kırmızı vurgu korunur) (MV-03)
struct WInvert: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.colorInvert().hueRotation(.degrees(180)) } else { content }
    }
}

struct WFramePlayer: View {
    let frames: [UIImage]
    /// Always On / arka plan: animasyon durur (WQ-03)
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
        // İki kare: yumuşak geçiş; video kareleri (MoveKit, 6 fps): geçişsiz akış (WT-09)
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


/// Oynatıcı girdileri: kilo ve tekrar (WQ-01)
@MainActor @Observable
final class WInput {
    var kg: Double = 0
    var reps = 10
}

/// Kilo kadranı: − / Digital Crown / + ve öneri; yalnız kendi içini yeniden çizer (WQ-01)
struct WKgDial: View {
    @Bindable var input: WInput
    let sug: Double?
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        let onSug = (sug ?? 0) > 0 && input.kg == sug
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                dialButton("minus", label: "Kiloyu azalt") { input.kg = max(0, input.kg - 2.5) }
                VStack(spacing: 0) {
                    // Crown çevrilince rakamlar yuvarlanır; önerilen kiloda yeşil (MO-S2)
                    Text(input.kg.kgText).font(.system(size: 30, weight: .heavy).italic().monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(onSug ? Color.wDone : .primary)
                        .contentTransition(.numericText(value: input.kg))
                        .animation(reduce ? nil : .snappy(duration: 0.2), value: input.kg)
                    Text(onSug ? "önerilen" : "kg").font(.caption2).foregroundStyle(onSug ? Color.wDone : .secondary)
                }
                .frame(maxWidth: .infinity)
                .sensoryFeedback(.success, trigger: onSug) { _, new in new }
                .focusable()
                .digitalCrownRotation($input.kg, from: 0, through: 500, by: 2.5, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                dialButton("plus", label: "Kiloyu artır") { input.kg = min(500, input.kg + 2.5) }
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
