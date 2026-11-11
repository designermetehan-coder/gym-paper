import SwiftUI
import UIKit

// GYM Paper design language: tokens mirror the Figma variables.
// Light/dark themes are automatic. Type is SF Pro (system); large numbers SF Pro Heavy Italic. Icons: Tabler (Assets › Tabler).

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
    static let bBg = d(0xF2F2F5, 0x0A0A0A)   // light mode: gray canvas, white cards
    static let bFg = d(0x0A0A0A, 0xE5E5E7)
    static let bCard = d(0xFFFFFF, 0x171717)
    /// Primary color: natural near-black (off-white #E5E5E7 in dark mode, not pure white)
    static let bPrimary = d(0x1C1C1E, 0xE5E5E7)
    static let bPrimaryFg = d(0xFAFAFA, 0x1C1C1E)
    /// Primary action: neon lime fill, dark navy text (same in both themes; high contrast on dark)
    static let bAction = d(0xC6FF3D, 0xC6FF3D)
    static let bActionFg = d(0x121826, 0x121826)
    /// Text buttons (no fill): readable dark olive in light mode, neon lime in dark mode
    static let bLink = d(0x4A6B00, 0xC6FF3D)
    /// Selected tab: brand lime in dark mode; primary color in light mode, where lime on glass is unreadable
    static let bTab = d(0x1C1C1E, 0xC6FF3D)
    /// Selected day: primary color (near-black; off-white in dark mode)
    static let bSel = d(0x1C1C1E, 0xE5E5E7)
    static let bSelFg = d(0xFAFAFA, 0x1C1C1E)
    static let bSecondary = d(0xE5E5EA, 0x262626)   // stands apart from the #F2F2F5 canvas in light mode
    static let bMuted = d(0xF5F5F5, 0x262626)
    static let bMutedFg = d(0x666666, 0xA1A1A1)   // AA contrast
    static let bBorder = d(0xE5E5E5, 0xFFFFFF, da: 0.10)
    static let bInput = d(0xE5E5E5, 0xFFFFFF, da: 0.15)
    static let bAccent = d(0xF5F5F5, 0x262626)
    static let bDestructive = d(0xE7000B, 0xFF6467)
    static let bSuccess = d(0x15803D, 0x26C55F)   // 5:1 on white
    static let bChart2 = d(0x737373, 0xA1A1A1)
    static let bChart4 = d(0x525252, 0x525252)
    /// Tonal secondary button text
    static let bTonalText = d(0x1C1C1E, 0xE5E5E7)
    static let bSky = Color(red: 0.055, green: 0.647, blue: 0.914)
    // Activity rings (Figma color/data/*): steps, workout, protein
    static let bRingSteps = d(0xFA114F, 0xFA114F)
    static let bRingWorkout = d(0x6BD60A, 0x92E82A)
    static let bRingProtein = d(0x00B8E6, 0x1EEAEF)
    // Macros (Figma color/macro/*): carb is yellow-green so it never reads as protein
    static let bProtein = d(0xE0144C, 0xE0144C)
    static let bCarb = d(0x86A300, 0xC9E83A)
    static let bFat = d(0x0A7AE0, 0x0A7AE0)
    // Weekly training volume per muscle (Figma color/volume/1-4): 1-4, 5-9, 10-20, 20+ sets
    static let bVolume1 = d(0xA6E3B8, 0x1F4D31)
    static let bVolume2 = d(0x55C97D, 0x2A8A50)
    static let bVolume3 = d(0x16A34A, 0x26C55F)
    static let bVolume4 = d(0x0B5E2B, 0x86F0AE)
    /// Hero card (Today's workout, Progress weight): near-black in both themes, light text
    // Hero cards: standard graphite (#1C1C1E) in both modes (dark-mode color trials reverted)
    static let bHero = d(0x1C1C1E, 0x1C1C1E)
    static let bHeroFg = d(0xFAFAFA, 0xFAFAFA)
    static let bHeroMuted = d(0xFAFAFA, 0xFAFAFA, la: 0.64, da: 0.64)
    static let bHeroFill = d(0xFAFAFA, 0xFAFAFA, la: 0.12, da: 0.12)
    static let bHeroAccent = d(0xC6FF3D, 0xC6FF3D)
    /// Filled highlight on a hero card (done days, progress) and what sits on it
    static let bHeroHi = d(0xC6FF3D, 0xC6FF3D)
    static let bHeroOnHi = d(0x121826, 0x121826)
    /// Figma alpha/lime-d-20 base color (#92E82A): the dark-mode hero tint, used at 20%
    static let bHeroTint = d(0x92E82A, 0x92E82A)
    /// Lime wash strength (Figma effect/wash-opacity): 70% light, 20% dark
    static let bWashOpacity: (light: Double, dark: Double) = (0.7, 0.2)
    // Workout metrics — Apple Fitness color language (time yellow, calories red); readable tones in light mode
    static let fitTime = d(0x8A6700, 0xFFD60A)   // 2.97:1 → ~4.9:1 in light mode
    static let fitKcal = d(0xE0144C, 0xFF375F)
    static let fitPurple = d(0x7A3FF2, 0xA97CFF)
    static let fitBlue = d(0x0A7AE0, 0x40C8FF)
    static let fitGreen = d(0x1E9E3E, 0x5FE07A)
    // Steps map: one green ramp, few steps → many. Light mode goes light to dark, dark mode dim to bright.
    static let stepTier1 = d(0xD3EFDA, 0x1C3523)
    static let stepTier2 = d(0xA6DDB3, 0x23492E)
    static let stepTier3 = d(0x76C88B, 0x2A6A3B)
    static let stepTier4 = d(0x4BAE66, 0x34904E)
    static let stepTier5 = d(0x2A8F48, 0x4FBE6A)
    static let stepTier6 = d(0x167A33, 0x7CF08F)
    static func ringGradient(_ c: Color) -> [Color] {
        // slightly darker to lighter along the ring (like Watch)
        [c.opacity(0.85), c]
    }
}

// MARK: - Type (system font SF Pro; large numbers SF Pro Heavy Italic)

extension Font {
    /// Body text: SF Pro, scales with Dynamic Type (the name is historical)
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .system(size: scaled(size, style), weight: weight)
    }
    /// Emphasis (buttons, screen titles): SF Pro Bold Italic
    static func bDisplay(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .system(size: scaled(size, style), weight: .bold).italic()
    }
    /// Large numbers (time, kcal, kg, countdowns): SF Pro Heavy Italic with fixed-width digits.
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
        // Cap at accessibility sizes: large numbers stop at xxxL, text at AX3; otherwise titles and numbers
        // broke mid-word ("Workou/t", "88 , kg 4")
        let cur = UITraitCollection.current.preferredContentSizeCategory
        let cap: UIContentSizeCategory = size >= 24 ? .extraExtraExtraLarge : .accessibilityLarge
        let traits = UITraitCollection(preferredContentSizeCategory: min(cur, cap))
        return UIFontMetrics(forTextStyle: ui).scaledValue(for: size, compatibleWith: traits)
    }
    // Tailwind sizes (computed, so they rescale when Dynamic Type changes)
    static var bXs: Font { geist(12, relativeTo: .caption) }            // text-xs
    static var bSm: Font { geist(14, relativeTo: .subheadline) }        // text-sm
    static var bBase: Font { geist(16) }                                 // text-base
    static var bLg: Font { geist(18, .semibold, relativeTo: .title3) }  // text-lg
    static var bXl: Font { geist(20, .semibold, relativeTo: .title3) }  // text-xl
    static var b2xl: Font { geist(24, .semibold, relativeTo: .title2) } // text-2xl
}

// MARK: - Tabler icons

/// Corner radii = Figma radius/*: every card radius/lg 20 (light, hero, tiles on the canvas); things nested in a card
/// radius/md 16 (inner tiles, chips); small boxes radius/sm 12 (thumbnails, icon badges). Pills use Capsule.
enum BRadius {
    static let card: CGFloat = 20
    static let inner: CGFloat = 16
    static let small: CGFloat = 12
}

/// Hero card surface: graphite (#1C1C1E) in both modes
struct BHeroSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: BRadius.card, style: .continuous)
        content.background(Color.bHero, in: shape)
    }
}

private struct BOnHeroKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Inside a hero card (bHeroCard)
    var bOnHero: Bool { get { self[BOnHeroKey.self] } set { self[BOnHeroKey.self] = newValue } }
}

struct BInvertedScheme: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.environment(\.colorScheme, scheme == .dark ? .light : .dark) }
}

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
            .background(Color.bCard, in: RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
            .overlay {
                // no shadow or border; only a highlighted card gets a colored outline
                if let highlight { RoundedRectangle(cornerRadius: BRadius.card, style: .continuous).strokeBorder(highlight, lineWidth: 1) }
            }
    }
}

extension View {
    func bCard(padding: CGFloat = 16, highlight: Color? = nil) -> some View { modifier(BCardModifier(padding: padding, highlight: highlight)) }
    /// Dark hero card (card radius, 20 pt padding)
    func bHeroCard(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.bHeroFg)
            .background(Color.bHero, in: RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
    /// Flips the color scheme: hero surfaces are dark on the light app and light on the dark app
    func bInverted() -> some View { modifier(BInvertedScheme()) }
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
    /// Inside a hero card shown light (the lime card in the dark app): primary turns ink with lime text
    @Environment(\.bOnHero) private var onHero
    private var limeHero: Bool { onHero && scheme == .light }

    func makeBody(configuration c: Configuration) -> some View {
        let h: CGFloat = switch size { case .small: 32; case .large: 48; case .icon: 40; case .iconLarge: 44; case .regular: 44 }
        let isIcon = size == .icon || size == .iconLarge
        c.label
            .font(size == .large ? .bDisplay(16, relativeTo: .body) : .bDisplay(14, relativeTo: .subheadline))
            .lineLimit(1).minimumScaleFactor(0.7)   // shrinks instead of truncating at large text sizes
            .padding(.horizontal, isIcon ? 0 : (size == .large ? 24 : size == .small ? 12 : 16))
            .frame(minWidth: isIcon ? h : nil, maxWidth: fullWidth ? .infinity : nil, minHeight: h)
            .foregroundStyle(fg)
            .background(bg(c.isPressed), in: Capsule())
            .overlay {
                if variant == .outline { Capsule().strokeBorder(scheme == .dark ? Color.bInput : Color.bBorder, lineWidth: 1) }
            }
            // small buttons (32/40 pt) get a 44 pt touch area without changing their look
            .padding(max(0, (44 - h) / 2)).contentShape(Rectangle()).padding(-max(0, (44 - h) / 2))
            .scaleEffect(c.isPressed ? 0.96 : 1)
            .opacity(enabled ? 1 : 0.5)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: c.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: c.isPressed) { _, new in new }
    }
    private var fg: Color {
        switch variant {
        case .primary: limeHero ? .bAction : .bActionFg
        case .destructive: .white
        case .tonal: .bTonalText
        case .ghost: customFg ?? ((size == .icon || size == .iconLarge) ? .bFg : .bLink)
        default: customFg ?? .bFg
        }
    }
    private func bg(_ pressed: Bool) -> AnyShapeStyle {
        switch variant {
        case .primary: AnyShapeStyle((limeHero ? Color(red: 0.07, green: 0.09, blue: 0.15) : Color.bAction).opacity(pressed ? 0.85 : 1))
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

/// Plain button that shrinks slightly when pressed (.press)
struct PressStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.contentShape(Rectangle()).scaleEffect(c.isPressed ? 0.97 : 1).opacity(c.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: c.isPressed)
    }
}
extension ButtonStyle where Self == PressStyle { static var press: PressStyle { PressStyle() } }

/// Text label (gap-2)
@MainActor
struct BLabel: View {
    let text: String; let icon: String?
    var trailing = false
    init(_ text: String, icon: String? = nil, trailing: Bool = false) { self.text = text; self.icon = icon; self.trailing = trailing }
    var body: some View {
        // Text buttons carry no icon; icon-only buttons use Ti
        Text(tl(text))
    }
}

// MARK: - Progress, badge, ring

struct BProgress: View {
    @State private var appeared = false
    var value: Double          // 0…1
    var tint: Color = .bPrimary
    var height: CGFloat = 6
    var track: Color? = nil
    /// What the progress is for, read by VoiceOver
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

/// Apple Watch style nested rings (outer to inner)
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
                    // second lap once the goal is exceeded (like Watch)
                    if v > 1 {
                        Circle().trim(from: 0, to: appeared ? min(1, v - 1) : 0)
                            .stroke(r.tint, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: .black.opacity(0.35), radius: 1.5)
                    }
                }
                .padding(inset)
                .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.9).delay(0.1 + Double(i) * 0.08), value: appeared)
                // when the value changes, rings fill outer to inner 80 ms apart
                .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.6).delay(Double(i) * 0.08), value: v)
            }
            content
        }
        .frame(width: size, height: size)
        .onAppear { appeared = true }
    }
}

// MARK: - Screen header

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
                    .lineLimit(1).minimumScaleFactor(0.6)   // single-word titles must not break
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

/// Round header button: Liquid Glass on iOS 26, outline pill before (44 pt)
struct BRoundIcon: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) { Ti(icon, size: 20) }
            .buttonStyle(BGlassIconStyle()).accessibilityLabel(tl(label))
    }
}

/// 44 pt circular glass button used for every header/toolbar icon action
struct BGlassIconStyle: ButtonStyle {
    var size: CGFloat = 44
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .foregroundStyle(Color.bFg)
            .frame(width: size, height: size)
            .modifier(BGlassCircle())
            .contentShape(Circle())
            .scaleEffect(c.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: c.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: c.isPressed) { _, new in new }
    }
}

struct BGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.bFg.opacity(0.08), lineWidth: 1))
        }
    }
}

// MARK: - Lime wash (Figma "Gradient Wash")

enum BWashStyle { case none, dominant, full, sheet, bar }

/// Lime gradient behind a screen's top area. Dominant: tabs; Full: player; Sheet: modal sheets;
/// Bar: sub screens (pushed, Profile), only as tall as the nav bar area
struct BWash: View {
    var style: BWashStyle = .dominant
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if style != .none {
            Color.bAction
                .opacity(scheme == .dark ? Color.bWashOpacity.dark : Color.bWashOpacity.light)
                .mask(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom))
                .frame(height: height)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
    private var height: CGFloat? {
        // dominant (main tabs): shorter since the gray eyebrow left the headers
        switch style { case .full: nil; case .sheet: 280; case .bar: 170; default: 380 }
    }
    private var stops: [Gradient.Stop] {
        switch style {
        case .full: [.init(color: .black, location: 0), .init(color: .black.opacity(0.75), location: 0.55), .init(color: .black.opacity(0.2), location: 1)]
        case .sheet: [.init(color: .black.opacity(0.9), location: 0), .init(color: .clear, location: 1)]
        case .bar: [.init(color: .black, location: 0), .init(color: .black.opacity(0.6), location: 0.5), .init(color: .clear, location: 1)]
        default: [.init(color: .black, location: 0), .init(color: .black.opacity(0.45), location: 0.45), .init(color: .clear, location: 1)]
        }
    }
}

// MARK: - Ekran iskeleti

private struct MiniInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    /// Bottom inset added to screens while the mini player is visible
    var miniPlayerInset: CGFloat { get { self[MiniInsetKey.self] } set { self[MiniInsetKey.self] = newValue } }
}

struct BScreen<C: View>: View {
    @Environment(\.miniPlayerInset) private var miniInset
    /// Top safe area: close to 0 on iPhone Duo, where the status bar is on the side
    @State private var topInset: CGFloat = 60
    @State private var bottomInset: CGFloat = 0
    /// Duo stand pose: measured card heights per pane (how many fit in the top half)
    @State private var paneHeights: [AnyHashable: CGFloat] = [:]
    private let headKey: AnyHashable = "__head"
    var spacing: CGFloat = 16
    var wash: BWashStyle = .dominant
    /// Tall pushed headers (back + title + sub) scroll with the content instead of pinning;
    /// pinned, content showed through them under the soft edge
    var pinHeader = true
    @ViewBuilder var content: C
    var body: some View {
        // The first item (header) stays pinned; the rest scrolls below it
        Group(subviews: content) { subs in
            // iPhone Duo half-folded: cards split into the two panes beside the hinge; nothing sits on the hinge band
            DuoFoldReader { fold in
                if let fold {
                    duoPanes(subs, fold: fold)
                } else {
                    flatBody(subs)
                }
            }
        }
        // Behind the tab bar: progressive blur separating it from content
        // no progressive blur on iPhone Duo (status bar on the side, small topInset)
        // with the mini player, a single blur extends up over it
        .overlay(alignment: .bottom) {
            if topInset >= 24 {
                BBottomFade(height: bottomInset + 28 + (miniInset > 0 ? miniInset + 12 : 0))
                    .ignoresSafeArea(edges: .bottom).allowsHitTesting(false)
                    .animation(.smooth(duration: 0.3), value: miniInset)
            }
        }
        // sub screens (pushed, header scrolls) get the short bar-height wash
        .background { ZStack(alignment: .top) { Color.bBg; BWash(style: !pinHeader && wash == .dominant ? .bar : wash) }.ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
    }

    /// Flat screen (iPhone, Duo flat open/closed)
    @ViewBuilder private func flatBody(_ subs: SubviewsCollection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                if !pinHeader, let head = subs.first { head.padding(.top, topInset < 24 ? 16 : 0) }
                // cards rise in sequence when the screen opens
                ForEach(Array(subs.dropFirst().enumerated()), id: \.element.id) { i, sub in
                    sub.modifier(BRise(index: i + 1))
                }
            }
            // iPhone Duo inner screen / Split View: rows don't stretch on very wide layouts
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)   // iOS 26 system margin (aligned with the tab bar)
            .padding(.top, 4)
            .padding(.bottom, 24 + miniInset)   // keep the last item clear of the mini player
        }
        .scrollDismissesKeyboard(.interactively)
        // Screenshots: -scrollBottom opens at the end of the page (muscle map shots)
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-scrollBottom") ? .bottom : nil)
        // Header: progressive blur against content scrolling under it (system edge effect on iOS 26)
        .modifier(BTopBar(plain: topInset < 24) {
            if pinHeader, let head = subs.first {
                head
                    // If the status bar isn't on top (iPhone Duo), keep the header off the screen edge
                    .padding(.top, topInset < 24 ? 16 : 0)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
            }
        })
    }

    /// Half-folded Duo: book pose (vertical hinge) gives left/right panes, stand pose (horizontal hinge) top/bottom.
    /// Each pane scrolls on its own; the header starts the first pane. Cards are split in order.
    @ViewBuilder private func duoPanes(_ subs: SubviewsCollection, fold: CGRect) -> some View {
        let rest = Array(subs.dropFirst())
        let cut = fold.width < fold.height ? (rest.count + 1) / 2 : standCut(rest, room: fold.minY)
        let a = Array(rest.prefix(cut)), b = Array(rest.dropFirst(cut))
        if fold.width < fold.height {
            HStack(spacing: 0) {
                duoPane(a, head: subs.first, start: 1).frame(width: max(0, fold.minX))
                Color.clear.frame(width: fold.width)
                duoPane(b, head: nil, start: cut + 1).frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                duoPane(a, head: subs.first, start: 1).frame(height: max(0, fold.minY))
                Color.clear.frame(height: fold.height)
                duoPane(b, head: nil, start: cut + 1).frame(maxHeight: .infinity)
            }
        }
    }

    /// Cards that fit in the top half in stand pose: filled in order from measured heights, never cut at the hinge
    private func standCut(_ items: [Subview], room: CGFloat) -> Int {
        var used = (paneHeights[headKey] ?? 56) + 16 + 4
        var n = 0
        for it in items {
            guard let h = paneHeights[AnyHashable(it.id)] else { break }
            if h < 1 { n += 1; continue }   // empty view (e.g. hidden Getting started list)
            if used + spacing + h > room - 8 { break }
            used += spacing + h; n += 1
        }
        return n
    }

    private func duoPane(_ items: [Subview], head: Subview?, start: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                if let head {
                    head.padding(.top, 16)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { paneHeights[headKey] = $0 }
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { i, sub in
                    sub.modifier(BRise(index: start + i))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { paneHeights[AnyHashable(sub.id)] = $0 }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, head == nil ? 16 : 4)
            .padding(.bottom, 24 + miniInset)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollClipDisabled(false)
    }
}

/// Progressive blur for the bottom edge (behind the tab bar): material + mask fading upward
struct BBottomFade: View {
    var height: CGFloat
    var body: some View {
        ZStack {
            // The material turns gray in dark mode; the canvas color on top keeps it in tone with the background
            Rectangle().fill(.ultraThinMaterial)
            Color.bBg.opacity(0.78)
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.8), location: 0.45), .init(color: .black, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .frame(height: max(0, height))
    }
}

/// Pinned header bar: `safeAreaBar` + soft scroll edge effect on iOS 26 (system progressive blur);
/// material + downward fading mask on iOS 18 for the same feel
struct BTopBar<H: View>: ViewModifier {
    /// iPhone Duo: no blur; the header sits above the scroll view on the screen's own wash (no opaque band)
    var plain = false
    @ViewBuilder var head: H
    func body(content: Content) -> some View {
        if plain {
            VStack(spacing: 0) { head; content }
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

/// While scrolling, cards "float" slightly: they shrink a bit and lag near the screen edges
struct BFloat: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        if reduce { content } else {
            content.visualEffect { c, proxy in
                let f = proxy.frame(in: .scrollView(axis: .vertical))
                let h = proxy.bounds(of: .scrollView(axis: .vertical))?.height ?? 800
                // 0 = middle of the visible area, ±1 = edges
                let mid = (f.midY - h / 2) / max(1, h / 2)
                let edge = max(0, abs(mid) - 0.55)
                return c
                    .scaleEffect(1 - min(0.035, edge * 0.06), anchor: mid > 0 ? .top : .bottom)
                    .offset(y: mid * 4)
            }
        }
    }
}

/// Card rises 10 pt while fading in on first appearance (staggered)
struct BRise: ViewModifier {
    var index: Int
    /// Delay per item and initial delay (for a more visible sequence, e.g. the finish summary)
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

/// "Pop" on first appearance: grows from small, overshoots ~15% and settles (trophy, record badge)
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

/// Slight shrink + haptic on press (for cards)
extension View {
    func bPop<V: Equatable>(_ value: V) -> some View {
        self.phaseAnimator([false, true], trigger: value) { v, up in v.scaleEffect(up ? 1.03 : 1) } animation: { up in up ? .spring(response: 0.18, dampingFraction: 0.6) : .spring(response: 0.35, dampingFraction: 0.55) }
    }
}

// MARK: - Confirmation sheet (matches the UI instead of a system alert)

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

// MARK: - Swipe to delete

/// Swipe the row left: a red "Delete" appears; a full swipe or a tap on Delete removes it.
/// Doesn't block vertical scrolling (only horizontal drags are captured).
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
                    // while swiping or with Delete open, the row's own tap (open detail) is disabled
                    .disabled(dragging || open)
                    .overlay {
                        if open && !dragging {
                            Color.clear.contentShape(Rectangle()).onTapGesture { snap(open: false) }
                        }
                    }
                    .offset(x: x)
            }
            // also updates when the width changes (rotation, Duo fold); no GeometryReader per row
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .clipped()
            // If the scroll view takes over and cancels, onEnded never fires: recover when the GestureState resets
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
                            // the touch at release must not open the row
                            Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); dragging = false }
                        }
                        guard horizontal == true else { return }
                        let base: CGFloat = open ? -reveal : 0
                        let t = base + v.predictedEndTranslation.width
                        // Swiping only reveals Delete; deleting happens after tapping Delete and confirming
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
    /// Ask for confirmation first
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

/// Shared segmented control: gray capsule (bMuted), selected item is a card-colored pill with a soft shadow.
/// The pill slides with the selection (matchedGeometryEffect) with a light haptic. Figma: Components / Segmented.
struct BSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    /// Kept for older call sites; every segmented control now uses the same neutral look.
    var neutral = true
    @Environment(\.colorScheme) private var scheme
    @Namespace private var ns
    private var dark: Bool { scheme == .dark }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { v, l in
                let on = v == selection
                Button {
                    guard v != selection else { return }
                    haptic()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { selection = v }
                } label: {
                    // never truncate at large text: shrinks, and the row grows with the text
                    Text(tl(l)).font(.geist(14, on ? .semibold : .medium, relativeTo: .subheadline)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(on ? Color.bFg : Color.bMutedFg)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if on {
                                Capsule().fill(dark ? Color.bFg.opacity(0.14) : Color.bCard)
                                    .shadow(color: .black.opacity(dark ? 0 : 0.06), radius: 6, y: 2)
                                    .shadow(color: .black.opacity(dark ? 0 : 0.05), radius: 1, y: 0.5)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                        .animation(.easeOut(duration: 0.18), value: on)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(4)
        .frame(minHeight: 44)
        // ink-tinted track: stays visible on the green wash and on cards (solid gray vanished on both)
        .background(Color.bFg.opacity(dark ? 0.10 : 0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.bFg.opacity(dark ? 0.08 : 0.05), lineWidth: 1))
    }
}

// MARK: - Stepper (− value +)

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

/// Value box: large value in the brand color; tapping opens a wheel picker (no −/+)
struct BPickField: View {
    let label: String
    @Binding var value: Double
    var values: [Double]
    var suffix: String? = nil
    var format: (Double) -> String = { fmt1($0) }
    var height: CGFloat = 64
    /// Text shown when the value is 0 (e.g. "–" instead of "0 kg" for bodyweight exercises)
    var zeroText: String? = nil
    /// Value the picker opens on when the value is 0 (e.g. previous/planned weight)
    var startValue: Double? = nil
    /// Picker title when the label is hidden
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

/// Weight entry with the keyboard: tapping the box opens a decimal keyboard and the value is typed in place.
/// Comma and dot are accepted; only "Done" above the keyboard. The value is saved when focus leaves.
struct BKgField: View {
    let label: String
    @Binding var value: Double
    var suffix: String? = nil
    var height: CGFloat = 64
    /// Hint shown when empty (value 0), e.g. "–" or the previous/planned weight
    var placeholder: String = "–"
    /// Accessibility title when the label is hidden
    var title: String? = nil
    var maxValue: Double = 500
    /// No fill of its own (when embedded in a card, e.g. the player's weight stepper)
    var plain = false
    @State private var text = ""
    @FocusState private var focused: Bool
    private var compact: Bool { height < 56 }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
        VStack(spacing: 2) {
            if !label.isEmpty { Text(tl(label)).font(.geist(12, .medium, relativeTo: .caption)).foregroundStyle(Color.bMutedFg) }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.bMutedFg))
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .font(.bNum(compact ? 18 : 26))
                    .foregroundStyle(Color.bPrimary)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .accessibilityLabel(label.isEmpty ? (title ?? "") : tl(label))
                if let suffix, !text.isEmpty {
                    Text(suffix).font(.geist(compact ? 13 : 15, .semibold, relativeTo: .subheadline)).foregroundStyle(Color.bPrimary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .background(Color.bFg.opacity(focused ? 0.11 : (plain ? 0 : 0.07)), in: shape)
        .overlay { if focused { shape.strokeBorder(Color.bPrimary.opacity(0.3), lineWidth: 1.5) } }
        .contentShape(shape)
        .onTapGesture { if !focused { focused = true; haptic() } }
        .animation(.snappy(duration: 0.2), value: focused)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focused { Spacer(); Button("Bitti") { focused = false }.font(.geist(16, .semibold)) }
            }
        }
        .onAppear { text = Self.show(value) }
        .onChange(of: value) { _, v in if !focused { let t = Self.show(v); if t != text { text = t } } }
        .onChange(of: text) { _, v in let c = Self.clean(v); if c != v { text = c } }
        .onChange(of: focused) { _, f in if !f { commit() } }
        .onDisappear { if focused { commit() } }
    }
    private func commit() {
        let n = text.isEmpty ? 0 : min(maxValue, max(0, trNum(text))).rounded(toPlaces: 2)
        if n != value { value = n; haptic() }
        text = Self.show(n)
    }
    static func show(_ v: Double) -> String {
        v > 0 ? v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(trLocale)) : ""
    }
    /// Digits and one decimal separator only; at most 2 decimals and 4 whole digits
    static func clean(_ s: String) -> String {
        var out = "", sep = false, dec = 0, whole = 0
        for ch in s {
            if ch.isASCII, ch.isNumber {
                if sep { guard dec < 2 else { continue }; dec += 1 } else { guard whole < 4 else { continue }; whole += 1 }
                out.append(ch)
            } else if (ch == "," || ch == "."), !sep {
                sep = true; out.append(out.isEmpty ? "0" : ""); out.append(ch)
            }
        }
        return out
    }
}

// MARK: - Input field

struct BFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var scheme
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.geist(16)).monospacedDigit()
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(scheme == .dark ? Color.white.opacity(0.045) : Color.clear, in: RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
            .overlay { if scheme == .light { RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous).strokeBorder(Color.bInput) } }
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
    /// Pushed as a detail screen instead of a sheet: back button + large title
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
                Button { dismiss() } label: { Ti("x", size: 20) }.buttonStyle(BGlassIconStyle()).accessibilityLabel(tl("Kapat"))
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
        // sheets stay plain (temporary layer); the wash belongs to full screens
        .background { ZStack(alignment: .top) { Color.bBg; if pushed { BWash(style: .bar) } }.ignoresSafeArea() }
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

/// Number of open sheets: the main screen behind is dimmed further
@MainActor @Observable final class SheetDim { static let shared = SheetDim(); var count = 0 }

// MARK: - Checkbox

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

// MARK: - Helpers

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) { UIImpactFeedbackGenerator(style: style).impactOccurred() }

extension Double {
    func rounded(toPlaces p: Int) -> Double { let m = pow(10, Double(p)); return (self * m).rounded() / m }
}

/// Thousands/decimal separators of the app language, at most 1 decimal
private var trLocale: Locale { .current }
/// Infinite/NaN or values beyond Int must not crash; shows "–"
func fmt0(_ x: Double) -> String { guard x.isFinite, abs(x) < 1e15 else { return "–" }; return Int(x.rounded()).formatted(.number.locale(trLocale)) }
func fmt1(_ x: Double) -> String { guard x.isFinite else { return "–" }; return x.formatted(.number.precision(.fractionLength(0...1)).locale(trLocale)) }


/// Two cards: side by side when there is room (iPhone Duo inner screen), stacked otherwise.
/// Uses the real width, not the size class: stacks in a narrow column with a sidebar or in Split View.
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

/// Changes the text color of ghost and outline buttons (e.g. red for delete)
private struct BButtonFgKey: EnvironmentKey { static let defaultValue: Color? = nil }
extension EnvironmentValues {
    var bButtonFg: Color? { get { self[BButtonFgKey.self] } set { self[BButtonFgKey.self] = newValue } }
}
extension View {
    func bButtonFg(_ c: Color) -> some View { environment(\.bButtonFg, c) }
}
