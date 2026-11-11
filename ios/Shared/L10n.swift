import Foundation

/// Runtime translation: the key is the Turkish text itself (Localizable.xcstrings, source language tr).
/// For components that take a `String` (BLabel, BSheet, toast…) and labels coming from data (meal, activity level…);
/// returns the text unchanged when there's no translation. For fixed text `Text("…")` / `String(localized: "…")` is enough.
func tl(_ s: String) -> String {
    s.isEmpty ? s : Bundle.main.localizedString(forKey: s, value: s, table: nil)
}
