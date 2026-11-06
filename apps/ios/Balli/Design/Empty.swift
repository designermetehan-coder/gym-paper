import SwiftUI

// MARK: - Boş durum (TE-12)

/// Boş durum: SF Symbol kompozisyonu (halkalı yumuşak daire + ana sembol + köşede eylem rozeti),
/// kısa başlık ve metin, tek birincil eylem. Özet, Antrenmanlarım, Besinlerim, Ölçümlerim ve Beslenme'de ortak.
struct BEmpty: View {
    var symbol: String
    /// Köşedeki küçük rozet (genelde eylemi anlatır: plus, scalemass…); nil ise yok
    var badge: String? = "plus"
    var title: String
    var text: String
    var action: String? = nil
    /// Kart içinde gösterilecekse false (kendi kartını çizmez)
    var framed = true
    var perform: () -> Void = {}
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            BEmptyArt(symbol: symbol, badge: badge, size: framed ? 96 : 80, bounce: shown)
                .padding(.bottom, 16)
            Text(tl(title)).font(.bDisplay(20, relativeTo: .title3)).tracking(-0.3).foregroundStyle(Color.bFg)
                .multilineTextAlignment(.center)
            Text(tl(text)).font(.bSm).foregroundStyle(Color.bMutedFg).multilineTextAlignment(.center)
                .frame(maxWidth: 300).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button { haptic(); perform() } label: { Text(tl(action)) }
                    .buttonStyle(.b(.primary, .large))
                    .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, framed ? 24 : 0).padding(.vertical, framed ? 32 : 8)
        .background { if framed { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.bCard) } }
        .accessibilityElement(children: .contain)
        .onAppear { shown = true }
    }
}

/// Boş durum görseli: iç içe iki daire, hiyerarşik ana sembol, sağ altta ana renkte rozet.
/// Turuncu yok; ana renk siyaha yakın / kırık beyaz.
struct BEmptyArt: View {
    var symbol: String
    var badge: String?
    var size: CGFloat = 96
    var bounce = false
    var body: some View {
        ZStack {
            Circle().fill(Color.bFg.opacity(0.04)).frame(width: size, height: size)
            Circle().fill(Color.bFg.opacity(0.06)).frame(width: size * 0.74, height: size * 0.74)
            Image(systemName: symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.bFg)
                .symbolEffect(.bounce, value: bounce)
            if let badge {
                ZStack {
                    Circle().fill(Color.bBg).frame(width: size * 0.34, height: size * 0.34)
                    Circle().fill(Color.bPrimary).frame(width: size * 0.27, height: size * 0.27)
                    Image(systemName: badge).font(.system(size: size * 0.12, weight: .bold)).foregroundStyle(Color.bPrimaryFg)
                }
                .offset(x: size * 0.3, y: size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 16) {
        BEmpty(symbol: "dumbbell", title: "Henüz programın yok", text: "Hazır bir programla başla ya da kendininkini kur.", action: "Program seç")
        BEmpty(symbol: "fork.knife", title: "Bugün henüz kayıt yok", text: "Yediğini ekle; kalori ve makrolar kendiliğinden hesaplanır.", action: "Yediğini ekle")
    }
    .padding(20).background(Color.bBg)
}
