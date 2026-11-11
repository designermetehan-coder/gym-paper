import SwiftUI
import SwiftData
import AVFoundation
import CoreHaptics
import CoreImage
import GymPaperKit

// Exercise visuals, two sources:
// 1) MoveKit 3D video (licensed; not in the open-source repo) — Resources/Motion/mk-<slug>.mp4/.jpg
// 2) free-exercise-db (Unlicense, public domain) — 106 exercises, two photos + a "how to"
//    Resources/ExerciseMedia/<slug>-0.jpg, -1.jpg, ex-media.json. The two frames alternate with a soft crossfade.

enum Motion {
    /// Silent videos must not interrupt music (set once)
    private static var audioReady = false
    static func prepareAudio() {
        guard !audioReady else { return }; audioReady = true
        DispatchQueue.global(qos: .utility).async { try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers) }
    }
    /// Exercise name (TR/EN, normalized) → MoveKit slug
    private static let map: [String: String] = [
        "barfiks": "pull-ups", "pull up": "pull-ups", "pull ups": "pull-ups", "pullup": "pull-ups", "barfix": "pull-ups",
        "dumbbell fly": "dumbbell-chest-fly", "dumbbell chest fly": "dumbbell-chest-fly", "dambil acis": "dumbbell-chest-fly",
        "dambil fly": "dumbbell-chest-fly", "dumbell fly": "dumbbell-chest-fly",
    ]

    /// MoveKit Complete Pack: English library name → slug (Resources/mk-map.json)
    private static let mkMap: [String: String] = {
        guard let u = Bundle.main.url(forResource: "mk-map", withExtension: "json"), let d = try? Data(contentsOf: u),
              let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in m { out[TextNorm.norm(k)] = v }
        return out
    }()

    /// MoveKit files are licensed and not in the open-source build: without the file the slug is ignored
    /// and the visual falls back to the free-exercise-db photo or a silhouette. `-noMoveKit` forces this for screenshots.
    static func slug(for name: String) -> String? {
        if noMoveKit { return nil }
        let n = TextNorm.norm(name)
        let s = map[n] ?? mkMap[n] ?? aliases[n].flatMap({ mkMap[$0] })
            // names with a suffix, e.g. "Pull-up (wide grip)"
            ?? map.first { n.hasPrefix($0.key + " ") }?.value
            ?? mkMap.first { n.hasPrefix($0.key + " ") }?.value
        guard let s, Bundle.main.url(forResource: "mk-\(s)", withExtension: "jpg") != nil else { return nil }
        return s
    }
    static let noMoveKit = ProcessInfo.processInfo.arguments.contains("-noMoveKit")
    // MARK: free-exercise-db
    private struct Media: Decodable { let s: String; let tr: String }
    private static let media: [String: Media] = {
        guard let u = Bundle.main.url(forResource: "ex-media", withExtension: "json"), let d = try? Data(contentsOf: u) else { return [:] }
        return (try? JSONDecoder().decode([String: Media].self, from: d)) ?? [:]
    }()
    /// Turkish/other library names → English name (exercise-library.json `tr`)
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
        // Posters are 1280 px (for the HD video); lists decode at most 720 px to keep memory and scrolling smooth
        let w = raw.size.width * raw.scale
        let i = (w > 720 ? raw.preparingThumbnail(of: CGSize(width: 720, height: (720 * raw.size.height / raw.size.width).rounded())) : raw.preparingForDisplay()) ?? raw   // decode once
        cache.setObject(i, forKey: file as NSString); return i
    }
    // MARK: User visuals (ExerciseMedia) — photos you add come first
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

    /// Two photos (start / end position)
    static func frames(_ name: String) -> [UIImage] {
        let u = userFrames(name); if !u.isEmpty { return u }
        guard let m = mediaEntry(name) else { return [] }
        return [0, 1].compactMap { image("\(m.s)-\($0)") }
    }
    /// "How to" text
    static func howTo(_ name: String) -> String? { mediaEntry(name)?.tr }
    static func hasVisual(_ name: String) -> Bool { !userFrames(name).isEmpty || slug(for: name) != nil || mediaEntry(name) != nil }

    static func videoURL(_ name: String) -> URL? {
        if !userFrames(name).isEmpty { return nil }   // the user's photo wins when present
        return slug(for: name).flatMap { Bundle.main.url(forResource: "mk-\($0)", withExtension: "mp4") }
    }
    /// List thumbnail: decoded, downscaled and cached up front (no JPEG decoding per frame while scrolling)
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

/// Silent looping exercise video (poster on the first frame; poster only with Reduce Motion)
struct MotionPlayer: View {
    let name: String
    var height: CGFloat = 200
    /// Crop photos to fill the box (like a music player cover)
    var fill = false
    /// Pausing the workout pauses the movement too (stays on the last frame)
    var paused = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme
    @State private var ready = false

    var body: some View {
        let _ = UserMotion.shared.version
        if let url = Motion.videoURL(name) {
            // When filling, the video covers the box: no light bands above or below
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
            .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
            .accessibilityLabel("\(name) hareket animasyonu")
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            let f = Motion.frames(name)
            if !f.isEmpty {
                // Photos match the 3D visuals: grayscale on the same light ground; no glare in dark mode
                FramePlayer(frames: f, animate: !reduce && !paused, fill: fill)
                    .grayscale(1).contrast(1.05)
                    .frame(maxWidth: .infinity).frame(height: height)
                    .clipped()
                    .background(Color(white: 0.94))
                    .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
                    .accessibilityLabel("\(name) hareket görseli")
            }
        }
    }
}

/// Alternates the two frames with a soft crossfade (start and end of the movement)
private struct FramePlayer: View {
    let frames: [UIImage]
    var animate = true
    var fill = false
    @State private var i = 0
    var body: some View {
        // Color.clear takes the proposed size as is; the image never overflows (cropped when filling)
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

/// List thumbnail: poster if available, neutral box otherwise
struct MotionThumb: View {
    let name: String?
    var size: CGFloat = 56
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let _ = UserMotion.shared.version
        RoundedRectangle(cornerRadius: BRadius.small, style: .continuous).fill(Color.bMuted).frame(width: size, height: size)
            .overlay {
                if let name, let p = Motion.thumb(name, side: size) {
                    // Photo thumbnails are grayscale so they don't clash with the 3D visuals
                    let mk = Motion.videoURL(name) != nil
                    Image(uiImage: p).resizable().scaledToFill().frame(width: size, height: size)
                        .grayscale(mk ? 0 : 1)
                        .background(Color(white: 0.94))
                        .clipShape(RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
                } else {
                    // Exercise without a visual: neutral figure silhouette instead of an empty dumbbell
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
    var paused = false
    @Binding var ready: Bool

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        Motion.prepareAudio()
        let item = AVPlayerItem(url: url)
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


/// Loads and saves user visuals; views refresh when `version` changes
@MainActor @Observable
final class UserMotion {
    static let shared = UserMotion()
    var version = 0
    /// Unobserved copy used as the cache key
    nonisolated(unsafe) static var versionSnapshot = 0
    nonisolated static func bump() {
        versionSnapshot += 1
        Task { @MainActor in UserMotion.shared.version += 1 }
    }

    /// Only changed exercise visuals are loaded; views refresh once
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

    /// Downscales and saves photos (max 900 px, JPEG)
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
    /// Light-background exercise visuals must not glare like a white block in dark mode
    func darkDim(_ scheme: ColorScheme) -> some View { colorMultiply(scheme == .dark ? Color(white: 0.8) : .white) }

}


extension View {
    /// MoveKit visuals are inverted in dark mode: black ground, light gray mannequin, red muscle highlight kept
    @ViewBuilder func mkInvert(_ on: Bool) -> some View { if on { colorInvert().hueRotation(.degrees(180)) } else { self } }
}


// MARK: - Confetti


/// Realistic paper confetti. Cross fire from both bottom corners; speed-dependent (quadratic) air drag; paper drags a lot
/// face-on and little edge-on (floats / slides); sways as it slows down; 3D flip (front/back shading, glint)
/// and depth. ~3 s, computed with a fixed 240 Hz step (same path on 60/120 Hz screens). A CoreHaptics pattern plays with the burst.
/// With Reduce Motion nothing is drawn; only the haptic plays.
struct ConfettiBurst: View {
    var count = 150
    var haptics = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.self) private var env
    @State private var sim = ConfettiSim()
    @State private var done = false

    var body: some View {
        ZStack {
            if !reduceMotion && !done {
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        sim.advance(to: tl.date, size: size)
                        sim.draw(&ctx)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            sim.prepare(count: count, palette: ConfettiSim.palette.map { $0.resolve(in: env) })
            if haptics { ConfettiHaptics.shared.play() }
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(ConfettiSim.life + 0.3))
            done = true
        }
    }
}

final class ConfettiSim {
    static let life: Double = 3.2
    /// Brand: mostly lime; bFg is ink in light mode and off-white in dark mode
    static let palette: [Color] = [.bAction, .bAction, .bAction, .bFg, .fitKcal, Color(white: 0.62)]

    private struct P {
        var x: Double, y: Double, vx: Double, vy: Double
        var rot: Double, vrot: Double
        var flip: Double, vflip: Double      // flip around the horizontal axis (face ↔ edge)
        var roll: Double, vroll: Double      // slight spin around the vertical axis
        var swayPhase: Double, swayFreq: Double, swayAmp: Double
        var w: Double, h: Double
        var shape: Int                       // 0 strip, 1 square, 2 round
        var r: Double, g: Double, b: Double
        var depth: Double
        var delay: Double
        var dead = false
    }
    private var ps: [P] = []
    private var palette: [Color.Resolved] = []
    private var count = 0
    private var started = false
    private var last: Date?
    private var t: Double = 0

    func prepare(count: Int, palette: [Color.Resolved]) { self.count = count; self.palette = palette }

    private func spawn(_ size: CGSize) {
        let H = Double(size.height), W = Double(size.width)
        ps = (0..<count).map { i in
            let left = i % 2 == 0
            let th = Double.random(in: 48...74) * .pi / 180
            let v = H * Double.random(in: 1.5...2.45)
            let c = palette.randomElement() ?? Color.bAction.resolve(in: EnvironmentValues())
            let roll = Double.random(in: 0..<1)
            let shape = roll < 0.68 ? 0 : (roll < 0.88 ? 1 : 2)
            let w = shape == 0 ? Double.random(in: 5.5...8.5) : (shape == 1 ? Double.random(in: 6.5...8.5) : Double.random(in: 5...6.5))
            return P(x: left ? -6 : W + 6, y: H * Double.random(in: 0.9...0.96),
                     vx: (left ? 1 : -1) * v * cos(th), vy: -v * sin(th),
                     rot: Double.random(in: 0...(2 * .pi)), vrot: Double.random(in: -9...9),
                     flip: Double.random(in: 0...(2 * .pi)), vflip: Double.random(in: 7...17) * (Bool.random() ? 1 : -1),
                     roll: Double.random(in: 0...(2 * .pi)), vroll: Double.random(in: 2...6),
                     swayPhase: Double.random(in: 0...(2 * .pi)), swayFreq: Double.random(in: 2.2...4.2), swayAmp: Double.random(in: 260...560),
                     w: w, h: shape == 0 ? Double.random(in: 10...15) : w, shape: shape,
                     r: Double(c.red), g: Double(c.green), b: Double(c.blue),
                     depth: Double.random(in: 0.62...1.15), delay: Double.random(in: 0...0.1))
        }
        .sorted { $0.depth < $1.depth }   // far pieces are drawn first
    }

    func advance(to now: Date, size: CGSize) {
        guard count > 0, size.width > 0, size.height > 0 else { return }
        if !started { started = true; last = now; spawn(size); return }
        let dt = min(max(now.timeIntervalSince(last ?? now), 0), 1.0 / 30)
        last = now
        let steps = max(1, Int((dt * 240).rounded(.up)))
        let h = dt / Double(steps)
        let H = Double(size.height)
        let g = 1500 * H / 874            // gravity scaled to screen height
        let dragScale = 874 / H
        let bottom = H + 30
        for _ in 0..<steps {
            t += h
            for i in ps.indices where !ps[i].dead {
                var p = ps[i]
                let age = t - p.delay
                guard age > 0 else { continue }
                let ramp = min(1, age / 0.75)              // little drag while still bunched at launch, then it spreads
                let flat = abs(cos(p.flip))                // 1: face-on, 0: edge-on
                let c = (0.0004 + ramp * ramp * (0.008 + 0.042 * flat)) * dragScale
                let sp = (p.vx * p.vx + p.vy * p.vy).squareRoot()
                let k = 1 / (1 + c * sp * h)               // quadratic drag, stable (semi-implicit) step
                p.vx *= k; p.vy *= k
                p.vy += g * h
                let calm = 1 - min(1, sp / 900)            // sway grows as it slows down
                p.swayPhase += p.swayFreq * h
                p.vx += p.swayAmp * sin(p.swayPhase) * h * ramp * calm
                p.x += p.vx * h; p.y += p.vy * h
                let spin = 0.55 + 0.45 * min(1, sp / 700)  // flips slow down while floating
                p.flip += p.vflip * h * spin
                p.roll += p.vroll * h
                p.rot += p.vrot * h * spin
                if p.y > bottom || age > Self.life { p.dead = true }
                ps[i] = p
            }
        }
    }

    func draw(_ ctx: inout GraphicsContext) {
        for p in ps where !p.dead {
            let age = t - p.delay
            guard age > 0 else { continue }
            let fade = min(1, max(0, (Self.life - age) / 0.45))
            guard fade > 0 else { continue }
            let cf = cos(p.flip), face = abs(cf)
            // Light: bright when the face turns to the screen, dark edge-on; back face duller; far pieces slightly faded
            var light = (0.58 + 0.42 * face) * (cf < 0 ? 0.86 : 1) * (0.9 + 0.1 * min(1, p.depth))
            let spec = face > 0.93 ? (face - 0.93) / 0.07 * 0.3 : 0
            light = max(0, light)
            var c = ctx
            c.opacity = fade
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(p.rot))
            c.scaleBy(x: p.depth * (0.78 + 0.22 * abs(cos(p.roll))), y: p.depth * max(0.07, face))
            let rect = CGRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h)
            let path = p.shape == 2 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.2)
            c.fill(path, with: .color(Color(.sRGB, red: min(1, p.r * light + spec), green: min(1, p.g * light + spec),
                                             blue: min(1, p.b * light + spec), opacity: 1)))
        }
    }
}

/// Burst: a strong "pop" + short rumble; sparse light ticks while falling. Success haptic when CoreHaptics is unavailable.
final class ConfettiHaptics {
    static let shared = ConfettiHaptics()
    private var engine: CHHapticEngine?

    func play() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            UINotificationFeedbackGenerator().notificationOccurred(.success); return
        }
        do {
            if engine == nil { engine = try CHHapticEngine(); engine?.isAutoShutdownEnabled = true }
            try engine?.start()
            var ev: [CHHapticEvent] = []
            func tap(_ at: Double, _ i: Float, _ s: Float) {
                ev.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: s)], relativeTime: at))
            }
            tap(0, 1, 0.55)
            tap(0.045, 0.75, 0.8)
            ev.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)], relativeTime: 0.02, duration: 0.16))
            var at = 0.38
            while at < 1.9 { tap(at, Float.random(in: 0.12...0.26), Float.random(in: 0.7...0.95)); at += Double.random(in: 0.12...0.3) }
            let player = try engine?.makePlayer(with: CHHapticPattern(events: ev, parameters: []))
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
