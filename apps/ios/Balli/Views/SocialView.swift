import SwiftUI
import Security
import BalliKit

// MARK: - Sosyal: arkadaşlarla adım sıralaması (SO-10…14, F1)
// Hesap yok: cihaz kendi rastgele kimliğini ve gizli anahtarını alır (Keychain). Sunucu: Supabase (supabase/social.sql).
// Paylaşılan tek sağlık verisi günlük adım sayısıdır; kullanıcının açık onayıyla gönderilir. iCloud'a yazılmaz (5.1.3).

enum SocialAPI {
    static let url = "https://YOUR-PROJECT-REF.supabase.co"
    // Herkese açık anon anahtar (web uygulamasında da görünür); tablolara doğrudan erişim kapalı, yalnız RPC
    static let anon = "YOUR_SUPABASE_ANON_KEY"

    struct APIError: LocalizedError {
        var code: String
        var errorDescription: String? {
            switch code {
            case "code": tl("Bu davet kodu bulunamadı.")
            case "self": tl("Kendi kodunu ekleyemezsin.")
            case "limit": tl("En fazla 100 arkadaş ekleyebilirsin.")
            case "name": tl("Ad 1–24 karakter olmalı.")
            case "auth": tl("Sosyal kaydın bulunamadı. Paylaşımı yeniden başlat.")
            default: tl("Sunucuya ulaşılamadı. Biraz sonra yeniden dene.")
            }
        }
    }

    static func rpc<T: Decodable>(_ fn: String, _ body: [String: Any], as: T.Type = T.self) async throws -> T {
        var r = URLRequest(url: URL(string: "\(url)/rest/v1/rpc/\(fn)")!)
        r.httpMethod = "POST"
        r.timeoutInterval = 15
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(anon, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: r)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // PostgREST hata gövdesi: {"message":"code", ...}
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw APIError(code: msg ?? "net")
        }
        if T.self == Empty.self { return Empty() as! T }
        return try JSONDecoder().decode(T.self, from: data)
    }
    struct Empty: Decodable {}
}

/// Kimlik bilgileri Keychain'de (cihazda kalır, yedeklenmez)
enum SocialKeychain {
    private static let service = "com.metehankaya.balli.social"
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
        var user_id: String; var name: String; var is_me: Bool; var today: Int; var week: Int; var days: [String: Int]
        var id: String { user_id }
    }
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

    /// Son 7 günün adımı; değişmediyse ya da 10 dk geçmediyse gönderilmez
    func push(_ steps: [String: Int], force: Bool = false) async {
        guard let me, !steps.isEmpty else { return }
        guard force || (steps != lastPushed && Date.now.timeIntervalSince(lastPush) > 600) else { return }
        do {
            let _: SocialAPI.Empty = try await SocialAPI.rpc("so_push_steps", ["p_id": me.id, "p_secret": me.secret, "p_days": steps])
            lastPush = .now; lastPushed = steps
        } catch { /* sessiz: bir sonraki açılışta yeniden denenir */ }
    }

    func refresh() async {
        guard let me else { rows = []; return }
        loading = rows.isEmpty; defer { loading = false }
        let today = DayKey.today
        let monday = DayKey.shift(today, days: -DayKey.weekday(today))
        do {
            rows = try await SocialAPI.rpc("so_board", ["p_id": me.id, "p_secret": me.secret, "p_today": today, "p_from": monday])
            error = nil
        } catch let e as SocialAPI.APIError where e.code == "auth" {
            // Sunucuda kayıt silinmiş: yerel kimliği de temizle
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
    /// Paylaşımı durdur: sunucudaki tüm kayıt ve arkadaşlıklar silinir
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
    @State private var social = SocialService.shared
    @State private var mode = 0          // 0: bugün, 1: bu hafta
    @State private var name = ""
    @State private var consent = false
    @State private var addOpen = false
    @State private var settingsOpen = false
    @State private var detail: SocialService.Row?
    @FocusState private var nameFocus: Bool

    private var sorted: [SocialService.Row] {
        social.rows.sorted { mode == 0 ? ($0.today, $1.name) > ($1.today, $0.name) : ($0.week, $1.name) > ($1.week, $0.name) }
    }

    var body: some View {
        BScreen {
            BHeader(title: "Sosyal") {
                if social.joined {
                    BRoundIcon(icon: "adjustments-horizontal", label: "Paylaşım ayarları") { settingsOpen = true }
                    BRoundIcon(icon: "plus", label: "Arkadaş ekle") { addOpen = true }
                }
            }
            if social.joined { board } else { intro }
            if let e = social.error {
                Label(e, systemImage: "exclamationmark.triangle").font(.bXs).foregroundStyle(Color.bDestructive)
            }
        }
        .task { await social.push(health.weekSteps); await social.refresh() }
        .refreshable { await health.refresh(); await social.push(health.weekSteps, force: true); await social.refresh() }
        .sheet(isPresented: $addOpen) { SocialAddSheet().presentationDetents([.medium]) }
        .sheet(isPresented: $settingsOpen) { SocialSettingsSheet().presentationDetents([.medium, .large]) }
        .sheet(item: $detail) { r in SocialFriendSheet(row: r).presentationDetents([.medium]) }
    }

    // İlk açılış: ad + açık onay
    @ViewBuilder private var intro: some View {
        BEmpty(symbol: "figure.walk", badge: "person.2.fill", title: "Arkadaşlarınla adım yarışı",
               text: "Arkadaşlarını davet et, günlük ve haftalık adımınızı bir sıralamada görün.", framed: false)
        VStack(alignment: .leading, spacing: 12) {
            Text("Görünen ad").font(.bSm.weight(.semibold)).foregroundStyle(Color.bFg)
            TextField("Örn. Mete", text: $name)
                .textInputAutocapitalization(.words).submitLabel(.done).focused($nameFocus)
                .font(.geist(17)).padding(.horizontal, 14).frame(height: 50)
                .background(Color.bMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: name) { _, v in if v.count > 24 { name = String(v.prefix(24)) } }
            Toggle(isOn: $consent) {
                Text("Günlük adım sayımın ve görünen adımın, yalnız davet ettiğim arkadaşlarımla paylaşılmasını kabul ediyorum.")
                    .font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            .tint(Color.bSuccess)
            Text("Kilo, ölçü, beslenme, oruç ve Sağlık'taki diğer veriler hiçbir zaman paylaşılmaz. Paylaşımı istediğin an durdurup verini silebilirsin.")
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
        Picker("Dönem", selection: $mode) { Text("Bugün").tag(0); Text("Bu hafta").tag(1) }
            .pickerStyle(.segmented)
        if social.rows.count <= 1 && !social.loading {
            BEmpty(symbol: "person.2", title: "Henüz arkadaşın yok",
                   text: "Davet kodunu paylaş ya da arkadaşının kodunu gir; sıralama burada görünür.",
                   action: "Arkadaş ekle") { addOpen = true }
        }
        VStack(spacing: 0) {
            let top = max(1, sorted.map { mode == 0 ? $0.today : $0.week }.max() ?? 1)
            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, r in
                Button { if !r.is_me { detail = r } } label: { row(r, rank: i + 1, top: top) }
                    .buttonStyle(.press)
                if i < sorted.count - 1 { Rectangle().fill(Color.bBorder).frame(height: 1).padding(.leading, 64) }
            }
            if social.loading && social.rows.isEmpty { ProgressView().padding(24) }
        }
        .bCard(padding: 0)
        .animation(.snappy, value: mode)
        .animation(.snappy, value: social.rows)
        if let me = social.me {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Davet kodun").font(.bXs).foregroundStyle(Color.bMutedFg)
                    Text(me.code).font(.bNum(26)).tracking(3).foregroundStyle(Color.bFg).textSelection(.enabled)
                }
                Spacer()
                ShareLink(item: String(localized: "GYM Paper'da adım sıralamasına katıl! Sosyal › + › davet kodu: \(me.code)\nhttps://apps.apple.com/app/gym-paper")) {
                    Label("Paylaş", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.b(.secondary))
            }
            .bCard()
            Text("Sıralama arkadaşlarının uygulamayı açmasıyla ya da arka planda güncellenir; adımlar Apple Sağlık'tan gelir.")
                .font(.bXs).foregroundStyle(Color.bMutedFg)
        }
    }

    private func row(_ r: SocialService.Row, rank: Int, top: Int) -> some View {
        let v = mode == 0 ? r.today : r.week
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
        .accessibilityLabel("\(rank). \(r.name)\(r.is_me ? tl(", sen") : ""), \(v) adım")
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

/// Arkadaş kodu gir
struct SocialAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var social = SocialService.shared
    @State private var code = ""
    @State private var busy = false
    @FocusState private var focus: Bool
    var body: some View {
        BSheet(title: "Arkadaş ekle") {
            Text("Arkadaşının Sosyal ekranındaki 6 haneli davet kodunu gir. Eklenince ikiniz de birbirinizi görürsünüz.")
                .font(.bSm).foregroundStyle(Color.bMutedFg)
            TextField("ABC234", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled().focused($focus)
                .font(.bNum(30)).tracking(4).multilineTextAlignment(.center)
                .frame(height: 64).background(Color.bMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

/// Arkadaş detayı: 7 günlük adım + arkadaşlıktan çıkar
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

/// Paylaşım ayarları: ad, kod yenile, paylaşımı durdur
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
                    .background(Color.bMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: name) { _, v in if v.count > 24 { name = String(v.prefix(24)) } }
                Button("Adı kaydet") { Task { await social.rename(name.trimmingCharacters(in: .whitespaces)); app.toast("Ad güncellendi") } }
                    .buttonStyle(.b(.secondary, .regular, full: true))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == social.me?.name)
            }
            .bCard()
            VStack(alignment: .leading, spacing: 6) {
                Text("Arkadaşların ne görür?").font(.bSm.weight(.semibold))
                Text("Yalnız görünen adın ve günlük adım sayın. Kilo, ölçü, beslenme, oruç ve antrenman detayları paylaşılmaz.")
                    .font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            .bCard()
            Button("Davet kodunu yenile") { Task { await social.newCode(); app.toast(String(localized: "Yeni kod: \(social.me?.code ?? "")")) } }
                .buttonStyle(.b(.secondary, .regular, full: true))
            Button("Paylaşımı durdur ve verimi sil", role: .destructive) { confirm = true }
                .buttonStyle(.b(.ghost, .regular, full: true)).bButtonFg(Color.bDestructive)
                .confirmationDialog("Paylaşım durdurulsun mu?", isPresented: $confirm, titleVisibility: .visible) {
                    Button("Durdur ve sil", role: .destructive) { Task { await social.leave(); dismiss(); app.toast("Sosyal verin silindi") } }
                } message: { Text("Adın, adım kayıtların ve arkadaşlıkların sunucudan silinir.") }
        }
    }
}
