import SwiftUI
import SwiftData
import TipKit
import BalliKit

// Başlarken (ON-02): yeni kullanıcı Özet'in en üstünde kısa bir yapılacaklar listesi görür.
// Maddeler veriden kendiliğinden işaretlenir; elle de işaretlenebilir; X ile kapanır.
// Yalnız ilk açılış akışını bu sürümde tamamlayanlara gösterilir (güncelleyen eski kullanıcılara değil).

enum StartGuide {
    static let showKey = "start.show"
    static let manualKey = "start.manual"
}

struct StartChecklist: View {
    @Environment(AppState.self) private var app
    @Environment(HealthService.self) private var health
    @AppStorage(StartGuide.showKey) private var show = false
    @AppStorage(StartGuide.manualKey) private var manualRaw = ""
    @AppStorage("start.widget") private var widgetHint = false
    let hasProgram: Bool
    let didWorkout: Bool
    let didFood: Bool
    let didWeight: Bool

    struct Item: Identifiable { let id: String; let title: String; let sub: String; let auto: Bool; let action: () -> Void }

    private var manual: Set<String> { Set(manualRaw.split(separator: ",").map(String.init)) }

    private var items: [Item] {
        var a: [Item] = [
            Item(id: "program", title: "Programını seç", sub: "Hazır bir programla başla ya da kendininkini kur", auto: hasProgram) {
                app.tab = .workout; app.workoutPath = [.programs]
            },
            Item(id: "workout", title: "İlk antrenmanını yap", sub: "Antrenman › Başlat; setleri işaretle", auto: didWorkout) {
                app.tab = .workout
            },
            Item(id: "food", title: "Yediğin bir şeyi ekle", sub: "\"2 yumurta, 1 dilim ekmek\" yazman yeter", auto: didFood) {
                app.open(.addFood(date: DayKey.today, meal: nil))
            },
            Item(id: "weight", title: "Kilonu gir", sub: "İlerlemen buna göre çizilir", auto: didWeight) {
                app.open(.measure(quick: true))
            },
        ]
        if health.available {
            a.append(Item(id: "health", title: "Apple Sağlık'a bağlan", sub: "Adım ve kalori ihtiyacın için", auto: health.authorized) {
                Task { await health.requestAccess() }
            })
        }
        a.append(Item(id: "widget", title: "Ana ekrana widget ekle", sub: "Ana ekranda boş yere basılı tut › + › GYM Paper", auto: false) {
            widgetHint = true
            app.toast("Ana ekranda boş bir yere basılı tut, + ile GYM Paper'ı seç")
        })
        return a
    }

    private func done(_ i: Item) -> Bool { i.auto || manual.contains(i.id) }

    var body: some View {
        let list = items
        let n = list.filter(done).count
        let forced = ProcessInfo.processInfo.arguments.contains("-startGuide")   // ekran görüntüsü
        if (show || forced) && n < list.count {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Başlarken").font(.bDisplay(20, relativeTo: .title3)).foregroundStyle(Color.bFg)
                        Text("\(n)/\(list.count) tamamlandı").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
                    }
                    Spacer()
                    Button {
                        haptic(); withAnimation(.snappy) { show = false }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.bMutedFg)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel("Başlarken listesini kapat")
                    .padding(.trailing, -12).padding(.top, -10)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.bFg.opacity(0.08))
                        Capsule().fill(Color.bPrimary).frame(width: g.size.width * CGFloat(n) / CGFloat(max(1, list.count)))
                    }
                }
                .frame(height: 4).padding(.top, 10).padding(.bottom, 6)
                .animation(.snappy, value: n)
                ForEach(list) { i in row(i) }
            }
            .bCard(padding: 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func row(_ i: Item) -> some View {
        let d = done(i)
        return HStack(spacing: 12) {
            Button { toggle(i) } label: {
                Image(systemName: d ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(d ? Color.bSuccess : Color.bFg.opacity(0.25))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .disabled(i.auto)
            .accessibilityLabel(d ? "\(i.title), tamamlandı" : "\(i.title), tamamlandı olarak işaretle")
            Button { haptic(); i.action() } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tl(i.title)).font(.geist(15, .semibold)).foregroundStyle(d ? Color.bMutedFg : Color.bFg)
                            .strikethrough(d, color: Color.bMutedFg)
                        if !d { Text(tl(i.sub)).font(.bXs).foregroundStyle(Color.bMutedFg).fixedSize(horizontal: false, vertical: true) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !d { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.bMutedFg) }
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .disabled(d)
        }
        .padding(.leading, -10)
    }

    private func toggle(_ i: Item) {
        haptic()
        var m = manual
        if m.contains(i.id) { m.remove(i.id) } else { m.insert(i.id) }
        withAnimation(.snappy) { manualRaw = m.sorted().joined(separator: ",") }
    }
}

// MARK: - İpuçları (ON-03): arada bir, bir kez gösterilen kısa balonlar (TipKit)

/// İpuçları yalnız ilk açılış akışı bittikten sonra görünür: akışın üstüne arkadaki ekranın ipucu binmesin (2 Kas)
enum TipGate {
    @Parameter static var appReady: Bool = false
}
extension Tip {
    var gateRules: [Rule] { [#Rule(TipGate.$appReady) { $0 == true }] }
}

enum BTips {
    static func configure() {
        let a = ProcessInfo.processInfo.arguments
        if a.contains("-demo") { Tips.hideAllTipsForTesting() }   // ekran görüntülerinde ipucu yok
        try? Tips.configure([.displayFrequency(.daily)])
    }
}

struct TipEditSummary: Tip {
    var title: Text { Text("Özet senin") }
    var message: Text? { Text("Kartları ekle, kaldır, sırala; küçük ya da geniş seç.") }
    var image: Image? { Image(systemName: "square.grid.2x2") }
    var rules: [Rule] { gateRules }
}

struct TipStartWorkout: Tip {
    var title: Text { Text("Antrenmanı başlat") }
    var message: Text? { Text("Müzik çalar gibi ilerler: seti bitirince dinlenme sayacı kendiliğinden başlar.") }
    var image: Image? { Image(systemName: "play.circle") }
    var rules: [Rule] { gateRules }
}

struct TipCompleteSet: Tip {
    var title: Text { Text("Seti tamamla") }
    var message: Text? { Text("Kiloyu ve tekrarı üstten değiştir; bu düğme seti kaydedip dinlenmeyi başlatır.") }
    var image: Image? { Image(systemName: "forward.end") }
    var rules: [Rule] { gateRules }
}

struct TipAddFood: Tip {
    var title: Text { Text("Yazman yeter") }
    var message: Text? { Text("\"2 yumurta, 1 dilim ekmek\" yaz ya da barkodu okut; kalori ve makrolar hesaplansın.") }
    var image: Image? { Image(systemName: "text.cursor") }
    var rules: [Rule] { gateRules }
}
