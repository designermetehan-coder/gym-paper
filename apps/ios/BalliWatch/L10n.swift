import Foundation

/// Çalışma anında çeviri: anahtar Türkçe metnin kendisidir (Localizable.xcstrings, kaynak dil tr).
/// `String` alan bileşenler (BLabel, BSheet, toast…) ve veriden gelen etiketler (öğün, aktivite düzeyi…) için;
/// karşılığı yoksa metin aynen döner. Sabit metinlerde `Text("…")` / `String(localized: "…")` yeterli.
func tl(_ s: String) -> String {
    s.isEmpty ? s : Bundle.main.localizedString(forKey: s, value: s, table: nil)
}
