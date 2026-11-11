import SwiftUI
import SwiftData
import GymPaperKit

// First run: welcome → Apple Health → weight and goal → first program.
// Shown once; never opens when data exists on this device or in iCloud, and closes if iCloud data arrives mid-flow.
// Nothing is saved during the steps: everything is written on "Finish" (so it doesn't mix with data from iCloud).

enum Onboarding {
    static let key = "onboarded"
    /// Traces of a used app: program, plan, weight, measurement or saved food
    static func hasData(_ ctx: ModelContext) -> Bool {
        func any<T: PersistentModel>(_ t: T.Type) -> Bool {
            var d = FetchDescriptor<T>(); d.fetchLimit = 1
            return ((try? ctx.fetchCount(d)) ?? 0) > 0
        }
        if any(WorkoutProgram.self) || any(BodyMeasure.self) || any(SavedFood.self) || any(Recipe.self) { return true }
        let profiles = (try? ctx.fetch(FetchDescriptor<UserProfile>())) ?? []
        return profiles.contains { $0.startKg != nil || !$0.goals.isEmpty || !$0.schedule.isEmpty }
    }
}

struct OnboardingView: View {
    enum Step: Hashable { case welcome, health, body, weight, program, tour }

    @Environment(\.modelContext) private var ctx
    @Environment(HealthService.self) private var health
    @Environment(AppState.self) private var app
    var onFinish: () -> Void
    /// Profile › Try the intro: replays the flow without saving anything
    var preview = false

    @State private var index = 0
    @State private var forward = true
    @State private var kg = ""
    @State private var goal = ""
    @State private var template: String? = WkTemplate.all.first?.key
    @State private var connecting = false
    @State private var healthKg: Double?   // weight prefilled from Health
    @FocusState private var focus: Bool

    /// If height, age or sex didn't come from Health, the "About you" step is added so calorie and macro goals fit the person
    private var needsBody: Bool { health.heightCm == nil || health.birthDate == nil || health.sex == nil }
    private var steps: [Step] {
        var a: [Step] = [.welcome]
        if health.available { a.append(.health) }
        if needsBody { a.append(.body) }
        return a + [.weight, .program, .tour]
    }
    @State private var sex: Sex? = nil
    @State private var birthYear = ""
    @State private var heightText = ""
    @State private var activity: ActivityLevel = .light
    private var step: Step { steps[min(index, steps.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                Group {
                    switch step {
                    case .welcome: welcome
                    case .health: healthStep
                    case .weight: weightStep
                    case .program: programStep
                    case .body: bodyStep
                    case .tour: tourStep
                    }
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .background(Color.bBg.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: index)
        .onAppear {
            #if DEBUG
            // screenshots: -onbStep N jumps to that step
            let a = ProcessInfo.processInfo.arguments
            if let i = a.firstIndex(of: "-onbStep"), i + 1 < a.count, let n = Int(a[i + 1]) { index = min(max(0, n), steps.count - 1) }
            #endif
        }
    }

    private var hideSkip: Bool { (step == .welcome && !preview) || step == .health }

    // MARK: Top bar: back, progress, skip

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { go(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)) }
                .buttonStyle(.b(.outline, .iconLarge))
                .accessibilityLabel("Geri")
                .opacity(index > 0 ? 1 : 0).disabled(index == 0)
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule().fill(i <= index ? Color.bPrimary : Color.bFg.opacity(0.12))
                        .frame(height: 4)
                }
            }
            .frame(maxWidth: 160)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Adım \(index + 1) / \(steps.count)")
            Button(preview && step == .welcome ? "Kapat" : "Atla") { preview && step == .welcome ? onFinish() : skip() }
                .buttonStyle(.b(.ghost))
                .foregroundStyle(Color.bMutedFg)
                // hidden on welcome and the Health step: "Not now" in Health only skips that step, so the two don't mix
                .opacity(hideSkip ? 0 : 1).disabled(hideSkip)
                .frame(minWidth: 44)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
        .animation(.snappy, value: index)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnbHero().frame(maxWidth: .infinity).padding(.top, 24).padding(.bottom, 32)
            Text("Hoş geldin").font(.bDisplay(34, relativeTo: .largeTitle)).tracking(-0.8).foregroundStyle(Color.bFg)
            Text("GYM Paper antrenmanını, beslenmeni ve kilonu sade bir defter gibi tek yerde tutar.")
                .font(.geist(17, relativeTo: .body)).foregroundStyle(Color.bMutedFg).padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 18) {
                OnbRow(symbol: "dumbbell", title: "Antrenman", text: "Programını kur, setleri işaretle; dinlenme sayacı kendiliğinden başlar.")
                OnbRow(symbol: "fork.knife", title: "Beslenme", text: "Yediğini ekle; kalori ve makrolar hesaplansın.")
                OnbRow(symbol: "chart.line.downtrend.xyaxis", title: "İlerleme", text: "Kilonu ve ölçülerini izle, hedefe ne kaldığını gör.")
            }
            .padding(.top, 28)
        }
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            BEmptyArt(symbol: "heart.text.square", badge: "link", size: 112).frame(maxWidth: .infinity).padding(.top, 24).padding(.bottom, 32)
            title("Apple Sağlık'a bağlan",
                  "Adımlarını, yaktığın kaloriyi ve kilonu okuyup günlük kalori ihtiyacını hesaplarız. Bitirdiğin antrenmanları Sağlık'a yazarız.")
            VStack(spacing: 0) {
                OnbCheck(symbol: "figure.walk", text: "Adım ve aktif enerji")
                OnbDivider()
                OnbCheck(symbol: "scalemass", text: "Kilo, boy, yaş ve cinsiyet")
                OnbDivider()
                OnbCheck(symbol: "figure.strengthtraining.traditional", text: "Antrenmanların (yazma)")
            }
            .bCard(padding: 0)
            .padding(.top, 24)
            Text("İzinleri istediğin zaman Ayarlar › Sağlık'tan değiştirebilirsin.")
                .font(.bXs).foregroundStyle(Color.bMutedFg).padding(.top, 12)
        }
    }

    private var weightStep: some View {
        let k = parsed(kg), g = parsed(goal)
        return VStack(alignment: .leading, spacing: 0) {
            BEmptyArt(symbol: "scalemass", badge: "flag.fill", size: 112).frame(maxWidth: .infinity).padding(.top, 24).padding(.bottom, 32)
            title("Kilon ve hedefin", "İlerlemeni buna göre gösteririz; istediğin zaman Profil'den değiştirebilirsin.")
            VStack(spacing: 12) {
                OnbKgField(label: "Şu anki kilon", text: $kg, hint: health.latestWeightKg != nil ? "Sağlık'tan" : nil, focus: $focus)
                OnbKgField(label: "Hedef kilon", text: $goal, hint: nil, focus: $focus)
            }
            .padding(.top, 24)
            if let k, let g {
                let d = g - k
                HStack(spacing: 8) {
                    Image(systemName: d < 0 ? "arrow.down.right" : d > 0 ? "arrow.up.right" : "equal")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.bMutedFg)
                    (Text(d == 0 ? "Kilonu korumak" : "Hedefe ").foregroundColor(Color.bMutedFg)
                     + Text(d == 0 ? "" : fmt1(abs(d))).font(.bNum(17, relativeTo: .body)).foregroundColor(Color.bFg)
                     + Text(d == 0 ? "" : " kg \(d < 0 ? tl("vermek") : tl("almak"))").foregroundColor(Color.bMutedFg))
                        .font(.bSm).monospacedDigit()
                }
                .padding(.top, 14)
                .transition(.opacity)
            }
            planPreview(k, g)
        }
        .animation(.snappy, value: k != nil && g != nil)
    }

    /// Preview of the computed daily goal
    @ViewBuilder private func planPreview(_ k: Double?, _ g: Double?) -> some View {
        if let k, let plan = OnbPlan.make(kg: k, goal: g, heightCm: bodyHeight, birth: bodyBirth, sex: bodySex, activity: activity) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Günlük hedefin").font(.bXs).foregroundStyle(Color.bMutedFg)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(fmt0(plan.kcal)).font(.bNum(28, relativeTo: .title)).foregroundStyle(Color.bFg)
                    Text("kcal").font(.geist(14, .semibold)).foregroundStyle(Color.bMutedFg)
                }
                Text("Protein \(fmt0(plan.p)) g · Karbonhidrat \(fmt0(plan.c)) g · Yağ \(fmt0(plan.f)) g")
                    .font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
                Text("Boy, yaş, cinsiyet ve hareket düzeyinden hesaplandı; tahminidir. Profil › Kalori hedefi'nden değiştirebilirsin.")
                    .font(.bXs).foregroundStyle(Color.bMutedFg).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .bCard(padding: 14)
            .padding(.top, 16)
            .transition(.opacity)
        }
    }

    private var bodyHeight: Double? { health.heightCm ?? { let v = trNum(heightText); return (120...230).contains(v) ? v : nil }() }
    private var bodyBirth: Date? {
        if let b = health.birthDate { return b }
        guard let y = Int(birthYear), (1920...(Calendar.current.component(.year, from: .now) - 10)).contains(y) else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: 7, day: 1))
    }
    private var bodySex: Sex? { health.sex ?? sex }

    /// About you: only asks what Health doesn't have
    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            BEmptyArt(symbol: "person.text.rectangle", badge: "flame.fill", size: 112).frame(maxWidth: .infinity).padding(.top, 24).padding(.bottom, 32)
            title("Seni tanıyalım", "Günlük kalori ve makro hedefini sana göre hesaplamak için. Bu bilgiler yalnız cihazında ve iCloud'unda kalır.")
            VStack(spacing: 12) {
                if health.sex == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cinsiyet").font(.geist(14, .medium, relativeTo: .subheadline)).foregroundStyle(Color.bMutedFg)
                        HStack(spacing: 8) {
                            ForEach(Sex.allCases, id: \.self) { sx in
                                Button { haptic(); sex = sx } label: { Text(sx.label).frame(maxWidth: .infinity) }
                                    .buttonStyle(.b(sex == sx ? .primary : .secondary, full: true))
                                    .accessibilityAddTraits(sex == sx ? .isSelected : [])
                            }
                        }
                    }
                    .bCard(padding: 16)
                }
                HStack(spacing: 12) {
                    if health.birthDate == nil { OnbNumField(label: "Doğum yılı", placeholder: "1990", unit: nil, text: $birthYear, focus: $focus) }
                    if health.heightCm == nil { OnbNumField(label: "Boy", placeholder: "175", unit: "cm", text: $heightText, focus: $focus) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hareket düzeyi").font(.geist(14, .medium, relativeTo: .subheadline)).foregroundStyle(Color.bMutedFg)
                    Picker("Hareket düzeyi", selection: $activity) {
                        ForEach(ActivityLevel.allCases, id: \.self) { Text(tl($0.label)).tag($0) }
                    }
                    .pickerStyle(.menu).tint(Color.bFg)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .bCard(padding: 16)
            }
            .padding(.top, 24)
        }
    }

    private var programStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("İlk programını seç", "Hazır bir programla başla; günlerini haftalık plana yerleştiririz. Sonra dilediğin gibi düzenlersin.")
                .padding(.top, 16)
            VStack(spacing: 8) {
                ForEach(WkTemplate.all) { t in
                    choice(selected: template == t.key, title: t.key == WkTemplate.all.first?.key ? String(localized: "\(t.name) · Önerilen") : t.name, sub: String(localized: "Haftada \(t.days ?? t.programs.count) gün · \(t.who)")) { template = t.key }
                }
                choice(selected: template == nil, title: "Kendim kuracağım", sub: "Boş başla; Antrenmanlarım'dan programını oluştur.") { template = nil }
            }
            .padding(.top, 20)
            // if used on another device, iCloud data lands within minutes; warn to avoid duplicate programs
            if FileManager.default.ubiquityIdentityToken != nil {
                Label("GYM Paper'ı başka bir cihazda kullanıyorsan verilerin iCloud'dan birkaç dakika içinde gelir; bu adımı atlayabilirsin.", systemImage: "icloud")
                    .font(.bXs).foregroundStyle(Color.bMutedFg)
                    .padding(.top, 16)
            }
        }
    }

    /// How it works: one screen, four rows
    private var tourStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            BEmptyArt(symbol: "sparkles", badge: "checkmark", size: 112).frame(maxWidth: .infinity).padding(.top, 24).padding(.bottom, 32)
            title("Nasıl kullanılır", "Dört şey bilmen yeter; gerisini yolda ipuçlarıyla gösteririz.")
            VStack(alignment: .leading, spacing: 18) {
                OnbRow(symbol: "play.circle", title: "Başlat", text: "Antrenman sekmesinde günün antrenmanını başlat; oynatıcı seni hareket hareket götürür.")
                OnbRow(symbol: "forward.end", title: "Seti tamamla", text: "Kiloyu ve tekrarı gir, seti bitir; dinlenme sayacı kendiliğinden başlar.")
                OnbRow(symbol: "text.cursor", title: "Yediğini yaz", text: "\"2 yumurta, 1 dilim ekmek\" yazman yeter; kalori ve makrolar hesaplanır.")
                OnbRow(symbol: "square.grid.2x2", title: "Günün tek ekranda", text: "Özet'te antrenman, beslenme, su, adım ve haftalık gidişatın bir arada. İlk günler için üstte kısa bir yapılacaklar listesi seni bekliyor.")
            }
            .padding(.top, 24)
        }
    }

    // MARK: Bottom buttons

    private var footer: some View {
        VStack(spacing: 4) {
            switch step {
            case .welcome:
                Button("Başlayalım") { go(1) }.buttonStyle(.b(.primary, .large, full: true))
            case .health:
                Button { connect() } label: {
                    HStack(spacing: 8) {
                        if connecting { ProgressView().tint(Color.bActionFg) }
                        Text("Sağlık'a bağlan")
                    }
                }
                .buttonStyle(.b(.primary, .large, full: true)).disabled(connecting)
                Button("Şimdi değil") { go(1) }.buttonStyle(.b(.ghost, .regular, full: true)).bButtonFg(Color.bMutedFg)
            case .body:
                Button("Devam") { focus = false; go(1) }.buttonStyle(.b(.primary, .large, full: true))
            case .weight:
                Button("Devam") { focus = false; go(1) }.buttonStyle(.b(.primary, .large, full: true))
            case .program:
                Button("Devam") { go(1) }.buttonStyle(.b(.primary, .large, full: true))
            case .tour:
                Button(template == nil ? "Başla" : "Programı ekle ve başla") { finish() }.buttonStyle(.b(.primary, .large, full: true))
            }
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Color.bBg)
    }

    // MARK: Parts

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tl(t)).font(.bDisplay(30, relativeTo: .largeTitle)).tracking(-0.6).foregroundStyle(Color.bFg)
                .fixedSize(horizontal: false, vertical: true)
            Text(tl(sub)).font(.geist(16)).foregroundStyle(Color.bMutedFg).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choice(selected: Bool, title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button { haptic(); withAnimation(.snappy) { action() } } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tl(title)).font(.geist(16, .semibold)).foregroundStyle(Color.bFg)
                    Text(tl(sub)).font(.bXs).foregroundStyle(Color.bMutedFg).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(selected ? Color.bPrimary : Color.bFg.opacity(0.25))
                    .contentTransition(.symbolEffect(.replace))
            }
            .bCard(padding: 14, highlight: selected ? Color.bPrimary : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Eylemler

    private func parsed(_ s: String) -> Double? { let v = trNum(s); return (20...400).contains(v) ? v : nil }

    private func go(_ d: Int) {
        let n = index + d
        guard steps.indices.contains(n) else { return }
        forward = d > 0
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { index = n }
    }

    private func skip() {
        focus = false
        if step == .weight { kg = ""; goal = "" }
        if step == .tour { finish() } else { if step == .program { template = nil }; go(1) }
    }

    private func connect() {
        connecting = true
        Task {
            await health.requestAccess()
            // prefill the weight from Health
            if kg.isEmpty, let w = health.latestWeightKg { kg = fmt1(w); healthKg = w }
            connecting = false
            go(1)
        }
    }

    private func finish() {
        focus = false
        if preview {
            // trial run: nothing written to profile, measurements, programs or Health
            haptic(.medium)
            onFinish()
            app.toast("Tanıtım bitti · verilerin değişmedi")
            return
        }
        let p = Store.profile(ctx)
        if let k = parsed(kg) {
            if p.startKg == nil { p.startKg = k }
            // an unchanged Health weight isn't written to iCloud as a measurement nor written to Health again
            let fromHealth = healthKg.map { abs($0 - k) < 0.05 } ?? false
            if !fromHealth {
                ctx.insert(BodyMeasure(date: .now, kg: k))
                Task { await health.saveWeight(k) }
            }
        }
        if let g = parsed(goal), g != parsed(kg) { p.goals = [g] }
        // personal goals: details missing from Health go to the profile; calories and macros are computed
        if health.heightCm == nil, let h = bodyHeight { p.heightCm = h }
        if health.birthDate == nil, let b = bodyBirth { p.birthDate = b }
        if health.sex == nil, let sx = sex { p.sex = sx }
        p.activity = activity
        let k0 = parsed(kg) ?? health.latestWeightKg ?? p.startKg
        if let k0 {
            let g0 = parsed(goal)
            p.weeklyLossKg = (g0 ?? k0) < k0 - 0.4 ? 0.5 : 0
            if let plan = OnbPlan.make(kg: k0, goal: g0, heightCm: bodyHeight, birth: bodyBirth, sex: bodySex, activity: activity) {
                p.manualKcal = nil
                p.proteinG = plan.p; p.carbsG = plan.c; p.fatG = plan.f
            } else {
                // without height/age/sex, macros are at least based on weight
                p.proteinG = (k0 * 1.8 / 5).rounded() * 5; p.fatG = (k0 * 0.8 / 5).rounded() * 5
            }
        }
        var added: String?
        if let key = template, let t = WkTemplate.all.first(where: { $0.key == key }) {
            Wk.applyTemplate(t, ctx: ctx, profile: p)
            added = t.name
        }
        Store.save(ctx)
        UserDefaults.standard.set(true, forKey: StartGuide.showKey)   // Getting started list on Today
        haptic(.medium)
        onFinish()
        if let added { app.toast(String(localized: "\(added) haftalık planına eklendi")) }
    }
}

// MARK: - Parts

/// Welcome art: three circles (workout, nutrition, progress), same language as the empty states
private struct OnbHero: View {
    @State private var shown = false
    var body: some View {
        ZStack {
            Circle().fill(Color.bFg.opacity(0.04)).frame(width: 200, height: 200)
            bubble("fork.knife", 64).offset(x: -78, y: 38)
            bubble("chart.line.downtrend.xyaxis", 64).offset(x: 78, y: 38)
            ZStack {
                Circle().fill(Color.bPrimary).frame(width: 104, height: 104)
                Image(systemName: "dumbbell.fill").font(.system(size: 40, weight: .semibold)).foregroundStyle(Color.bPrimaryFg)
                    .symbolEffect(.bounce, value: shown)
            }
            .offset(y: -12)
        }
        .frame(height: 210)
        .accessibilityHidden(true)
        .onAppear { shown = true }
    }
    private func bubble(_ s: String, _ size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.bCard).frame(width: size, height: size)
            Image(systemName: s).font(.system(size: size * 0.38, weight: .semibold)).symbolRenderingMode(.hierarchical).foregroundStyle(Color.bFg)
        }
    }
}

private struct OnbRow: View {
    var symbol: String; var title: String; var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.bFg)
                .frame(width: 44, height: 44)
                .background(Color.bCard, in: RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(tl(title)).font(.geist(16, .semibold)).foregroundStyle(Color.bFg)
                Text(tl(text)).font(.bSm).foregroundStyle(Color.bMutedFg).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnbCheck: View {
    var symbol: String; var text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.bFg).frame(width: 28)
            Text(tl(text)).font(.geist(15)).foregroundStyle(Color.bFg)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }
}

private struct OnbDivider: View { var body: some View { Rectangle().fill(Color.bBorder).frame(height: 1).padding(.leading, 56) } }

/// Large weight field: −/+ in 0.5 kg steps, or type directly
private struct OnbKgField: View {
    var label: String
    @Binding var text: String
    var hint: String?
    var focus: FocusState<Bool>.Binding
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tl(label)).font(.geist(14, .medium, relativeTo: .subheadline)).foregroundStyle(Color.bMutedFg)
                    if let hint { Text(tl(hint)).font(.bXs).foregroundStyle(Color.bMutedFg).padding(.horizontal, 6).padding(.vertical, 1).background(Color.bFg.opacity(0.07), in: Capsule()) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    // faded placeholder so it doesn't read as a real value
                    TextField("", text: $text, prompt: Text(verbatim: "0,0").foregroundStyle(Color.bMutedFg.opacity(0.35)))
                        .keyboardType(.decimalPad).focused(focus)
                        .font(.bNum(34, relativeTo: .largeTitle)).foregroundStyle(Color.bFg)
                        .fixedSize()
                        .accessibilityLabel(tl(label))
                    Text("kg").font(.geist(16, .semibold)).foregroundStyle(Color.bMutedFg)
                }
            }
            Spacer(minLength: 0)
            step("minus", -0.5)
            step("plus", 0.5)
        }
        .bCard(padding: 16)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
    }
    private func step(_ s: String, _ d: Double) -> some View {
        Button {
            let cur = trNum(text)
            // don't invent a default weight when empty; open the keyboard
            guard cur > 0 else { focus.wrappedValue = true; return }
            text = fmt1(min(400, max(20, cur + d)))
        } label: { Image(systemName: s).font(.system(size: 15, weight: .bold)) }
        .buttonStyle(.b(.secondary, .iconLarge))
        .accessibilityLabel(d < 0 ? "\(label) azalt" : "\(label) artır")
    }
}


/// Personal daily goal on first run: Mifflin-St Jeor × activity, 0.5 kg/week deficit for weight loss
/// (never below BMR); protein 1.8 g/kg, fat 0.8 g/kg, remaining calories carbs (at least 50 g)
enum OnbPlan {
    struct Plan { var kcal, p, c, f: Double }
    static func make(kg: Double, goal: Double?, heightCm: Double?, birth: Date?, sex: Sex?, activity: ActivityLevel) -> Plan? {
        guard let heightCm, let birth, let sex else { return nil }
        let body = BodyProfile(weightKg: kg, heightCm: heightCm, age: min(100, max(10, AgeCalc.age(birth: birth))), sex: sex)
        let bmr = CalorieEngine.bmr(body)
        let loss = (goal ?? kg) < kg - 0.4 ? 0.5 : 0
        let kcal = CalorieEngine.dailyTarget(tdee: CalorieEngine.tdee(body, activity: activity), bmr: bmr, weeklyLossKg: loss)
        let p = (kg * 1.8 / 5).rounded() * 5, f = (kg * 0.8 / 5).rounded() * 5
        let c = max(50, ((kcal - p * 4 - f * 9) / 4 / 5).rounded() * 5)
        return Plan(kcal: kcal, p: p, c: c, f: f)
    }
}

private struct OnbNumField: View {
    var label: String; var placeholder: String; var unit: String?
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tl(label)).font(.geist(14, .medium, relativeTo: .subheadline)).foregroundStyle(Color.bMutedFg)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField(placeholder, text: $text)
                    .keyboardType(.numberPad).focused(focus)
                    .font(.bNum(30, relativeTo: .largeTitle)).foregroundStyle(Color.bFg)
                    .accessibilityLabel(tl(label))
                if let unit { Text(unit).font(.geist(16, .semibold)).foregroundStyle(Color.bMutedFg) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bCard(padding: 16)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
    }
}
