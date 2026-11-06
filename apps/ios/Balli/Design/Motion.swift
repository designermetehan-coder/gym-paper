import SwiftUI
import SwiftData
import AVFoundation
import CoreImage
import BalliKit

// Hareket görselleri, iki kaynak:
// 1) MoveKit 3D video (ücretsiz örnek: Barfiks, Dambıl açış) — Resources/Motion/mk-<slug>.mp4/.jpg
// 2) free-exercise-db (Unlicense, kamu malı) — 106 hareket, 2 kare fotoğraf + Türkçe "Nasıl yapılır" (PWA ile aynı)
//    Resources/ExerciseMedia/<slug>-0.jpg, -1.jpg, ex-media.json. İki kare yumuşak geçişle dönüşümlü oynar.

enum Motion {
    /// Sessiz videolar müziği kesmesin (bir kez)
    private static var audioReady = false
    static func prepareAudio() {
        guard !audioReady else { return }; audioReady = true
        DispatchQueue.global(qos: .utility).async { try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers) }
    }
    /// Hareket adı (TR/EN, normalize) → MoveKit slug
    private static let map: [String: String] = [
        "barfiks": "pull-ups", "pull up": "pull-ups", "pull ups": "pull-ups", "pullup": "pull-ups", "barfix": "pull-ups",
        "dumbbell fly": "dumbbell-chest-fly", "dumbbell chest fly": "dumbbell-chest-fly", "dambil acis": "dumbbell-chest-fly",
        "dambil fly": "dumbbell-chest-fly", "dumbell fly": "dumbbell-chest-fly",
    ]

    /// MoveKit Complete Pack (MV-01): kütüphanedeki İngilizce ad → slug (Resources/mk-map.json)
    private static let mkMap: [String: String] = {
        guard let u = Bundle.main.url(forResource: "mk-map", withExtension: "json"), let d = try? Data(contentsOf: u),
              let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in m { out[TextNorm.norm(k)] = v }
        return out
    }()

    static func slug(for name: String) -> String? {
        let n = TextNorm.norm(name)
        if let s = map[n] ?? mkMap[n] ?? aliases[n].flatMap({ mkMap[$0] }) { return s }
        // "Barfiks (geniş tutuş)" gibi ekli adlar
        return map.first { n.hasPrefix($0.key + " ") }?.value
            ?? mkMap.first { n.hasPrefix($0.key + " ") }?.value
    }
    // MARK: free-exercise-db
    private struct Media: Decodable { let s: String; let tr: String }
    private static let media: [String: Media] = {
        guard let u = Bundle.main.url(forResource: "ex-media", withExtension: "json"), let d = try? Data(contentsOf: u) else { return [:] }
        return (try? JSONDecoder().decode([String: Media].self, from: d)) ?? [:]
    }()
    /// Kütüphanedeki Türkçe/diğer adlar → İngilizce ad (exercise-library.json `tr`)
    private static let aliases: [String: String] = {
        struct Lib: Decodable { struct E: Decodable { let name: String; let tr: [String]? }; let exercises: [E] }
        guard let u = Bundle.main.url(forResource: "exercise-library", withExtension: "json"), let d = try? Data(contentsOf: u),
              let lib = try? JSONDecoder().decode(Lib.self, from: d) else { return [:] }
        var m: [String: String] = [:]
        for e in lib.exercises { for a in e.tr ?? [] { m[TextNorm.norm(a)] = TextNorm.norm(e.name) } }
        return m
    }()
    private static func mediaEntry(_ name: String) -> Media? {
        let n = TextNorm.norm(name)
        return media[n] ?? aliases[n].flatMap { media[$0] }
    }
    private static let cache = NSCache<NSString, UIImage>()
    private static func image(_ file: String) -> UIImage? {
        if let i = cache.object(forKey: file as NSString) { return i }
        guard let u = Bundle.main.url(forResource: file, withExtension: "jpg"), let raw = UIImage(contentsOfFile: u.path) else { return nil }
        let i = raw.preparingForDisplay() ?? raw   // bir kez çöz
        cache.setObject(i, forKey: file as NSString); return i
    }
    // MARK: Kullanıcı görselleri (ExerciseMedia) — kendi eklediğin fotoğraflar önce gelir
    private static let userLock = NSLock()
    nonisolated(unsafe) private static var user: [String: [UIImage]] = [:]
    static func setUser(_ key: String, _ imgs: [UIImage], bump: Bool = true) {
        userLock.lock(); if imgs.isEmpty { user[key] = nil } else { user[key] = imgs }; userLock.unlock()
        if bump { UserMotion.bump() }
    }
    static func userFrames(_ name: String) -> [UIImage] {
        userLock.lock(); defer { userLock.unlock() }
        return user[TextNorm.norm(name)] ?? []
    }

    /// İki kare fotoğraf (başlangıç / bitiş pozisyonu)
    static func frames(_ name: String) -> [UIImage] {
        let u = userFrames(name); if !u.isEmpty { return u }
        guard let m = mediaEntry(name) else { return [] }
        return [0, 1].compactMap { image("\(m.s)-\($0)") }
    }
    /// Türkçe "Nasıl yapılır"
    static func howTo(_ name: String) -> String? { mediaEntry(name)?.tr }
    static func hasVisual(_ name: String) -> Bool { !userFrames(name).isEmpty || slug(for: name) != nil || mediaEntry(name) != nil }

    static func videoURL(_ name: String) -> URL? {
        if !userFrames(name).isEmpty { return nil }   // kullanıcının fotoğrafı varsa o gösterilir
        return slug(for: name).flatMap { Bundle.main.url(forResource: "mk-\($0)", withExtension: "mp4") }
    }
    /// Liste küçük resmi: önceden çözülmüş, küçültülmüş ve önbellekli (kaydırırken her karede JPEG çözülmesin)
    private static let thumbCache = NSCache<NSString, UIImage>()
    static func thumb(_ name: String, side: CGFloat) -> UIImage? {
        let key = "\(TextNorm.norm(name))|\(Int(side))|\(UserMotion.versionSnapshot)" as NSString
        if let t = thumbCache.object(forKey: key) { return t }
        guard let p = poster(name) else { return nil }
        let px = side * 3
        let k = px / min(p.size.width, p.size.height)
        let size = CGSize(width: (p.size.width * k).rounded(), height: (p.size.height * k).rounded())
        let t = p.preparingThumbnail(of: size) ?? p
        thumbCache.setObject(t, forKey: key)
        return t
    }
    static func poster(_ name: String) -> UIImage? {
        if let u = userFrames(name).first { return u }
        if let s = slug(for: name), let i = image("mk-\(s)") { return i }
        return frames(name).first
    }
}

/// Sessiz, döngüde oynayan hareket videosu (ilk karede poster; Hareketi Azalt açıksa yalnız poster)
struct MotionPlayer: View {
    let name: String
    var height: CGFloat = 200
    /// Fotoğrafları kutuyu dolduracak şekilde kırp (müzik çalar kapağı gibi)
    var fill = false
    /// Antrenman duraklatılınca hareket de durur (son karede kalır) (4 Kas)
    var paused = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme
    @State private var ready = false

    var body: some View {
        let _ = UserMotion.shared.version
        if let url = Motion.videoURL(name) {
            // Doldururken video kutuyu kaplar: üstte/altta açık bant kalmaz (TE-02)
            Color.clear.overlay {
                ZStack {
                    Group {
                        Color(white: 0.94)
                        if let p = Motion.poster(name) { Image(uiImage: p).resizable().aspectRatio(contentMode: fill ? .fill : .fit) }
                    }
                    if !reduce {
                        LoopingVideo(url: url, fill: fill, paused: paused, ready: $ready).opacity(ready ? 1 : 0)
                            .animation(.easeOut(duration: 0.25), value: ready)
                    }
                }
            }
            .frame(maxWidth: .infinity).frame(height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityLabel("\(name) hareket animasyonu")
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            let f = Motion.frames(name)
            if !f.isEmpty {
                // Fotoğraflar 3D görsellerle aynı dilde: gri tonlu, aynı açık zemin (TE-01); koyu temada parlamasın (TE-02)
                FramePlayer(frames: f, animate: !reduce && !paused, fill: fill)
                    .grayscale(1).contrast(1.05)
                    .frame(maxWidth: .infinity).frame(height: height)
                    .clipped()
                    .background(Color(white: 0.94))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityLabel("\(name) hareket görseli")
            }
        }
    }
}

/// İki kareyi yumuşak geçişle dönüşümlü gösterir (hareketin başı ve sonu)
private struct FramePlayer: View {
    let frames: [UIImage]
    var animate = true
    var fill = false
    @State private var i = 0
    var body: some View {
        // Color.clear önerilen boyutu aynen alır; görsel taşmaz (doldurunca kırpılır)
        Color.clear.overlay {
            ZStack {
                ForEach(frames.indices, id: \.self) { k in
                    Image(uiImage: frames[k]).resizable().aspectRatio(contentMode: fill ? .fill : .fit).opacity(k == i ? 1 : 0)
                }
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.45), value: i)
        .task(id: animate) {
            guard animate, frames.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.1))
                i = (i + 1) % frames.count
            }
        }
    }
}

/// Liste küçük resmi: varsa poster, yoksa nötr kutu
struct MotionThumb: View {
    let name: String?
    var size: CGFloat = 56
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let _ = UserMotion.shared.version
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.bMuted).frame(width: size, height: size)
            .overlay {
                if let name, let p = Motion.thumb(name, side: size) {
                    // Fotoğraf küçük resimleri gri tonlu: 3D görsellerle karışık durmasın (TE-01)
                    let mk = Motion.videoURL(name) != nil
                    Image(uiImage: p).resizable().scaledToFill().frame(width: size, height: size)
                        .grayscale(mk ? 0 : 1)
                        .background(Color(white: 0.94))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    // Görseli olmayan hareket: boş dambıl yerine nötr figür silüeti (TE-01)
                    Image(systemName: "figure.strengthtraining.traditional").font(.system(size: size * 0.42, weight: .regular))
                        .foregroundStyle(Color.bMutedFg.opacity(0.55))
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct LoopingVideo: UIViewRepresentable {
    let url: URL
    var fill = false
    var invert = false
    var paused = false
    @Binding var ready: Bool

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        Motion.prepareAudio()
        let item = AVPlayerItem(url: url)
        if invert {
            // Ters renk + ton 180°: kırmızı vurgu kırmızı kalır (MV-03)
            let asset = item.asset
            item.videoComposition = AVVideoComposition(asset: asset) { req in
                // Core Image doğrusal renk uzayında çalışır; ters çevirme sRGB'de yapılmazsa zemin siyah değil gri kalır
                let srgb = req.sourceImage.applyingFilter("CILinearToSRGBToneCurve")
                let inv = srgb.applyingFilter("CIColorInvert").applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: Double.pi])
                let out = inv.applyingFilter("CISRGBToneCurveToLinear")
                req.finish(with: out.cropped(to: req.sourceImage.extent), context: nil)
            }
        }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        v.layer2.player = player
        v.layer2.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        context.coordinator.obs = v.layer2.observe(\.isReadyForDisplay, options: [.new]) { l, _ in
            if l.isReadyForDisplay { DispatchQueue.main.async { ready = true } }
        }
        if !paused { player.play() }
        return v
    }
    func updateUIView(_ v: PlayerView, context: Context) {
        guard let p = v.layer2.player else { return }
        if paused { if p.rate != 0 { p.pause() } } else if p.rate == 0 { p.play() }
    }
    static func dismantleUIView(_ v: PlayerView, coordinator: Coordinator) { v.layer2.player?.pause(); coordinator.obs = nil }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var looper: AVPlayerLooper?; var obs: NSKeyValueObservation? }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var layer2: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}


/// Kullanıcı görsellerinin yüklenmesi/kaydı; `version` değişince görünümler yenilenir
@MainActor @Observable
final class UserMotion {
    static let shared = UserMotion()
    var version = 0
    /// Önbellek anahtarı için gözlemlenmeyen kopya
    nonisolated(unsafe) static var versionSnapshot = 0
    nonisolated static func bump() {
        versionSnapshot += 1
        Task { @MainActor in UserMotion.shared.version += 1 }
    }

    /// Yalnız değişen hareket görselleri yüklenir; görünümler bir kez yenilenir (CR-41)
    @ObservationIgnored private var loadedAt: [String: Date] = [:]
    func load(_ ctx: ModelContext) {
        let all = (try? ctx.fetch(FetchDescriptor<ExerciseMedia>())) ?? []
        let changed = all.filter { loadedAt[$0.key] != $0.updatedAt }
        guard !changed.isEmpty else { return }
        for m in changed { loadedAt[m.key] = m.updatedAt }
        let raw = changed.map { ($0.key, [$0.frame0, $0.frame1].compactMap { $0 }) }
        Task.detached(priority: .utility) {
            for (key, datas) in raw { Motion.setUser(key, datas.compactMap(UIImage.init(data:)), bump: false) }
            UserMotion.bump()
        }
    }

    /// Fotoğrafları küçültüp kaydeder (en çok 900 px, JPEG)
    func save(name: String, frames: [UIImage], ctx: ModelContext) {
        let key = TextNorm.norm(name)
        let data = frames.prefix(2).compactMap { Self.shrink($0)?.jpegData(compressionQuality: 0.78) }
        let all = (try? ctx.fetch(FetchDescriptor<ExerciseMedia>())) ?? []
        let m = all.first { $0.key == key } ?? { let x = ExerciseMedia(key: key); ctx.insert(x); return x }()
        if data.isEmpty { ctx.delete(m) } else {
            m.frame0 = data.first; m.frame1 = data.count > 1 ? data[1] : nil; m.updatedAt = .now
        }
        Store.save(ctx)
        Motion.setUser(key, data.compactMap(UIImage.init(data:)))
    }

    nonisolated static func shrink(_ img: UIImage, max side: CGFloat = 900) -> UIImage? {
        let s = img.size; let k = min(1, side / max(s.width, s.height))
        let size = CGSize(width: (s.width * k).rounded(), height: (s.height * k).rounded())
        let f = UIGraphicsImageRendererFormat.default(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

private extension View {
    /// Açık zeminli hareket görseli koyu temada beyaz blok gibi parlamasın (TE-02)
    func darkDim(_ scheme: ColorScheme) -> some View { colorMultiply(scheme == .dark ? Color(white: 0.8) : .white) }

}


extension View {
    /// MoveKit görselleri koyu temada ters çevrilir: zemin siyah, manken açık gri, kırmızı kas vurgusu korunur (MV-03)
    @ViewBuilder func mkInvert(_ on: Bool) -> some View { if on { colorInvert().hueRotation(.degrees(180)) } else { self } }
}
