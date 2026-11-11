import SwiftUI
import SwiftData
import VisionKit
import Vision
import GymPaperKit

/// VisionKit live barcode scanner (Add food › Barcode)
struct BarcodeScannerView: UIViewControllerRepresentable {
    var symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .code128]
    var onCode: (String) -> Void
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: symbologies)], qualityLevel: .balanced, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coord) { vc.stopScanning() }
    func makeCoordinator() -> Coord { Coord(onCode: onCode) }
    final class Coord: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var last = ""
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(b) in items { if let v = b.payloadStringValue, v != last { last = v; UINotificationFeedbackGenerator().notificationOccurred(.success); onCode(v) } }
        }
    }
}

/// Save a product with an unknown barcode using the label's per-100 g values
struct NutLabelForm: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SavedFood.createdAt, order: .reverse) private var saved: [SavedFood]
    let code: String
    var onBack: () -> Void
    var onSaved: (FoodItem) -> Void
    @State private var name = ""
    @State private var kcal = ""
    @State private var p = ""
    @State private var c = ""
    @State private var f = ""
    @State private var portion = ""

    var body: some View {
        let macroOK = nutNum(p) <= 100 && nutNum(c) <= 100 && nutNum(f) <= 100 && nutNum(p) + nutNum(c) + nutNum(f) <= 100
        // calories or a macro must be filled; an empty 0 kcal product isn't saved
        let ok = !name.trimmingCharacters(in: .whitespaces).isEmpty && nutNum(kcal) <= 900 && macroOK
            && (nutNum(kcal) > 0 || nutNum(p) + nutNum(c) + nutNum(f) > 0)
        HStack(spacing: 8) {
            Ti("barcode")
            Text("Barkod")
            Text(code).foregroundStyle(Color.bFg).monospacedDigit()
        }
        .font(.bSm).foregroundStyle(Color.bMutedFg)
        BField(label: "Ürün adı") { TextField("ör. Sütaş Yoğurt", text: $name).textFieldStyle(.b) }
        VStack(alignment: .leading, spacing: 8) {
            Text("Etiketteki 100 g değerleri").font(.geist(14, .medium, relativeTo: .subheadline))
            NutMacroInputs(kcal: $kcal, p: $p, c: $c, f: $f)
            Text(macroOK ? "Ondalık için virgül kullanabilirsin." : "Protein, karb. ve yağ 100 g içinde toplam 100 g’ı geçemez.")
                .font(.bXs).foregroundStyle(macroOK ? Color.bMutedFg : Color.bDestructive)
        }
        BField(label: "Porsiyon (g) · isteğe bağlı") {
            TextField("ör. 150", text: $portion).keyboardType(.decimalPad).textFieldStyle(.b)
                .onChange(of: portion) { _, v in let x = nutDecimal(v); if x != v { portion = x } }
        }
        VStack(spacing: 8) {
            Button { save() } label: { BLabel("Kaydet ve devam et", icon: "bookmark") }
                .buttonStyle(.b(.primary, .large, full: true)).disabled(!ok)
            Button("Geri", action: onBack).buttonStyle(.b(.ghost, full: true))
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        var per = Macros(kcal: max(0, nutNum(kcal)), p: max(0, nutNum(p)), c: max(0, nutNum(c)), f: max(0, nutNum(f)))
        if per.kcal == 0 { per.kcal = (per.p * 4 + per.c * 4 + per.f * 9).rounded() }
        let por: [String: Double] = nutNum(portion) > 0 ? ["porsiyon": min(nutMaxG, nutNum(portion))] : [:]
        // a food with the same name merges only if its values match too; a barcode never overwrites another product's
        if let same = saved.first(where: { nutSameName($0.name, n) }), same.per100 == per {
            if same.barcode == nil { same.barcode = code }
            Store.save(ctx); haptic()
            onSaved(FoodItem(id: "mine-\(same.persistentModelID.hashValue)", name: same.name, per100: same.per100, portions: same.portions, source: .mine, barcode: code))
            return
        }
        let finalName = saved.contains(where: { nutSameName($0.name, n) }) ? "\(n) · \(code.suffix(4))" : n
        ctx.insert(SavedFood(name: finalName, per100: per, portions: por, barcode: code))
        Store.save(ctx); haptic()
        onSaved(FoodItem(id: "label-\(code)", name: finalName, per100: per, portions: por, source: .mine, barcode: code))
    }
}
