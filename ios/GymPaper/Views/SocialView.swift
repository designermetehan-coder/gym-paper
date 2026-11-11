import SwiftUI
import Security
import GymPaperKit

// MARK: - Team: workouts and steps with friends (1.2)
// No account: the device gets its own random id and secret (Keychain). Server: Supabase (supabase/social.sql).
// Shared data: display name, daily step count and whether a workout was done that day — with explicit consent.
// Never written to iCloud (5.1.3).

enum SocialAPI {
    /// The backend only comes from Config; without it Team is unavailable
    static var backend: AppConfig.Backend? { AppConfig.backend }

    struct APIError: LocalizedError {
        var code: String
        var errorDescription: String? {
            switch code {
            case "code": tl("Bu davet kodu bulunamadı.")
            case "self": tl("Kendi kodunu ekleyemezsin.")
            case "limit": tl("En fazla 100 arkadaş ekleyebilirsin.")
            case "name": tl("Ad 1–24 karakter olmalı.")
            case "auth": tl("Ekip kaydın bulunamadı. Paylaşımı yeniden başlat.")
            case "off": tl("Ekip bu sürümde kapalı.")
            default: tl("Sunucuya ulaşılamadı. Biraz sonra yeniden dene.")
            }
        }
    }

    static func rpc<T: Decodable>(_ fn: String, _ body: [String: Any], as: T.Type = T.self) async throws -> T {
        guard let be = backend else { throw APIError(code: "off") }
        var r = URLRequest(url: be.url.appendingPathComponent("rest/v1/rpc/\(fn)"))
        r.httpMethod = "POST"
        r.timeoutInterval = 15
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(be.anonKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(be.anonKey)", forHTTPHeaderField: "Authorization")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: r)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // PostgREST error body: {"message":"code", ...}
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw APIError(code: msg ?? "net")
        }
        if T.self == Empty.self { return Empty() as! T }
        return try JSONDecoder().decode(T.self, from: data)
    }
    struct Empty: Decodable {}
}

/// Credentials live in the Keychain (stay on device, not backed up)
enum SocialKeychain {
    private static let service = "\(AppConfig.bundleBase).social"
    static func save(_ s: SocialService.Identity?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "identity"]
        SecItemDelete(q as CFDictionary)
        guard let s, let data = try? JSONEncoder().encode(s) else { return }
        var add = q; add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
    static func load() -> SocialService.Identity? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "identity",
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(SocialService.Identity.self, from: d)
    }
}

@MainActor @Observable
final class SocialService {
    static let shared = SocialService()
    struct Identity: Codable, Equatable { var id: String; var secret: String; var code: String; var name: String }
    struct Row: Decodable, Identifiable, Equatable {
        var user_id: String; var name: String; var is_me: Bool
        var steps_day: Int; var steps_week: Int; var steps_month: Int; var steps_all: Int
        var wk_day: Int; var wk_week: Int; var wk_month: Int; var wk_all: Int
        var days: [String: Int]
        var id: String { user_id }
        var today: Int { steps_day }
        var week: Int { steps_week }
        func value(_ p: Period, _ m: Metric) -> Int {
            switch (p, m) {
            case (.day, .steps): steps_day; case (.week, .steps): steps_week; case (.month, .steps): steps_month; case (.all, .steps): steps_all
            case (.day, .workouts): wk_day; case (.week, .workouts): wk_week; case (.month, .workouts): wk_month; case (.all, .workouts): wk_all
            }
        }
    }
    enum Period: Int, CaseIterable, Hashable { case day, week, month, all }
    enum Metric: Int, Hashable { case steps, workouts }
    /// Finished workouts per day (last 14 days), filled by the app before a push
    var workouts: [String: Int] = [:]
    private(set) var me: Identity? = SocialKeychain.load()
    var rows: [Row] = []
    var loading = false
    var error: String?
    private var lastPush: Date = .distantPast
    private var lastPushed: [String: Int] = [:]

    var joined: Bool { me != nil }

    func join(name: String, steps: [String: Int]) async {
        error = nil; loading = true; defer { loading = false }
        do {
            struct R: Decodable { var id: String; var secret: String; var code: String }
            let r: [R] = try await SocialAPI.rpc("so_register", ["p_name": name.trimmingCharacters(in: .whitespacesAndNewlines)])
            guard let x = r.first else { throw SocialAPI.APIError(code: "net") }
            let id = Identity(id: x.id, secret: x.secret, code: x.code, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            SocialKeychain.save(id); me = id
            await push(steps, force: true)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    /// Steps and workouts of recent days; skipped when nothing changed or within 10 minutes
    func push(_ steps: [String: Int], force: Bool = false) async {
        guard let me else { return }
        var payload: [String: [String: Int]] = [:]
        for (d, n) in steps { payload[d, default: [:]]["s"] = n }
        for (d, n) in workouts { payload[d, default: [:]]["w"] = n }
        guard !payload.isEmpty else { return }
        let sig = payload.mapValues { ($0["s"] ?? 0) * 100 + ($0["w"] ?? 0) }
        guard force || (sig != lastPushed && Date.now.timeIntervalSince(lastPush) > 600) else { return }
        do {
            let _: SocialAPI.Empty = try await SocialAPI.rpc("so_push", ["p_id": me.id, "p_secret": me.secret, "p_days": payload])
            lastPush = .now; lastPushed = sig
        } catch { /* silent: retried on next open */ }
    }
    /// Done workouts of the last 14 days from the local log
    func loadWorkouts(_ days: [DayLog]) {
        let from = DayKey.shift(DayKey.today, days: -14)
        var w: [String: Int] = [:]
        for d in days where d.date >= from && d.workoutDone { w[d.date] = 1 }
        workouts = w
    }

    func refresh() async {
        guard let me else { rows = []; return }
        loading = rows.isEmpty; defer { loading = false }
        let today = DayKey.today
        let monday = DayKey.shift(today, days: -DayKey.weekday(today))
        let month = String(today.prefix(8)) + "01"
        do {
            rows = try await SocialAPI.rpc("so_board2", ["p_id": me.id, "p_secret": me.secret, "p_today": today, "p_week": monday, "p_month": month])
            error = nil
        } catch let e as SocialAPI.APIError where e.code == "auth" {
            // record deleted on the server: clear the local identity too
            SocialKeychain.save(nil); self.me = nil; rows = []
        } catch { self.error = error.localizedDescription }
    }

    func addFriend(code: String) async -> String? {
        guard let me else { return nil }
        do {
            let name: String = try await SocialAPI.rpc("so_add_friend", ["p_id": me.id, "p_secret": me.secret, "p_code": code])
            await refresh(); return name
        } catch { self.error = error.localizedDescription; return nil }
    }
    func remove(_ r: Row) async {
        guard let me else { return }
        rows.removeAll { $0.id == r.id }
        do { let _: SocialAPI.Empty = try await SocialAPI.rpc("so_remove_friend", ["p_id": me.id, "p_secret": me.secret, "p_friend": r.user_id]) }
        catch { self.error = error.localizedDescription; await refresh() }
    }
    func rename(_ name: String) async {
        guard var me else { return }
        do {
            let _: SocialAPI.Empty = try await SocialAPI.rpc("so_rename", ["p_id": me.id, "p_secret": me.secret, "p_name": name])
            me.name = name; SocialKeychain.save(me); self.me = me; await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func newCode() async {
        guard var me else { return }
        do {
            let c: String = try await SocialAPI.rpc("so_new_code", ["p_id": me.id, "p_secret": me.secret])
            me.code = c; SocialKeychain.save(me); self.me = me
        } catch { self.error = error.localizedDescription }
    }
    #if DEBUG
    /// Screenshots (-demo): a sample team without the server
    func seedDemo() {
        guard rows.isEmpty else { return }
        me = Identity(id: "me", secret: "", code: "GP7K2Q", name: "Alex")
        func days(_ base: Int) -> [String: Int] {
            Dictionary(uniqueKeysWithValues: (0..<14).map { (DayKey.shift(DayKey.today, days: -$0), base + ($0 * 731) % 4200) })
        }
        func r(_ id: String, _ n: String, me: Bool, _ s: (Int, Int, Int, Int), _ w: (Int, Int, Int, Int), _ b: Int) -> Row {
            Row(user_id: id, name: n, is_me: me, steps_day: s.0, steps_week: s.1, steps_month: s.2, steps_all: s.3,
                wk_day: w.0, wk_week: w.1, wk_month: w.2, wk_all: w.3, days: days(b))
        }
        rows = [r("me", "Alex", me: true, (9840, 61230, 214560, 1204300), (1, 4, 15, 92), 7000),
                r("a", "Ayla", me: false, (11420, 68410, 236100, 998700), (1, 4, 14, 61), 8200),
                r("c", "Can", me: false, (7310, 48950, 201800, 1450200), (0, 3, 12, 118), 5600),
                r("d", "Deniz", me: false, (5120, 39870, 166400, 640300), (0, 2, 9, 40), 4300),
                r("e", "Elif", me: false, (12960, 74200, 251900, 1310000), (1, 5, 17, 104), 9100)]
    }
    #endif
    /// Stop sharing: every record and friendship on the server is deleted
    func leave() async {
        guard let me else { return }
        do { let _: SocialAPI.Empty = try await SocialAPI.rpc("so_delete", ["p_id": me.id, "p_secret": me.secret]) } catch {}
        SocialKeychain.save(nil); self.me = nil; rows = []
    }
}

// MARK: - Ekran

struct SocialView: View {
    @Environment(HealthService.self) private var health
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var social = SocialService.shared
    @State private var period = SocialService.Period.week
    @State private var metric = SocialService.Metric.workouts
    @State private var name = ""
    @State private var consent = false
    @State private var addOpen = false
    @State private var settingsOpen = false
    @State private var detail: SocialService.Row?
    @FocusState private var nameFocus: Bool
    /// Pushed from somewhere (back button); as the Team tab it is the root
    var pushed = false

    private var sorted: [SocialService.Row] {
        social.rows.sorted { ($0.value(period, metric), $1.name) > ($1.value(period, metric), $0.name) }
    }

    var body: some View {
        BScreen {
            VStack(alignment: .leading, spacing: 0) {
                if pushed { BRoundIcon(icon: "chevron-left", label: "Geri") { dismiss() }.padding(.top, 4) }
                BHeader(title: "Ekip") {
                    if social.joined {
                        BRoundIcon(icon: "adjustments-horizontal", label: "Paylaşım ayarları") { settingsOpen = true }
                        BRoundIcon(icon: "plus", label: "Arkadaş ekle") { addOpen = true }
                    }
                }
            }
            if social.joined { board } else { intro }
            if let e = social.error {
                Label(e, systemImage: "exclamationmark.triangle").font(.bXs).foregroundStyle(Color.bDestructive)
            }
        }
        .task {
            #if DEBUG
            if DemoData.active { social.seedDemo(); return }
            #endif
            social.loadWorkouts(Wk.allDays(ctx)); await social.push(health.weekSteps); await social.refresh()
        }
        .refreshable { await health.refresh(); social.loadWorkouts(Wk.allDays(ctx)); await social.push(health.weekSteps, force: true); await social.refresh() }
        .sheet(isPresented: $addOpen) { SocialAddSheet().presentationDetents([.medium]) }
        .sheet(isPresented: $settingsOpen) { SocialSettingsSheet().presentationDetents([.medium, .large]) }
        .sheet(item: $detail) { r in SocialFriendSheet(row: r).presentationDetents([.medium]) }
    }

    // first open: name + explicit consent
    @ViewBuilder private var intro: some View {
        BEmpty(symbol: "figure.strengthtraining.traditional", badge: "person.2.fill", title: "Eşin ve arkadaşlarınla ekip",
               text: "Davet ettiğin kişilerle antrenmanlarınızı ve adımlarınızı günlük, haftalık, aylık ve tüm zamanlar için bir sıralamada görün.", framed: false)
        VStack(alignment: .leading, spacing: 12) {
            Text("Görünen ad").font(.bSm.weight(.semibold)).foregroundStyle(Color.bFg)
            TextField("Örn. Alex", text: $name)
                .textInputAutocapitalization(.words).submitLabel(.done).focused($nameFocus)
                .font(.geist(17)).padding(.horizontal, 14).frame(height: 50)
                .background(Color.bMuted, in: RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
                .onChange(of: name) { _, v in if v.count > 24 { name = String(v.prefix(24)) } }
            Toggle(isOn: $consent) {
                Text("Görünen adımın, günlük adım sayımın ve antrenman yapıp yapmadığımın yalnız davet ettiğim kişilerle paylaşılmasını kabul ediyorum.")
                    .font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            .tint(Color.bSuccess)
            Text("Kilo, ölçü, beslenme, oruç, antrenman detayları ve Sağlık'taki diğer veriler hiçbir zaman paylaşılmaz. Paylaşımı istediğin an durdurup verini silebilirsin.")
                .font(.bXs).foregroundStyle(Color.bMutedFg)
            Button {
                nameFocus = false
                Task { await health.refresh(); await social.join(name: name, steps: health.weekSteps) }
            } label: {
                HStack { if social.loading { ProgressView().tint(Color.bActionFg) }; Text("Paylaşmaya başla") }
            }
            .buttonStyle(.b(.primary, .large, full: true))
            .disabled(!consent || name.trimmingCharacters(in: .whitespaces).isEmpty || social.loading)
        }
        .bCard()
    }

    @ViewBuilder private var board: some View {
        BSegmented(selection: $metric, options: [(.workouts, "Antrenman"), (.steps, "Adım")])
        HStack(spacing: 8) {
            ForEach(SocialService.Period.allCases, id: \.self) { p in
                Button { haptic(); withAnimation(.snappy) { period = p } } label: {
                    Text(periodTitle(p)).font(.geist(14, .medium, relativeTo: .subheadline))
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .foregroundStyle(period == p ? Color.bSelFg : Color.bFg)
                        .background(period == p ? AnyShapeStyle(Color.bSel) : AnyShapeStyle(Color.bCard.opacity(0.6)), in: Capsule())
                }
                .buttonStyle(.press)
                .accessibilityAddTraits(period == p ? .isSelected : [])
            }
        }
        if social.rows.count <= 1 && !social.loading {
            BEmpty(symbol: "person.2", title: "Henüz arkadaşın yok",
                   text: "Davet kodunu paylaş ya da arkadaşının kodunu gir; sıralama burada görünür.",
                   action: "Arkadaş ekle") { addOpen = true }
        }
        VStack(spacing: 0) {
            let top = max(1, sorted.map { $0.value(period, metric) }.max() ?? 1)
            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, r in
                Button { if !r.is_me { detail = r } } label: { row(r, rank: i + 1, top: top) }
                    .buttonStyle(.press)
                if i < sorted.count - 1 { Rectangle().fill(Color.bBorder).frame(height: 1).padding(.leading, 64) }
            }
            if social.loading && social.rows.isEmpty { ProgressView().padding(24) }
        }
        .bCard(padding: 0)
        .animation(.snappy, value: period)
        .animation(.snappy, value: metric)
        .animation(.snappy, value: social.rows)
        if let me = social.me {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Davet kodun").font(.bXs).foregroundStyle(Color.bMutedFg)
                    Text(me.code).font(.bNum(26)).tracking(3).foregroundStyle(Color.bFg).textSelection(.enabled)
                }
                Spacer()
                ShareLink(item: String(localized: "GYM Paper'da ekibime katıl! Ekip › + › davet kodu: \(me.code)\nhttps://apps.apple.com/app/id6826874026")) {
                    Label("Paylaş", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.b(.secondary))
            }
            .bCard()
            Text("Sıralama, ekip üyeleri uygulamayı açtıkça ya da arka planda güncellenir; adımlar Apple Sağlık'tan gelir.")
                .font(.bXs).foregroundStyle(Color.bMutedFg)
        }
    }

    private func periodTitle(_ p: SocialService.Period) -> String {
        switch p { case .day: tl("Gün"); case .week: tl("Hafta"); case .month: tl("Ay"); case .all: tl("Tüm zamanlar") }
    }

    private func row(_ r: SocialService.Row, rank: Int, top: Int) -> some View {
        let v = r.value(period, metric)
        return HStack(spacing: 12) {
            Text("\(rank)").font(.bNum(16)).foregroundStyle(rank == 1 ? Color.bFg : Color.bMutedFg).frame(width: 18)
            SocialAvatar(name: r.name, me: r.is_me)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(r.name).font(.geist(16, .semibold)).foregroundStyle(Color.bFg).lineLimit(1)
                    if r.is_me { Text("Sen").font(.geist(11, .bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.bAction, in: Capsule()).foregroundStyle(Color.bActionFg) }
                    if rank == 1 && v > 0 { Image(systemName: "crown.fill").font(.system(size: 12)).foregroundStyle(Color(red: 0.95, green: 0.7, blue: 0.1)) }
                }
                GeometryReader { g in
                    Capsule().fill(Color.bFg.opacity(0.08))
                        .overlay(alignment: .leading) { Capsule().fill(r.is_me ? Color.bAction : Color.bPrimary).frame(width: max(6, g.size.width * CGFloat(v) / CGFloat(top))) }
                }
                .frame(height: 6)
            }
            Text(v.formatted(.number.locale(.current))).font(.bNum(20)).monospacedDigit().foregroundStyle(Color.bFg)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(r.is_me ? Color.bAction.opacity(0.12) : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank). \(r.name)\(r.is_me ? tl(", sen") : ""), \(v) \(metric == .steps ? tl("adım") : tl("antrenman"))")
    }
}

struct SocialAvatar: View {
    var name: String; var me = false; var size: CGFloat = 40
    private static let palette: [Color] = [.init(red: 0.88, green: 0.08, blue: 0.3), .init(red: 0.04, green: 0.48, blue: 0.88), .init(red: 0.48, green: 0.25, blue: 0.95), .init(red: 0.12, green: 0.62, blue: 0.24), .init(red: 0.9, green: 0.45, blue: 0.05)]
    var body: some View {
        let c = me ? Color.bPrimary : Self.palette[abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % Self.palette.count]
        Text(String(name.prefix(1)).uppercased(with: .current))
            .font(.geist(size * 0.4, .bold)).foregroundStyle(me ? Color.bPrimaryFg : .white)
            .frame(width: size, height: size).background(c, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Enter a friend's code
struct SocialAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var social = SocialService.shared
    @State private var code = ""
    @State private var busy = false
    @FocusState private var focus: Bool
    var body: some View {
        BSheet(title: "Arkadaş ekle") {
            Text("Ekip arkadaşının Ekip sekmesindeki 6 haneli davet kodunu gir. Eklenince ikiniz de birbirinizi görürsünüz.")
                .font(.bSm).foregroundStyle(Color.bMutedFg)
            TextField("ABC234", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled().focused($focus)
                .font(.bNum(30)).tracking(4).multilineTextAlignment(.center)
                .frame(height: 64).background(Color.bMuted, in: RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
                .onChange(of: code) { _, v in let f = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6)); if f != v { code = f } }
            Button {
                busy = true
                Task {
                    if let n = await social.addFriend(code: code) { dismiss(); app.toast(String(localized: "\(n) eklendi")) }
                    busy = false
                }
            } label: { HStack { if busy { ProgressView().tint(Color.bActionFg) }; Text("Ekle") } }
            .buttonStyle(.b(.primary, .large, full: true))
            .disabled(code.count != 6 || busy)
            if let e = social.error { Text(e).font(.bXs).foregroundStyle(Color.bDestructive) }
        }
        .onAppear { social.error = nil; focus = true }
    }
}

/// Friend detail: 7 days of steps + remove friend
struct SocialFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    var row: SocialService.Row
    @State private var confirm = false
    var body: some View {
        let today = DayKey.today
        let keys = (0..<7).map { DayKey.shift(today, days: $0 - 6) }
        let top = max(1, keys.map { row.days[$0] ?? 0 }.max() ?? 1)
        BSheet(title: row.name) {
            HStack(spacing: 8) {
                stat("Bugün", row.today); stat("Bu hafta", row.week)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(keys, id: \.self) { k in
                    let v = row.days[k] ?? 0
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6).fill(k == today ? Color.bAction : Color.bPrimary.opacity(0.85))
                            .frame(height: max(4, 110 * CGFloat(v) / CGFloat(top)))
                        Text(Self.short(k)).font(.bXs).foregroundStyle(Color.bMutedFg)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(Self.short(k)): \(v) adım")
                }
            }
            .frame(height: 140, alignment: .bottom)
            .bCard()
            Button("Arkadaşlıktan çıkar", role: .destructive) { confirm = true }
                .buttonStyle(.b(.ghost, .regular, full: true)).bButtonFg(Color.bDestructive)
                .confirmationDialog("\(row.name) arkadaşlıktan çıkarılsın mı?", isPresented: $confirm, titleVisibility: .visible) {
                    Button("Çıkar", role: .destructive) { Task { await SocialService.shared.remove(row); dismiss(); app.toast(String(localized: "\(row.name) çıkarıldı")) } }
                } message: { Text("Birbirinizi artık görmezsiniz. Yeniden eklemek için yeni bir davet kodu gerekir.") }
        }
    }
    static func short(_ k: String) -> String { DayKey.dayShort[max(0, min(6, DayKey.weekday(k)))] }
    private func stat(_ t: String, _ v: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tl(t)).font(.bXs).foregroundStyle(Color.bMutedFg)
            Text(v.formatted(.number.locale(.current))).font(.bNum(26)).foregroundStyle(Color.bFg)
            Text("adım").font(.bXs).foregroundStyle(Color.bMutedFg)
        }
        .bCard()
    }
}

/// Sharing settings: name, new code, stop sharing
struct SocialSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var social = SocialService.shared
    @State private var name = SocialService.shared.me?.name ?? ""
    @State private var confirm = false
    var body: some View {
        BSheet(title: "Paylaşım") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Görünen ad").font(.bSm.weight(.semibold))
                TextField("Ad", text: $name).font(.geist(17)).padding(.horizontal, 14).frame(height: 50)
                    .background(Color.bMuted, in: RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
                    .onChange(of: name) { _, v in if v.count > 24 { name = String(v.prefix(24)) } }
                Button("Adı kaydet") { Task { await social.rename(name.trimmingCharacters(in: .whitespaces)); app.toast("Ad güncellendi") } }
                    .buttonStyle(.b(.secondary, .regular, full: true))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == social.me?.name)
            }
            .bCard()
            VStack(alignment: .leading, spacing: 6) {
                Text("Arkadaşların ne görür?").font(.bSm.weight(.semibold))
                Text("Yalnız görünen adın, günlük adım sayın ve o gün antrenman yapıp yapmadığın. Kilo, ölçü, beslenme, oruç ve antrenman detayları paylaşılmaz.")
                    .font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            .bCard()
            Button("Davet kodunu yenile") { Task { await social.newCode(); app.toast(String(localized: "Yeni kod: \(social.me?.code ?? "")")) } }
                .buttonStyle(.b(.secondary, .regular, full: true))
            Button("Paylaşımı durdur ve verimi sil", role: .destructive) { confirm = true }
                .buttonStyle(.b(.ghost, .regular, full: true)).bButtonFg(Color.bDestructive)
                .confirmationDialog("Paylaşım durdurulsun mu?", isPresented: $confirm, titleVisibility: .visible) {
                    Button("Durdur ve sil", role: .destructive) { Task { await social.leave(); dismiss(); app.toast("Ekip verin silindi") } }
                } message: { Text("Adın, adım kayıtların ve arkadaşlıkların sunucudan silinir.") }
        }
    }
}
