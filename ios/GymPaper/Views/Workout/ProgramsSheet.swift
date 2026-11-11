import SwiftUI
import SwiftData
import VisionKit
import AVFoundation
import CoreImage.CIFilterBuiltins
import GymPaperKit

/// Antrenman sekmesindeki itilen (push) ekranlar
enum WkRoute: Hashable {
    case programs
    case programEdit(pid: String)
}

/// Destinations of pushed screens (bound at the root of the Workout tab)
struct WkRouteDestination: View {
    let route: WkRoute
    var body: some View {
        switch route {
        case .programs: ProgramsScreen()
        case .programEdit(let p): ProgramEditScreen(pid: p)
        }
    }
}

/// Header of a pushed screen: back button on the left, BHeader below. Edge swipe back works too.
struct WkPushedHeader: View {
    var eyebrow: String? = nil
    var title: String
    var sub: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.embeddedDetail) private var embedded
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // no back button in the detail when list and detail are side by side (iPhone Duo inner screen)
            if !embedded {
                BRoundIcon(icon: "chevron-left", label: "Geri") { dismiss() }
                    .padding(.top, 4)
            }
            // no eyebrow on pushed screens: back button + one title (Figma v1.2)
            BHeader(title: title, sub: sub)
        }
    }
}

/// Edge swipe back even with the navigation bar hidden
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // don't start while a transition is running (the stack can freeze)
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        return viewControllers.count > 1 && transitionCoordinator == nil
    }
}

private struct EmbeddedDetailKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// The view is shown as a detail next to the list on a wide screen
    var embeddedDetail: Bool { get { self[EmbeddedDetailKey.self] } set { self[EmbeddedDetailKey.self] = newValue } }
}

typealias ProgramsSheet = ProgramsScreen
typealias ProgramEditSheet = ProgramEditScreen

/// My programs: weekly days, my programs (edit/delete), ready-made programs — full screen (not a sheet)
struct ProgramsScreen: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutProgram.createdAt) private var programs: [WorkoutProgram]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var name = ""
    @State private var route: WkSheet?
    @State private var showTemplates = false
    /// My programs / Ready-made programs
    @State private var tab = 0
    /// Ready-made program preview
    @State private var previewKey: String?
    /// New program → edit screen (opens in whichever tab pushed it)
    @State private var newPid: String?
    @State private var shareProg: WorkoutProgram?
    @State private var scanning = false
    @State private var naming = false
    @State private var scanned: String?
    @Environment(\.horizontalSizeClass) private var hsc
    /// Program open on the right on a wide screen
    @State private var selPid: String?

    var body: some View {
        if hsc == .regular {
            // iPhone Duo inner screen: list on the left, the selected program is edited on the right
            let live = programs.filter { !$0.archived }
            HStack(spacing: 0) {
                listBody.frame(width: 340)
                Rectangle().fill(Color.bBorder).frame(width: 1).ignoresSafeArea()
                Group {
                    if let pid = selPid ?? live.first?.pid, live.contains(where: { $0.pid == pid }) {
                        ProgramEditScreen(pid: pid).id(pid).environment(\.embeddedDetail, true)
                    } else {
                        WkEmpty(icon: "barbell", title: "Program seç", text: "Düzenlemek için soldan bir program seç ya da yeni oluştur.")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color.bBg.ignoresSafeArea())
        } else {
            listBody
        }
    }

    /// Edit: a new screen on narrow layouts, the right pane on wide ones
    private func open(_ pid: String) { if hsc == .regular { selPid = pid } else { newPid = pid } }

    @ViewBuilder private var listBody: some View {
        let live = programs.filter { !$0.archived }
        let today = DayKey.today, ti = DayKey.weekday(today)
        let profile = profiles.first
        BScreen(pinHeader: false) {
            WkPushedHeader(eyebrow: "Antrenman", title: "Antrenmanlarım", sub: nil)
            // my programs and ready-made programs on separate tabs
            BSegmented(selection: $tab, options: [(0, "Programlarım"), (1, "Hazır programlar")])
            if tab == 0 {
                if live.isEmpty {
                    BEmpty(symbol: "dumbbell", badge: "sparkles", title: "Henüz programın yok",
                           text: "Hazır programlara göz at ya da kendininkini kur. Hangi gün yapacağını haftalık plandan sen seçersin.",
                           action: "Hazır programlara bak") {
                        withAnimation(.snappy) { tab = 1 }
                    }
                } else {
                    WkSectionTitle("Haftalık plan")
                    WkListCard {
                        ForEach(0..<7, id: \.self) { i in
                            // each day's plan on its next date
                            let k = Wk.weekDate(i, i < ti ? 1 : 0)
                            let cur: String? = profile.flatMap { (Wk.scheduleAt($0, k)[String(i)] ?? nil) }
                            HStack(spacing: 12) {
                                Text(DayKey.dayLong[i]).font(.geist(14, .medium, relativeTo: .subheadline))
                                Spacer()
                                Menu {
                                    Button("Dinlenme") { setDay(i, nil) }
                                    ForEach(live) { p in Button(p.name) { setDay(i, p.pid) } }
                                } label: {
                                    HStack {
                                        Text(live.first { $0.pid == cur }?.name ?? "Dinlenme").lineLimit(1).foregroundStyle(Color.bFg)
                                        Spacer(minLength: 4)
                                        Ti("selector").foregroundStyle(Color.bMutedFg)
                                    }
                                    .font(.geist(16)).padding(.horizontal, 12).frame(width: 176, height: 40)
                                    .overlay(RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous).strokeBorder(Color.bInput))
                                }
                                .accessibilityLabel("\(DayKey.dayLong[i]) programı")
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                        }
                    }
                    WkSectionTitle("Programlarım")
                }
                VStack(spacing: 8) {
                    ForEach(live) { p in
                        // tapping a row opens the program detail; name and exercises are edited there
                        // options (…) sit inside the card, on the right (they hung outside it before)
                        HStack(spacing: 4) {
                            Button { haptic(); open(p.pid) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name.isEmpty ? "Program" : p.name).font(.geist(16, .semibold)).foregroundStyle(Color.bFg).lineLimit(1)
                                    Text(progSub(p, profile: profile)).font(.bXs).foregroundStyle(Color.bMutedFg).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 16).padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.press)
                            .accessibilityHint("Programı aç")
                            Menu {
                                Button { shareProg = p } label: { Label("Paylaş", systemImage: "square.and.arrow.up") }
                                    .disabled(p.blocks.allExercises.isEmpty)
                                Button(role: .destructive) { remove(p) } label: { Label("Sil", systemImage: "trash") }
                            } label: {
                                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(Color.bMutedFg)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .padding(.trailing, 6)
                            .accessibilityLabel("\(p.name) için seçenekler")
                        }
                        .bCard(padding: 0)
                    }
                    // new program: build your own, scan a QR code or paste a link
                    Menu {
                        Button { name = ""; naming = true } label: { Label("Kendi programını oluştur", systemImage: "square.and.pencil") }
                        Button { scanning = true } label: { Label("QR okut", systemImage: "qrcode.viewfinder") }
                        Button { pasteLink() } label: { Label("Bağlantıyı yapıştır", systemImage: "doc.on.clipboard") }
                    } label: {
                        Label(live.isEmpty ? "Kendi programını kur" : "Yeni program", systemImage: "plus").font(.geist(16, .semibold))
                            .foregroundStyle(live.isEmpty ? Color.bFg : Color.bActionFg)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(live.isEmpty ? Color.bSecondary : Color.bAction, in: Capsule())
                    }
                    .accessibilityLabel("Yeni program")
                }
            } else {
                // ready-made programs: tapping shows the contents first; adding is a separate step
                Text("Programa dokunup hareketlerini incele; eklediğin programı hangi günlere koyacağını Programlarım › Haftalık plan'dan seçersin.")
                    .font(.bXs).foregroundStyle(Color.bMutedFg)
                VStack(spacing: 8) {
                    ForEach(WkTemplate.all) { t in
                        Button { haptic(); previewKey = t.key } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    (Text(t.name).font(.geist(15, .semibold, relativeTo: .subheadline)).foregroundColor(Color.bFg)
                                     + Text(" · \(t.days ?? t.programs.count) gün").font(.bSm).foregroundColor(Color.bMutedFg))
                                    Text(t.who).font(.bXs).foregroundStyle(Color.bMutedFg)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.bMutedFg)
                            }
                            .bCard(padding: 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.press)
                    }
                }
            }
        }
        .wkSheets($route)
        .navigationDestination(item: $newPid) { pid in ProgramEditScreen(pid: pid) }
        .navigationDestination(item: $previewKey) { key in WkTemplatePreview(key: key) { withAnimation(.snappy) { tab = 0 } } }
        .sheet(item: $shareProg) { p in WkShareSheet(prog: p).environment(app) }
        .alert("Yeni program", isPresented: $naming) {
            TextField("ör. Üst vücut", text: $name)
            Button("Oluştur") { add() }
            Button("Vazgeç", role: .cancel) { name = "" }
        } message: { Text("Oluşturunca hareket eklemek için düzenleme ekranı açılır.") }
        .fullScreenCover(isPresented: $scanning, onDismiss: {
            if let p = scanned { scanned = nil; app.open(.importProgram(payload: p)) }
        }) {
            WkQRScanSheet { payload in scanned = payload }
        }
    }

    /// "3 days · Mon, Wed, Fri" or "8 exercises · not assigned to a day"
    private func progSub(_ p: WorkoutProgram, profile: UserProfile?) -> String {
        let n = p.blocks.allExercises.count
        guard let profile else { return String(localized: "\(n) hareket") }
        let days = (0..<7).filter { k in (Wk.scheduleAt(profile, Wk.nextOnOrAfter(DayKey.today, k))[String(k)] ?? nil) == p.pid }
        return days.isEmpty ? String(localized: "\(n) hareket · güne atanmadı") : String(localized: "\(n) hareket · \(days.map { DayKey.dayShort[$0] }.joined(separator: ", "))")
    }

    private func pasteLink() {
        let t = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string ?? ""
        if let p = WkShare.payload(fromText: t) { app.open(.importProgram(payload: p)) }
        else { app.toast("Panoda antrenman bağlantısı yok", kind: .error) }
    }

    private func setDay(_ i: Int, _ pid: String?) {
        haptic()
        Wk.setScheduleFrom(ctx, Store.profile(ctx), from: DayKey.today, dow: i, pid: pid)
    }
    private func add() {
        let n = name.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
        let p = WorkoutProgram(pid: UUID().uuidString, name: n)
        ctx.insert(p); name = ""; haptic()
        // go to the new program's edit screen (to add exercises)
        open(p.pid)
    }
    /// Archives instead of deleting: past days keep showing the program, and the plan empties from today on
    private func remove(_ p: WorkoutProgram) {
        let profile = Store.profile(ctx), today = DayKey.today
        let oldSched = profile.schedule
        let overrides = Wk.allDays(ctx).filter { $0.date >= today && $0.programIdRaw == p.pid }
        p.archived = true
        // drop it from all future plan entries and day picks
        Wk.clearFutureAssignments(ctx, profile, pid: p.pid)
        let afterSched = profile.schedule
        app.toast(String(localized: "\(p.name) silindi"), kind: .delete) {
            p.archived = false
            // the old plan if it didn't change since; otherwise only this program's days are written back
            if profile.schedule == afterSched { profile.schedule = oldSched }
            else {
                for (k, v) in Schedule.at(oldSched, date: today) where v == p.pid {
                    if let dow = Int(k) { Wk.setScheduleFrom(ctx, profile, from: today, dow: dow, pid: p.pid) }
                }
            }
            for d in overrides where d.programIdRaw == nil { d.programIdRaw = p.pid }
        }
    }
}

/// Ready-made program preview: days and exercises are visible before adding
struct WkTemplatePreview: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Query(sort: \WorkoutProgram.createdAt) private var programs: [WorkoutProgram]
    let key: String
    var onAdded: () -> Void = {}

    var body: some View {
        if let t = WkTemplate.all.first(where: { $0.key == key }) {
            let owned = t.programs.allSatisfy { tp in programs.contains { !$0.archived && $0.name == tp.name } }
            BScreen(pinHeader: false) {
                WkPushedHeader(eyebrow: "Hazır program", title: t.name, sub: String(localized: "Haftada \(t.days ?? t.programs.count) gün · \(t.who)"))
                ForEach(t.programs, id: \.id) { tp in
                    WkSectionTitle(tp.name)
                    WkListCard {
                        ForEach(tp.blocks.allExercises) { e in
                            HStack(spacing: 12) {
                                MotionThumb(name: e.name, size: 44)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.name).font(.geist(15, .medium)).foregroundStyle(Color.bFg).lineLimit(1)
                                    Text("\(e.sets) × \(e.reps)\(e.unit == "tekrar" ? "" : " " + e.unit)").font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }
                }
                Button { add(t) } label: { BLabel(owned ? "Antrenmanlarında var" : "Antrenmanlarıma ekle", icon: owned ? "check" : "plus") }
                    .buttonStyle(.b(.primary, .large, full: true)).disabled(owned)
                Text("Eklediğin programlar bir güne atanmaz; Programlarım › Haftalık plan'dan istediğin günlere koyarsın.")
                    .font(.bXs).foregroundStyle(Color.bMutedFg)
            }
        } else {
            Color.bBg.onAppear { dismiss() }
        }
    }

    private func add(_ t: WkTemplate) {
        let (added, _) = Wk.applyTemplate(t, ctx: ctx, profile: Store.profile(ctx), assignDays: false)
        haptic(.medium)
        app.toast(String(localized: "\(t.name) Antrenmanlarım'a eklendi")) { for c in added { ctx.delete(c) } }
        onAdded()
        dismiss()
    }
}

/// Program name; restores the previous name if left empty
struct WkProgName: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var p: WorkoutProgram
    @State private var last = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField("Program adı", text: $p.name).textFieldStyle(.b).focused($focused)
            .onAppear { last = p.name }
            .onChange(of: focused) { _, f in
                if f { last = p.name } else if p.name.trimmingCharacters(in: .whitespaces).isEmpty { p.name = last.isEmpty ? "Program" : last }
                else if !last.isEmpty, p.name != last { Wk.freezePast(ctx, p, name: last); last = p.name }   // past days keep the old name
            }
            // no empty name even when going back with the keyboard open
            .onDisappear { if p.name.trimmingCharacters(in: .whitespaces).isEmpty { p.name = last.isEmpty ? "Program" : last } }
            .accessibilityLabel("Program adı")
    }
}

/// Edits one saved program on its own — full screen
struct ProgramEditScreen: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutProgram.createdAt) private var programs: [WorkoutProgram]
    let pid: String
    @State private var route: WkSheet?
    @State private var sharing = false
    @Environment(AppState.self) private var app

    var body: some View {
        if let prog = programs.first(where: { $0.pid == pid }) {
            let profile = Store.profile(ctx)
            let days = (0..<7).filter { k in (Wk.scheduleAt(profile, Wk.nextOnOrAfter(DayKey.today, k))[String(k)] ?? nil) == pid }.map { DayKey.dayLong[$0] }
            BScreen(pinHeader: false) {
                WkPushedHeader(eyebrow: "Programı düzenle", title: prog.name.isEmpty ? "Program" : prog.name,
                               sub: days.isEmpty ? "Henüz bir güne atanmadı" : String(localized: "Her \(Wk.lower(days.joined(separator: ", "))) · değişiklikler gelecek haftalara yansır"))
                BField(label: "Program adı") { WkProgName(p: prog) }
                if !prog.blocks.isEmpty {
                    WkBlockList(prog: prog, edit: true, date: nil, route: $route)
                    let weekEnd = DayKey.shift(DayKey.today, days: 6 - DayKey.weekday(DayKey.today))
                    let week = MuscleLoad.load(MuscleData.weekPlan(ctx, logs: Wk.allDays(ctx), profile: profile, through: weekEnd).items, scope: .week)
                    WkMuscleSection(prog: prog, canSuggest: true, title: tl("Bu antrenman çalıştırıyor"), footnote: false, week: week) { muscle in
                        route = .exPicker(pid: pid, bid: nil, newFor: nil, group: muscle)
                    }
                } else {
                    WkEmpty(icon: "plus", title: "Bu program boş", text: "Aşağıdan hareket ekle.")
                }
                HStack(spacing: 8) {
                    Button { route = .exPicker(pid: pid, bid: nil, newFor: nil) } label: { BLabel("Hareket", icon: "plus") }.buttonStyle(.b(.primary, full: true))
                    Button { route = .blockForm(pid: pid, bid: nil) } label: { BLabel("Süperset", icon: "plus") }.buttonStyle(.b(.outline, full: true))
                }
                if !prog.blocks.allExercises.isEmpty {
                    Button { sharing = true } label: {
                        Label("Antrenmanı paylaş", systemImage: "square.and.arrow.up").font(.geist(15, .medium)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.b(.outline, full: true))
                }
                Text("Harekete dokununca set, tekrar, hedef kilo ve dinlenmeyi değiştirebilirsin. Geçmişte yaptığın antrenmanların kayıtları değişmez.")
                    .font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            .wkSheets($route)
            .sheet(isPresented: $sharing) { WkShareSheet(prog: prog).environment(app) }
        } else {
            Color.bBg.onAppear { dismiss() }
        }
    }
}

// MARK: - Workout sharing (QR · link · AirDrop) and import

/// Turns a program into short text: short-key JSON → zlib → base64url.
/// Link: https://gympaper.vercel.app/p#<data> (the site opens the app) · app scheme: gympaper://p?d=<data>
enum WkShare {
    static let host = "gympaper.vercel.app"
    static let site = "https://\(host)/p"
    static func payload(_ p: WorkoutProgram) -> String? { ProgramShare.encode(name: p.name, blocks: p.blocks) }
    static func link(_ p: WorkoutProgram) -> URL? { payload(p).flatMap { URL(string: "\(site)#\($0)") } }
    static func decode(_ s: String) -> (name: String, blocks: [Block])? { ProgramShare.decode(s) }

    /// Data from a link: gympaper://p?d=… · https://gympaper.vercel.app/p#…
    static func payload(from url: URL) -> String? {
        if url.scheme == "gympaper" {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "d" }?.value
        }
        // only our own domain: look-alikes such as "kotugympaper.vercel.app" are rejected
        if url.scheme == "https", url.host == WkShare.host, url.path == "/p" || url.path == "/p/" || url.path == "/p.html", let f = url.fragment, !f.isEmpty { return f }
        return nil
    }
    static func payload(fromText t: String) -> String? {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: s), let p = payload(from: u) { return p }
        return decode(s) != nil ? s : nil
    }

    static func qr(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Share: QR code, link (Messages, WhatsApp, AirDrop…) and copy
struct WkShareSheet: View {
    let prog: WorkoutProgram
    @Environment(AppState.self) private var app
    @State private var url: URL?
    @State private var qr: UIImage?
    @State private var qrFailed = false
    var body: some View {
        BSheet(title: "Antrenmanı paylaş", description: String(localized: "Arkadaşın QR kodu iPhone kamerasıyla okutunca ya da bağlantıya dokununca \(prog.name) GYM Paper'da açılır.")) {
            VStack(spacing: 12) {
                Group {
                    if let qr {
                        Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                            .padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
                            .accessibilityLabel("\(prog.name) için QR kod")
                    } else {
                        RoundedRectangle(cornerRadius: BRadius.card, style: .continuous).fill(Color.bMuted)
                            .overlay {
                                if qrFailed {
                                    Text("Program QR için çok büyük; bağlantıyı paylaşabilirsin.").font(.bSm).foregroundStyle(Color.bMutedFg)
                                        .multilineTextAlignment(.center).padding(24)
                                } else { ProgressView() }
                            }
                    }
                }
                .frame(maxWidth: 280).aspectRatio(1, contentMode: .fit)
                Text(prog.name).font(.geist(18, .semibold))
                Text("\(prog.blocks.allExercises.count) hareket").font(.bSm).foregroundStyle(Color.bMutedFg)
            }
            .frame(maxWidth: .infinity)
        } footer: {
            if let url {
                ShareLink(item: url, subject: Text(prog.name), message: Text("\(prog.name) antrenmanım — GYM Paper'da aç:")) {
                    BLabel("Bağlantıyı paylaş", icon: "share")
                }
                .buttonStyle(.b(.primary, .large, full: true))
                Button { UIPasteboard.general.url = url; haptic(); app.toast("Bağlantı kopyalandı") } label: { BLabel("Bağlantıyı kopyala", icon: "copy") }
                    .buttonStyle(.b(.outline, .large, full: true))
            }
        }
        .presentationDetents([.large])
        .task {
            guard url == nil else { return }
            guard let u = WkShare.link(prog) else { qrFailed = true; return }
            url = u
            qr = WkShare.qr(u.absoluteString)
            qrFailed = qr == nil
        }
    }
}

/// Preview a shared program and add it to My programs
struct WkImportSheet: View {
    let payload: String
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    /// Decoded once; not reopened on every render, and ids stay stable
    @State private var decoded: (name: String, blocks: [Block])??
    @State private var added = false
    var body: some View {
        let parsed: (name: String, blocks: [Block])? = decoded ?? nil
        Group {
        if decoded == nil {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else if let p = parsed {
            BSheet(title: p.name, description: String(localized: "Paylaşılan antrenman · \(p.blocks.allExercises.count) hareket")) {
                WkListCard {
                    ForEach(p.blocks) { b in
                        if b.kind == .single, let e = b.ex {
                            row(e)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Süperset · \(b.rounds) tur").font(.bXs).foregroundStyle(Color.bMutedFg).padding(.horizontal, 16).padding(.top, 10)
                                ForEach(b.exs) { e in row(e) }
                            }
                        }
                    }
                }
            } footer: {
                Button { add(p.name, p.blocks) } label: { BLabel("Antrenmanlarıma ekle", icon: "plus") }
                    .buttonStyle(.b(.primary, .large, full: true)).disabled(added)
            }
        } else {
            BSheet(title: "Bağlantı açılamadı") {
                Text("Bu bağlantı ya da QR kod geçerli bir GYM Paper antrenmanı içermiyor.").font(.bSm).foregroundStyle(Color.bMutedFg)
            }
        }
        }
        .task { if decoded == nil { decoded = .some(WkShare.decode(payload)) } }
    }
    private func row(_ e: Exercise) -> some View {
        HStack(spacing: 12) {
            WkThumb(name: e.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.geist(15, .medium)).lineLimit(1)
                Text(Wk.meta(e)).font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
    private func add(_ name: String, _ blocks: [Block]) {
        guard !added else { return }
        added = true
        let all = Wk.allPrograms(ctx).filter { !$0.archived }.map(\.name)
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = t.isEmpty ? "Paylaşılan antrenman" : t
        var n = base, k = 2
        while all.contains(n) { n = "\(base) (\(k))"; k += 1 }
        ctx.insert(WorkoutProgram(pid: UUID().uuidString, name: n, blocks: blocks))
        Store.save(ctx)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        app.toast(String(localized: "\(n) Antrenmanlarım'a eklendi"))
    }
}

/// Scan a QR code in the app
struct WkQRScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onPayload: (String) -> Void
    @State private var bad = false
    @State private var cam = CameraAccess.status()
    var body: some View {
        ZStack(alignment: .top) {
            if DataScannerViewController.isSupported && cam == .authorized {
                BarcodeScannerView(symbologies: [.qr]) { code in
                    if let p = WkShare.payload(fromText: code) { dismiss(); onPayload(p) } else { bad = true }
                }
                .ignoresSafeArea()
            } else {
                Text(cam == .notDetermined ? "" : cam == .authorized ? "Bu cihazda QR okuyucu kullanılamıyor. iPhone kamerasıyla okutabilirsin." : "Kamera izni yok. Ayarlar › GYM Paper'dan kameraya izin ver.").font(.bSm).foregroundStyle(Color.bMutedFg)
                    .multilineTextAlignment(.center).padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text(bad ? "Bu QR bir GYM Paper antrenmanı değil" : "Antrenman QR kodunu okut").font(.geist(15, .semibold))
                    .padding(.horizontal, 16).frame(height: 44).background(.ultraThinMaterial, in: Capsule())
                Spacer()
                Button { dismiss() } label: { Ti("x", size: 20) }.buttonStyle(.b(.outline, .iconLarge)).accessibilityLabel("Kapat")
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .task { cam = await CameraAccess.request() }
    }
}
