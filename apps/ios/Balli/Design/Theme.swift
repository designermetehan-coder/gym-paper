import SwiftUI
import UIKit

// Ballı tasarım dili — PWA ile birebir (src/index.css + components/ui).
// Renkler oklch → sRGB; açık/koyu tema otomatik. Yazı tipi SF Pro (sistem); büyük sayılar SF Mono Heavy Italic. İkonlar Tabler (Assets › Tabler).

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    static func dyn(_ light: UIColor, _ dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
}

extension Color {
    private static func d(_ l: UInt32, _ dk: UInt32, la: CGFloat = 1, da: CGFloat = 1) -> Color {
        Color(uiColor: .dyn(UIColor(hex: l, alpha: la), UIColor(hex: dk, alpha: da)))
    }
    static let bBg = d(0xF2F2F5, 0x0A0A0A)   // açık temada gri zemin, beyaz kartlar
    static let bFg = d(0x0A0A0A, 0xE5E5E7)
    static let bCard = d(0xFFFFFF, 0x171717)
    /// Ana renk: doğal, siyaha yakın (koyu temada saf beyaz değil, kırık beyaz #E5E5E7); turuncu yalnız oruç gibi anlam taşıyan vurgularda
    static let bPrimary = d(0x1C1C1E, 0xE5E5E7)
    static let bPrimaryFg = d(0xFAFAFA, 0x1C1C1E)
    /// Birincil eylem butonu: neon lime (volt) zemin, koyu lacivert yazı (iki temada aynı; koyu ekranda yüksek kontrast)
    static let bAction = d(0xC6FF3D, 0xC6FF3D)
    static let bActionFg = d(0x121826, 0x121826)
    /// Metin butonları (zeminsiz): açık temada okunur koyu zeytin yeşili, koyu temada neon lime
    static let bLink = d(0x4A6B00, 0xC6FF3D)
    /// Tab bar seçili sekme: koyu temada marka lime; açık temada lime cam üstünde okunmadığı ve zeytin yeşili soluk durduğu için ana renk (GP-06)
    static let bTab = d(0x1C1C1E, 0xC6FF3D)
    /// Seçili gün: ana renk (siyaha yakın; koyu temada kırık beyaz)
    static let bSel = d(0x1C1C1E, 0xE5E5E7)
    static let bSelFg = d(0xFAFAFA, 0x1C1C1E)
    static let bSecondary = d(0xE5E5EA, 0x262626)   // açık temada #F2F2F5 zeminden ayrışsın (TE-04)
    static let bMuted = d(0xF5F5F5, 0x262626)
    static let bMutedFg = d(0x666666, 0xA1A1A1)   // AA kontrast (CR-36)
    static let bBorder = d(0xE5E5E5, 0xFFFFFF, da: 0.10)
    static let bInput = d(0xE5E5E5, 0xFFFFFF, da: 0.15)
    static let bAccent = d(0xF5F5F5, 0x262626)
    static let bDestructive = d(0xE7000B, 0xFF6467)
    static let bSuccess = d(0x15803D, 0x26C55F)   // beyazda 5:1 (CR-36)
    static let bChart2 = d(0x737373, 0xA1A1A1)
    static let bChart4 = d(0x525252, 0x525252)
    /// Tonal ikincil buton yazısı (TE-05)
    static let bTonalText = d(0x1C1C1E, 0xE5E5E7)
    static let bSky = Color(red: 0.055, green: 0.647, blue: 0.914)
    // Makro halkaları — Apple Watch Etkinlik renkleri (Hareket, Egzersiz, Ayakta)
    static let bProtein = d(0xFA114F, 0xFA114F)
    static let bCarb = d(0x6BD60A, 0x92E82A)
    static let bFat = d(0x00B8E6, 0x1EEAEF)
    // Antrenman ölçümleri — Apple Fitness renk dili (süre sarı, kalori kırmızı); açık temada okunur tonlar
    static let fitTime = d(0x8A6700, 0xFFD60A)   // açıkta 2,97:1 → ~4,9:1 (TE-04)
    static let fitKcal = d(0xE0144C, 0xFF375F)
    static let fitPurple = d(0x7A3FF2, 0xA97CFF)
    static let fitBlue = d(0x0A7AE0, 0x40C8FF)
    static let fitGreen = d(0x1E9E3E, 0x5FE07A)
    static func ringGradient(_ c: Color) -> [Color] {
        // halka boyunca hafif koyudan açığa (Watch gibi)
        [c.opacity(0.85), c]
    }
}

// MARK: - Yazı tipi (iOS sistem fontu: SF Pro; büyük sayılar SF Mono Heavy Italic)

extension Font {
    /// Metin: SF Pro; Dinamik Yazı ile ölçeklenir (ad geçmişten kalma, Geist yerine sistem fontu)
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .system(size: scaled(size, style), weight: weight)
    }
    /// Vurgulu metin (buton, ekran başlığı): SF Pro Bold Italic
    static func bDisplay(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .system(size: scaled(size, style), weight: .bold).italic()
    }
    /// Büyük sayılar (süre, kcal, kg, geri sayım): SF Pro Heavy Italic, rakamlar sabit genişlik.
    /// SF Mono'da ayraçlar da tam hücre genişliğindeydi ("88 , 4", "1 . 098") (TE-03)
    static func bNum(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .system(size: scaled(size, style), weight: .heavy).italic().monospacedDigit()
    }
    private static func scaled(_ size: CGFloat, _ style: Font.TextStyle) -> CGFloat {
        let ui: UIFont.TextStyle
        switch style {
        case .largeTitle: ui = .largeTitle
        case .title: ui = .title1
        case .title2: ui = .title2
        case .title3: ui = .title3
        case .headline: ui = .headline
        case .subheadline: ui = .subheadline
        case .callout: ui = .callout
        case .footnote: ui = .footnote
        case .caption: ui = .caption1
        case .caption2: ui = .caption2
        default: ui = .body
        }
        // Erişilebilirlik boyutlarında sınır: büyük sayılar xxxL'de, metin AX3'te durur; aksi halde başlık ve sayılar
        // harf ortasından bölünüyordu ("Antrenm/an", "88 , kg 4") (QA-01)
        let cur = UITraitCollection.current.preferredContentSizeCategory
        let cap: UIContentSizeCategory = size >= 24 ? .extraExtraExtraLarge : .accessibilityLarge
        let traits = UITraitCollection(preferredContentSizeCategory: min(cur, cap))
        return UIFontMetrics(forTextStyle: ui).scaledValue(for: size, compatibleWith: traits)
    }
    // Tailwind ölçüleri (hesaplanan: Dinamik Yazı değişince yeniden ölçeklenir)
    static var bXs: Font { geist(12, relativeTo: .caption) }            // text-xs
    static var bSm: Font { geist(14, relativeTo: .subheadline) }        // text-sm
    static var bBase: Font { geist(16) }                                 // text-base
    static var bLg: Font { geist(18, .semibold, relativeTo: .title3) }  // text-lg
    static var bXl: Font { geist(20, .semibold, relativeTo: .title3) }  // text-xl
    static var b2xl: Font { geist(24, .semibold, relativeTo: .title2) } // text-2xl
}

// MARK: - Tabler ikonları

struct Ti: View {
    let name: String
    var size: CGFloat = 16
    init(_ name: String, size: CGFloat = 16) { self.name = name; self.size = size }
    var body: some View {
        Image("ti-" + name).resizable().renderingMode(.template).scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

// MARK: - Kart

struct BCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 16
    var highlight: Color? = nil
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                // gölge ve kenarlık yok; yalnız vurgulu kartta renkli çerçeve
                if let highlight { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(highlight, lineWidth: 1) }
            }
    }
}

extension View {
    func bCard(padding: CGFloat = 16, highlight: Color? = nil) -> some View { modifier(BCardModifier(padding: padding, highlight: highlight)) }
    /// Cam yüzey (.glass)
    func bGlass<S: Shape>(_ shape: S) -> some View {
        background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.bFg.opacity(0.09), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 15, y: 8)
    }
}

// MARK: - Butonlar (pill)

enum BVariant { case primary, outline, secondary, ghost, tonal, destructive }
enum BSize { case regular, small, large, icon, iconLarge }

struct BButtonStyle: ButtonStyle {
    var variant: BVariant = .primary
    var size: BSize = .regular
    var fullWidth = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.bButtonFg) private var customFg

    func makeBody(configuration c: Configuration) -> some View {
        let h: CGFloat = switch size { case .small: 32; case .large: 48; case .icon: 40; case .iconLarge: 44; case .regular: 44 }
        let isIcon = size == .icon || size == .iconLarge
        c.label
            .font(size == .large ? .bDisplay(16, relativeTo: .body) : .bDisplay(14, relativeTo: .subheadline))
            .lineLimit(1).minimumScaleFactor(0.7)   // büyük yazıda "Deva…" yerine küçülür (QA-02)
            .padding(.horizontal, isIcon ? 0 : (size == .large ? 24 : size == .small ? 12 : 16))
            .frame(minWidth: isIcon ? h : nil, maxWidth: fullWidth ? .infinity : nil, minHeight: h)
            .foregroundStyle(fg)
            .background(bg(c.isPressed), in: Capsule())
            .overlay {
                if variant == .outline { Capsule().strokeBorder(scheme == .dark ? Color.bInput : Color.bBorder, lineWidth: 1) }
            }
            .shadow(color: variant == .primary ? Color.bAction.opacity(scheme == .dark ? 0.15 : 0.35) : .clear, radius: 6, y: 3)
            // Küçük düğmeler (32/40 pt) görünüşü bozmadan 44 pt dokunma alanı alır (QA-12)
            .padding(max(0, (44 - h) / 2)).contentShape(Rectangle()).padding(-max(0, (44 - h) / 2))
            .scaleEffect(c.isPressed ? 0.96 : 1)
            .opacity(enabled ? 1 : 0.5)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: c.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: c.isPressed) { _, new in new }
    }
    private var fg: Color {
        switch variant {
        case .primary: .bActionFg
        case .destructive: .white
        case .tonal: .bTonalText
        case .ghost: customFg ?? ((size == .icon || size == .iconLarge) ? .bFg : .bLink)
        default: customFg ?? .bFg
        }
    }
    private func bg(_ pressed: Bool) -> AnyShapeStyle {
        switch variant {
        case .primary: AnyShapeStyle(Color.bAction.opacity(pressed ? 0.85 : 1))
        case .destructive: AnyShapeStyle(Color.bDestructive)
        case .secondary: AnyShapeStyle(Color.bSecondary)
        case .tonal: AnyShapeStyle(Color.bPrimary.opacity(pressed ? 0.20 : 0.12))
        case .ghost: AnyShapeStyle(pressed ? Color.bAccent : Color.clear)
        case .outline: AnyShapeStyle(pressed ? Color.bAccent : (scheme == .dark ? Color.white.opacity(0.045) : Color.bCard))
        }
    }
}

extension ButtonStyle where Self == BButtonStyle {
    static func b(_ v: BVariant = .primary, _ s: BSize = .regular, full: Bool = false) -> BButtonStyle { BButtonStyle(variant: v, size: s, fullWidth: full) }
}

/// Basınca hafif küçülen sade buton (.press)
struct PressStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.contentShape(Rectangle()).scaleEffect(c.isPressed ? 0.97 : 1).opacity(c.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: c.isPressed)
    }
}
extension ButtonStyle where Self == PressStyle { static var press: PressStyle { PressStyle() } }

/// İkon + metin (gap-2)
@MainActor
struct BLabel: View {
    let text: String; let icon: String?
    var trailing = false
    init(_ text: String, icon: String? = nil, trailing: Bool = false) { self.text = text; self.icon = icon; self.trailing = trailing }
    var body: some View {
        // Metinli butonlarda ikon kullanılmaz (sade); yalnız ikonlu butonlar Ti ile yazılır
        Text(tl(text))
    }
}

// MARK: - İlerleme, rozet, halka

struct BProgress: View {
    @State private var appeared = false
    var value: Double          // 0…1
    var tint: Color = .bPrimary
    var height: CGFloat = 6
    var track: Color? = nil
    /// VoiceOver'da neyin ilerlemesi olduğu (QA-11)
    var label: String = "İlerleme"
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track ?? tint.opacity(0.15))
                Capsule().fill(tint).frame(width: appeared ? g.size.width * min(1, max(0, value.isFinite ? value : 0)) : 0)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: value)
        .onAppear { withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.7).delay(0.08)) { appeared = true } }
        .accessibilityElement().accessibilityLabel(tl(label)).accessibilityValue("%\(Int((value.isFinite ? value : 0) * 100))")
    }
}

enum BBadgeVariant { case primary, secondary, outline, soft, success }
struct BBadge<C: View>: View {
    var variant: BBadgeVariant = .outline
    @ViewBuilder var content: C
    var body: some View {
        HStack(spacing: 4) { content }
            .font(.geist(12, .medium, relativeTo: .caption))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
            .overlay { if variant == .outline { Capsule().strokeBorder(Color.bBorder, lineWidth: 1) } }
            .fixedSize()
    }
    private var fg: Color { switch variant { case .primary: .bPrimaryFg; case .soft: .bPrimary; case .success: .bSuccess; default: .bFg } }
    private var bg: Color { switch variant { case .primary: .bPrimary; case .secondary: .bSecondary; case .soft: .bPrimary.opacity(0.12); case .success: .bSuccess.opacity(0.15); case .outline: .clear } }
}

struct BRing<C: View>: View {
    @State private var appeared = false
    var value: Double
    var size: CGFloat = 56
    var stroke: CGFloat = 5
    var tint: Color = .bPrimary
    @ViewBuilder var content: C
    var body: some View {
        ZStack {
            Circle().stroke(Color.bMuted, lineWidth: stroke)
            Circle().trim(from: 0, to: appeared ? min(1, max(0, value.isFinite ? value : 0)) : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.6), value: value)
            content
        }
        .padding(stroke / 2)
        .frame(width: size, height: size)
        .onAppear { withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.8).delay(0.1)) { appeared = true } }
    }
}

/// Apple Watch tarzı iç içe halkalar (dıştan içe)
struct BRings<C: View>: View {
    var rings: [(value: Double, tint: Color)]
    var size: CGFloat = 104
    var stroke: CGFloat = 10
    var gap: CGFloat = 2.5
    @ViewBuilder var content: C
    @State private var appeared = false
    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { i, r in
                let inset = CGFloat(i) * (stroke + gap) + stroke / 2
                let v = r.value.isFinite ? max(0, r.value) : 0
                ZStack {
                    Circle().stroke(r.tint.opacity(0.22), lineWidth: stroke)
                    Circle().trim(from: 0, to: appeared ? min(1, v) : 0)
                        .stroke(AngularGradient(colors: Color.ringGradient(r.tint), center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(0.01, min(1, v)))),
                                style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    // hedef aşılınca ikinci tur (Watch gibi)
                    if v > 1 {
                        Circle().trim(from: 0, to: appeared ? min(1, v - 1) : 0)
                            .stroke(r.tint, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: .black.opacity(0.35), radius: 1.5)
                    }
                }
                .padding(inset)
                .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.9).delay(0.1 + Double(i) * 0.08), value: appeared)
                // Değer değişince halkalar dıştan içe 80 ms arayla dolar (MO-I4)
                .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.6).delay(Double(i) * 0.08), value: v)
            }
            content
        }
        .frame(width: size, height: size)
        .onAppear { appeared = true }
    }
}

// MARK: - Ekran başlığı (Header)

struct BHeader<Actions: View>: View {
    var eyebrow: String? = nil
    var title: String
    var sub: String? = nil
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow {
                    Text(tl(eyebrow).uppercased(with: .current))
                        .font(.geist(12, .medium, relativeTo: .caption)).tracking(0.6).foregroundStyle(Color.bMutedFg)
                }
                Text(tl(title)).font(.bDisplay(30, relativeTo: .largeTitle)).tracking(-0.6).foregroundStyle(Color.bFg)
                    .lineLimit(1).minimumScaleFactor(0.6)   // tek kelimelik başlık bölünmesin (QA-01)
                if let sub { Text(tl(sub)).font(.bSm).foregroundStyle(Color.bMutedFg).monospacedDigit() }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) { actions }
        }
        .padding(.top, 12).padding(.bottom, 12)
    }
}
extension BHeader where Actions == EmptyView {
    init(eyebrow: String? = nil, title: String, sub: String? = nil) { self.init(eyebrow: eyebrow, title: title, sub: sub) { EmptyView() } }
}

/// Başlıktaki yuvarlak cam buton (h-11)
struct BRoundIcon: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) { Ti(icon, size: 20) }
            .buttonStyle(.b(.outline, .iconLarge)).accessibilityLabel(tl(label))
    }
}

// MARK: - Ekran iskeleti

private struct MiniInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    /// Mini oynatıcı görünürken ekranların altına eklenecek boşluk
    var miniPlayerInset: CGFloat { get { self[MiniInsetKey.self] } set { self[MiniInsetKey.self] = newValue } }
}

struct BScreen<C: View>: View {
    @Environment(\.miniPlayerInset) private var miniInset
    /// Üst güvenli alan: iPhone Duo'da durum çubuğu yanda olduğundan 0'a yakın
    @State private var topInset: CGFloat = 60
    @State private var bottomInset: CGFloat = 0
    var spacing: CGFloat = 16
    @ViewBuilder var content: C
    var body: some View {
        // İlk öğe (başlık) üstte sabit kalır; gerisi altında kayar
        Group(subviews: content) { subs in
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    // Ekran açılışında kartlar sırayla yükselir (PWA .stagger)
                    ForEach(Array(subs.dropFirst().enumerated()), id: \.element.id) { i, sub in
                        sub.modifier(BRise(index: i + 1))   // kaydırırken kenarda küçülme (BFloat) kaldırıldı (2 Kas)
                    }
                }
                // iPhone Duo iç ekranı / Split View: çok geniş alanda satırlar uzamasın
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)   // iOS 26 sistem kenar boşluğu (tab bar ile hizalı)
                .padding(.top, 4)
                .padding(.bottom, 24 + miniInset)   // mini oynatıcı varken son öğe altında kalmasın
            }
            .scrollDismissesKeyboard(.interactively)
            // Üst başlık: altından kayan içerikle arasında kademeli bulanıklık (iOS 26'da sistemin kenar efekti)
            .modifier(BTopBar(plain: topInset < 24) {
                if let head = subs.first {
                    head
                        // Durum çubuğu üstte değilse (iPhone Duo) başlık ekran kenarına yapışmasın
                        .padding(.top, topInset < 24 ? 16 : 0)
                        .frame(maxWidth: 820, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                }
            })
        }
        // Tab bar arkası: içerikten ayıran kademeli bulanıklık
        // iPhone Duo'da (durum çubuğu yanda, topInset küçük) kademeli bulanıklık yok (2 Kas)
        // Mini oynatıcı varken tek parça bulanıklık onun üstüne kadar uzar (4 Kas)
        .overlay(alignment: .bottom) {
            if topInset >= 24 {
                BBottomFade(height: bottomInset + 28 + (miniInset > 0 ? miniInset + 12 : 0))
                    .ignoresSafeArea(edges: .bottom).allowsHitTesting(false)
                    .animation(.smooth(duration: 0.3), value: miniInset)
            }
        }
        .background(Color.bBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
    }
}

/// Alt kenar (tab bar arkası) için kademeli bulanıklık: malzeme + yukarı doğru solan maske
struct BBottomFade: View {
    var height: CGFloat
    var body: some View {
        ZStack {
            // Malzeme koyu temada griye çalar; zemin rengiyle örtülerek arka planla aynı tonda kalır
            Rectangle().fill(.ultraThinMaterial)
            Color.bBg.opacity(0.78)
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.8), location: 0.45), .init(color: .black, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .frame(height: max(0, height))
    }
}

/// Sabit üst başlık çubuğu: iOS 26'da `safeAreaBar` + yumuşak kaydırma kenarı efekti (sistemin kademeli bulanıklığı);
/// iOS 18'de malzeme + aşağı doğru solan maske ile aynı his
struct BTopBar<H: View>: ViewModifier {
    /// iPhone Duo: bulanıklık yok, başlık düz zeminde (2 Kas)
    var plain = false
    @ViewBuilder var head: H
    func body(content: Content) -> some View {
        if plain {
            content.safeAreaInset(edge: .top, spacing: 0) { head.background(Color.bBg.ignoresSafeArea(edges: .top)) }
        } else if #available(iOS 26, *) {
            content
                .safeAreaBar(edge: .top, spacing: 0) { head }
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                head.background {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Color.bBg.opacity(0.55)
                    }
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.65), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(.bottom, -20)
                    .ignoresSafeArea(edges: .top)
                }
            }
        }
    }
}

/// Kaydırırken kartlar çok hafif "yüzer": ekranın kenarlarına yaklaşınca biraz küçülür ve gecikmeli kayar
struct BFloat: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        if reduce { content } else {
            content.visualEffect { c, proxy in
                let f = proxy.frame(in: .scrollView(axis: .vertical))
                let h = proxy.bounds(of: .scrollView(axis: .vertical))?.height ?? 800
                // 0 = görünür alanın ortası, ±1 = kenarlar
                let mid = (f.midY - h / 2) / max(1, h / 2)
                let edge = max(0, abs(mid) - 0.55)
                return c
                    .scaleEffect(1 - min(0.035, edge * 0.06), anchor: mid > 0 ? .top : .bottom)
                    .offset(y: mid * 4)
            }
        }
    }
}

/// Kartın ilk görünüşte 10 pt aşağıdan solarak yükselmesi (sıra gecikmeli)
struct BRise: ViewModifier {
    var index: Int
    /// Sıra başına gecikme ve ilk gecikme (bitiş özeti gibi yerlerde daha belirgin sıra için)
    var step: Double = 0.03
    var base: Double = 0
    var maxIndex = 6
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.42).delay(base + Double(min(index, maxIndex)) * step)) { shown = true }
            }
    }
}

/// İlk görünüşte küçükten ~%15 aşarak yerine oturan "pop" (kupa, rekor rozeti — MO-I5)
struct BPopIn: ViewModifier {
    var delay: Double = 0
    var from: CGFloat = 0.5
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduce ? 1 : from)
            .opacity(shown || reduce ? 1 : 0)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.55).delay(delay)) { shown = true }
            }
    }
}

/// Basınca hafif küçülme + dokunsal geri bildirim (kartlar için)
extension View {
    func bPop<V: Equatable>(_ value: V) -> some View {
        self.phaseAnimator([false, true], trigger: value) { v, up in v.scaleEffect(up ? 1.03 : 1) } animation: { up in up ? .spring(response: 0.18, dampingFraction: 0.6) : .spring(response: 0.35, dampingFraction: 0.55) }
    }
}

// MARK: - Onay sheet'i (sistem uyarısı yerine arayüzle uyumlu)

struct BConfirmSheet: View {
    var title: String
    var message: String
    var action: String
    var icon = "trash.fill"
    var confirm: () -> Void
    var cancel: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(Color.bDestructive)
                .frame(width: 52, height: 52).background(Color.bDestructive.opacity(0.12), in: Circle())
                .padding(.top, 22)
            VStack(spacing: 4) {
                Text(tl(title)).font(.geist(18, .semibold))
                Text(tl(message)).font(.bSm).foregroundStyle(Color.bMutedFg).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            VStack(spacing: 8) {
                Button(action: { UINotificationFeedbackGenerator().notificationOccurred(.warning); confirm() }) { Text(tl(action)).frame(maxWidth: .infinity) }
                    .buttonStyle(.b(.destructive, .large, full: true))
                Button(action: cancel) { Text("Vazgeç").frame(maxWidth: .infinity) }
                    .buttonStyle(.b(.secondary, .large, full: true))
            }
            .padding(.horizontal, 20).padding(.top, 6)
            Spacer(minLength: 0)
        }
        .presentationDetents([.height(300), .large])
        .presentationCornerRadius(32)
        .presentationBackground(Color.bBg)
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Kaydırarak silme

/// Satırı sola kaydır: kırmızı "Sil" görünür; sonuna kadar kaydırınca ya da Sil'e dokununca siler.
/// Dikey kaydırmayı engellemez (yalnız yatay hareket yakalanır).
struct BSwipeDelete: ViewModifier {
    var enabled = true
    var onDelete: () -> Void
    @State private var x: CGFloat = 0
    @State private var open = false
    @State private var width: CGFloat = 320
    @State private var horizontal: Bool?
    @GestureState private var liveDrag = false
    @State private var asking = false
    @State private var dragging = false
    private let reveal: CGFloat = 84

    func body(content: Content) -> some View {
        if !enabled { content } else {
            ZStack(alignment: .trailing) {
                // arka plan
                HStack {
                    Spacer()
                    Button { commit() } label: {
                        VStack(spacing: 2) { Ti("trash", size: 20); Text("Sil").font(.geist(12, .semibold)) }
                            .foregroundStyle(.white)
                            .frame(width: max(reveal, -x), alignment: .center)
                            .frame(maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                }
                .background(Color.bDestructive)
                .opacity(x < 0 ? 1 : 0)
                content
                    .background(Color.bCard)
                    // kaydırırken ya da "Sil" açıkken satırın kendi dokunuşu (detay açma) çalışmasın
                    .disabled(dragging || open)
                    .overlay {
                        if open && !dragging {
                            Color.clear.contentShape(Rectangle()).onTapGesture { snap(open: false) }
                        }
                    }
                    .offset(x: x)
            }
            // Genişlik değişince de güncellenir (döndürme, Duo katlama); satır başına GeometryReader yok (CR-02)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .clipped()
            // Kaydırma ScrollView'a geçip iptal olursa onEnded gelmez: GestureState sıfırlanınca toparla (CR-05)
            .onChange(of: liveDrag) { _, on in
                guard !on else { return }
                horizontal = nil
                if dragging {
                    snap(open: x < -reveal * 0.6)
                    Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); dragging = false }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 14)
                    .updating($liveDrag) { _, s, _ in s = true }
                    .onChanged { v in
                        if horizontal == nil {
                            horizontal = abs(v.translation.width) > abs(v.translation.height) * 1.3
                            if horizontal == true { dragging = true }
                        }
                        guard horizontal == true else { return }
                        let base: CGFloat = open ? -reveal : 0
                        let t = base + v.translation.width
                        x = t > 0 ? t * 0.2 : t
                    }
                    .onEnded { v in
                        defer {
                            horizontal = nil
                            // bırakma anındaki dokunuş satırı açmasın
                            Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); dragging = false }
                        }
                        guard horizontal == true else { return }
                        let base: CGFloat = open ? -reveal : 0
                        let t = base + v.predictedEndTranslation.width
                        // Kaydırma yalnız "Sil"i gösterir; silme, Sil'e dokunup onaylayınca olur
                        if t < -reveal * 0.6 { snap(open: true) } else { snap(open: false) }
                    }
            )
            .accessibilityAction(named: "Sil") { asking = true }
            .sheet(isPresented: $asking, onDismiss: { if open { snap(open: false) } }) {
                BConfirmSheet(title: "Silinsin mi?", message: "Bu kayıt silinecek. Hemen ardından geri alabilirsin.", action: "Sil") {
                    asking = false; remove()
                } cancel: { asking = false; snap(open: false) }
            }
        }
    }
    private func snap(open o: Bool) {
        if o != open { haptic() }
        open = o
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { x = o ? -reveal : 0 }
    }
    /// Önce onay iste
    private func commit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { x = -reveal }
        open = true
        asking = true
    }
    private func remove() {
        withAnimation(.easeIn(duration: 0.18)) { x = -width }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            onDelete()
            open = false; x = 0
        }
    }
}
extension View {
    func bSwipeDelete(_ enabled: Bool = true, _ onDelete: @escaping () -> Void) -> some View { modifier(BSwipeDelete(enabled: enabled, onDelete: onDelete)) }
}

// MARK: - Segmented (pill)

struct BSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    /// Nötr görünüm: seçili öğe marka yeşili yerine beyaz (iOS segmented gibi)
    var neutral = false
    @Environment(\.colorScheme) private var scheme
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { v, l in
                let on = v == selection
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = v } } label: {
                    // Büyük yazıda kesilmesin: küçülür, satır yüksekliği metinle büyür (QA-10)
                    Text(tl(l)).font(.geist(14, .medium, relativeTo: .subheadline)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(on ? (neutral ? Color.bFg : Color.bActionFg) : Color.bFg.opacity(scheme == .dark ? 0.6 : 0.7))
                        .fontWeight(on ? .semibold : .medium)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if on {
                                // Seçili öğe marka rengi (neon lime)
                                Capsule().fill(neutral ? (scheme == .dark ? Color(white: 0.32) : Color.white) : Color.bAction)
                                    .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(3)
        .frame(minHeight: 44)
        .background(scheme == .dark ? Color.white.opacity(0.045) : Color.bFg.opacity(0.07), in: Capsule())
    }
}

// MARK: - Stepper (− değer +)

struct BStepper: View {
    @Binding var value: Double
    var step: Double = 1
    var min: Double = 0
    var max: Double = 100_000
    var suffix: String? = nil
    var format: (Double) -> String = { fmt1($0) }
    var full = false
    var height: CGFloat = 44
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 0) {
            Button { value = Swift.max(min, (value - step).rounded(toPlaces: 2)); haptic() } label: { Text("−").font(.geist(full ? 22 : 18)).frame(width: full ? 48 : 44, height: height) }
                .accessibilityLabel("Azalt")
            Text(format(value) + (suffix.map { " \($0)" } ?? "")).font(.bNum(full ? 22 : 16))
                .contentTransition(.numericText(value: value)).animation(.snappy(duration: 0.25), value: value)
                .frame(minWidth: full ? 0 : 56, maxWidth: full ? .infinity : nil).lineLimit(1).minimumScaleFactor(0.7)
            Button { value = Swift.min(max, (value + step).rounded(toPlaces: 2)); haptic() } label: { Text("+").font(.geist(full ? 22 : 18)).frame(width: full ? 48 : 44, height: height) }
                .accessibilityLabel("Artır")
        }
        .buttonStyle(.press)
        .foregroundStyle(Color.bFg)
        .background(scheme == .dark ? Color.white.opacity(0.045) : Color.bCard, in: Capsule())
        .overlay { if scheme == .light { Capsule().strokeBorder(Color.bBorder) } }
    }
}

/// Değer kutusu: marka renginde büyük değer; dokununca tekerlekli seçici açılır (−/+ yok)
struct BPickField: View {
    let label: String
    @Binding var value: Double
    var values: [Double]
    var suffix: String? = nil
    var format: (Double) -> String = { fmt1($0) }
    var height: CGFloat = 64
    /// Değer 0 iken gösterilecek metin (ör. vücut ağırlığıyla yapılan harekette "0 kg" yerine "–") (QA-04)
    var zeroText: String? = nil
    /// Değer 0 iken seçicinin açılacağı değer (ör. hareket detayında önceki/planlanan kilo)
    var startValue: Double? = nil
    /// Etiket gizliyse seçici başlığı
    var sheetTitle: String? = nil
    @State private var show = false
    @State private var temp: Double = 0
    private var shown: String { value == 0 && zeroText != nil ? zeroText! : format(value) + (suffix.map { " \($0)" } ?? "") }
    private var empty: Bool { value == 0 && zeroText != nil }
    var body: some View {
        let compact = height < 56
        Button { temp = nearest(value == 0 ? (startValue ?? 0) : value); show = true; haptic() } label: {
            VStack(spacing: 2) {
                if !label.isEmpty { Text(tl(label)).font(.geist(12, .medium, relativeTo: .caption)).foregroundStyle(Color.bMutedFg) }
                (Text(empty ? zeroText! : format(value)).font(.bNum(compact ? 18 : 26))
                 + Text(empty ? "" : suffix.map { " \($0)" } ?? "").font(.geist(compact ? 13 : 15, .semibold, relativeTo: .subheadline)))
                    .foregroundStyle(empty && compact ? Color.bMutedFg : Color.bPrimary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: value)).animation(.snappy(duration: 0.25), value: value)
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Color.bFg.opacity(0.07), in: RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous))
        }
        .buttonStyle(.press)
        .accessibilityLabel(label.isEmpty ? (sheetTitle ?? "") : tl(label)).accessibilityValue(value == 0 && zeroText != nil ? String(localized: "Vücut ağırlığı") : shown)
        .accessibilityHint("Seçmek için dokun")
        .sheet(isPresented: $show) {
            VStack(spacing: 8) {
                HStack {
                    Text(label.isEmpty ? (sheetTitle ?? "") : tl(label)).font(.geist(17, .semibold))
                    Spacer()
                    Button("Tamam") { value = temp; haptic(); show = false }
                        .font(.geist(17, .semibold)).foregroundStyle(Color.bPrimary)
                }
                .padding(.horizontal, 20).padding(.top, 18)
                Picker(label.isEmpty ? (sheetTitle ?? "") : tl(label), selection: $temp) {
                    ForEach(values, id: \.self) { v in
                        Text(format(v) + (suffix.map { " \($0)" } ?? "")).monospacedDigit().tag(v)
                    }
                }
                .pickerStyle(.wheel)
                .sensoryFeedback(.selection, trigger: temp)
            }
            .presentationDetents([.height(300), .large])
            .presentationCornerRadius(28)
            .presentationBackground(Color.bBg)
        }
    }
    private func nearest(_ v: Double) -> Double { values.min { abs($0 - v) < abs($1 - v) } ?? v }
}

// MARK: - Giriş alanı

struct BFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var scheme
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.geist(16)).monospacedDigit()
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(scheme == .dark ? Color.white.opacity(0.045) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { if scheme == .light { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.bInput) } }
    }
}
extension TextFieldStyle where Self == BFieldStyle { static var b: BFieldStyle { BFieldStyle() } }

struct BField<C: View>: View {
    var label: String?
    var hint: String? = nil
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label { Text(tl(label)).font(.geist(14, .medium, relativeTo: .subheadline)).foregroundStyle(Color.bFg) }
            content
            if let hint { Text(tl(hint)).font(.bXs).foregroundStyle(Color.bMutedFg) }
        }
    }
}

// MARK: - Sheet

struct BSheet<C: View, F: View>: View {
    var title: String
    var description: String? = nil
    @ViewBuilder var content: C
    @ViewBuilder var footer: F
    @Environment(\.dismiss) private var dismiss
    /// Sheet yerine detay ekranı olarak itildiyse: geri düğmesi + büyük başlık
    @Environment(\.bSheetPushed) private var pushed
    var body: some View {
        VStack(spacing: 0) {
            if pushed {
                VStack(alignment: .leading, spacing: 0) {
                    BRoundIcon(icon: "chevron-left", label: "Geri") { dismiss() }.padding(.top, 4)
                    BHeader(title: title, sub: description)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.bottom, 8)
            } else {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tl(title)).font(.geist(18, .semibold, relativeTo: .title3)).foregroundStyle(Color.bFg)
                    if let description { Text(tl(description)).font(.bSm).foregroundStyle(Color.bMutedFg) }
                }
                Spacer()
                Button { dismiss() } label: { Ti("x", size: 20) }.buttonStyle(.b(.outline, .iconLarge)).accessibilityLabel("Kapat")
                    .padding(.top, -6)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }.padding(.horizontal, 20).padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            footerView
        }
        .background(Color.bBg.ignoresSafeArea())
        .toolbar(pushed ? .hidden : .automatic, for: .navigationBar)
        .onAppear { if !pushed { SheetDim.shared.count += 1 } }
        .onDisappear { if !pushed { SheetDim.shared.count = max(0, SheetDim.shared.count - 1) } }
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }
    @ViewBuilder private var footerView: some View {
        if F.self != EmptyView.self {
            VStack(spacing: 8) { footer }.padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
}
extension BSheet where F == EmptyView {
    init(title: String, description: String? = nil, @ViewBuilder content: () -> C) {
        self.init(title: title, description: description, content: content, footer: { EmptyView() })
    }
}

private struct BSheetPushedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var bSheetPushed: Bool { get { self[BSheetPushedKey.self] } set { self[BSheetPushedKey.self] = newValue } }
}

/// Açık sheet sayısı: ana ekranın arkası ekstra karartılır
@MainActor @Observable final class SheetDim { static let shared = SheetDim(); var count = 0 }

// MARK: - Seçim kutusu (Checkbox)

struct BCheck: View {
    var checked: Bool
    var size: CGFloat = 20
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(checked ? Color.bPrimary : Color.clear)
                .overlay { if !checked { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.bInput, lineWidth: 1) } }
            if checked { Ti("check", size: size * 0.7).foregroundStyle(Color.bPrimaryFg).transition(.scale.combined(with: .opacity)) }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: checked)
    }
}

// MARK: - Yardımcılar

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) { UIImpactFeedbackGenerator(style: style).impactOccurred() }

extension Double {
    func rounded(toPlaces p: Int) -> Double { let m = pow(10, Double(p)); return (self * m).rounded() / m }
}

/// PWA `fmt` / `fmt1`: uygulamanın dilindeki binlik/ondalık ayırıcı, en çok 1 ondalık
private var trLocale: Locale { .current }
/// Sonsuz/NaN ya da Int sınırını aşan değer çökmesin; "–" yazılır (NU-31, CR-21)
func fmt0(_ x: Double) -> String { guard x.isFinite, abs(x) < 1e15 else { return "–" }; return Int(x.rounded()).formatted(.number.locale(trLocale)) }
func fmt1(_ x: Double) -> String { guard x.isFinite else { return "–" }; return x.formatted(.number.precision(.fractionLength(0...1)).locale(trLocale)) }


/// İki kart: yeterli genişlik varsa yan yana (iPhone Duo iç ekranı), yoksa alt alta.
/// Boyut sınıfına değil gerçek genişliğe bakar: kenar çubuğu açıkken ya da Split View'da dar kalan sütunda alt alta kalır.
struct BPair<A: View, B: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var a: A
    @ViewBuilder var b: B
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                a.frame(minWidth: 300, maxWidth: .infinity, alignment: .top)
                b.frame(minWidth: 300, maxWidth: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: spacing) { a; b }
        }
    }
}

/// Zeminsiz (ghost) ve kenarlıklı butonlarda yazı rengini değiştirir (ör. silme için kırmızı)
private struct BButtonFgKey: EnvironmentKey { static let defaultValue: Color? = nil }
extension EnvironmentValues {
    var bButtonFg: Color? { get { self[BButtonFgKey.self] } set { self[BButtonFgKey.self] = newValue } }
}
extension View {
    func bButtonFg(_ c: Color) -> some View { environment(\.bButtonFg, c) }
}
