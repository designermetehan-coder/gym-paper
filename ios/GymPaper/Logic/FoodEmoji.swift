import Foundation
import GymPaperKit

/// Visual (emoji) by food name. No license needed, works offline; a product photo wins when present.
enum FoodEmoji {
    // more specific keys first
    private static let rules: [(String, String)] = [
        ("whey", "🥤"), ("protein bar", "🍫"), ("protein puding", "🍮"), ("protein shake", "🥤"), ("protein sut", "🥛"),
        ("yumurta", "🥚"), ("omlet", "🍳"), ("menemen", "🍳"), ("cilbir", "🍳"), ("sahanda", "🍳"),
        ("durum", "🌯"), ("wrap", "🌯"), ("tantuni", "🌯"), ("doner", "🥙"), ("iskender", "🥙"), ("kebap", "🍢"), ("kebab", "🍢"),
        ("adana", "🍢"), ("urfa", "🍢"), ("sis", "🍢"), ("kofte", "🧆"), ("falafel", "🧆"), ("kokorec", "🥖"), ("balik ekmek", "🥪"),
        ("hamburger", "🍔"), ("burger", "🍔"), ("pizza", "🍕"), ("sandvic", "🥪"), ("tost", "🥪"), ("hot dog", "🌭"), ("sosis", "🌭"),
        ("patates kizartma", "🍟"), ("cips", "🍟"), ("nugget", "🍗"),
        ("tavuk", "🍗"), ("hindi", "🍗"), ("kanat", "🍗"), ("baget", "🍗"),
        ("bonfile", "🥩"), ("antrikot", "🥩"), ("biftek", "🥩"), ("pirzola", "🥩"), ("kuzu", "🥩"), ("dana", "🥩"), ("et ", "🥩"), ("kiyma", "🥩"),
        ("kavurma", "🥩"), ("tandir", "🥩"), ("sucuk", "🥓"), ("pastirma", "🥓"), ("salam", "🥓"), ("jambon", "🥓"), ("bacon", "🥓"),
        ("karides", "🦐"), ("kalamar", "🦑"), ("ahtapot", "🐙"), ("midye", "🦪"), ("sushi", "🍣"), ("somon", "🐟"), ("ton", "🐟"), ("levrek", "🐟"),
        ("cipura", "🐟"), ("hamsi", "🐟"), ("palamut", "🐟"), ("mezgit", "🐟"), ("istavrit", "🐟"), ("sardalya", "🐟"), ("balik", "🐟"),
        ("corba", "🍲"), ("guvec", "🍲"), ("turlu", "🍲"), ("yahni", "🍲"), ("kuru fasulye", "🫘"), ("barbunya", "🫘"), ("nohut", "🫘"),
        ("mercimek", "🫘"), ("fasulye", "🫘"), ("borulce", "🫘"), ("bezelye", "🫛"), ("edamame", "🫛"), ("humus", "🫘"),
        ("manti", "🥟"), ("borek", "🥐"), ("pogaca", "🥐"), ("kruvasan", "🥐"), ("acma", "🥐"), ("gozleme", "🫓"), ("pide", "🫓"),
        ("lahmacun", "🫓"), ("lavas", "🫓"), ("yufka", "🫓"), ("bazlama", "🫓"), ("tortilla", "🫓"), ("pisi", "🫓"), ("simit", "🥯"),
        ("makarna", "🍝"), ("spagetti", "🍝"), ("eriste", "🍝"), ("lazanya", "🍝"), ("noodle", "🍜"), ("ramen", "🍜"),
        ("pilav", "🍚"), ("pirinc", "🍚"), ("bulgur", "🍚"), ("kinoa", "🍚"), ("kuskus", "🍚"), ("risotto", "🍚"),
        ("ekmek", "🍞"), ("ekmeg", "🍞"), ("corbas", "🍲"), ("yogurd", "🥛"), ("kofteb", "🧆"), ("galeta", "🍞"), ("kraker", "🍘"), ("pirinc patlagi", "🍘"),
        ("yulaf", "🥣"), ("granola", "🥣"), ("musli", "🥣"), ("misir gevregi", "🥣"),
        ("sutlac", "🍮"), ("kazandibi", "🍮"), ("muhallebi", "🍮"), ("puding", "🍮"), ("tavuk gogsu tatlisi", "🍮"),
        ("baklava", "🍯"), ("kunefe", "🍯"), ("kadayif", "🍯"), ("sekerpare", "🍯"), ("lokma", "🍩"), ("tulumba", "🍩"), ("donut", "🍩"),
        ("dondurma", "🍨"), ("pasta", "🍰"), ("cheesecake", "🍰"), ("tiramisu", "🍰"), ("kek", "🍰"), ("revani", "🍰"), ("magnolia", "🍰"),
        ("kurabiye", "🍪"), ("biskuvi", "🍪"), ("gofret", "🍫"), ("cikolata", "🍫"), ("lokum", "🍬"), ("seker", "🍬"), ("helva", "🍯"),
        ("waffle", "🧇"), ("krep", "🥞"), ("pankek", "🥞"), ("patlamis misir", "🍿"),
        ("peynir", "🧀"), ("kasar", "🧀"), ("lor", "🧀"), ("labne", "🧀"), ("hellim", "🧀"), ("mozzarella", "🧀"), ("cokelek", "🧀"),
        ("yogurt", "🥛"), ("ayran", "🥛"), ("kefir", "🥛"), ("sut", "🥛"), ("cacik", "🥣"), ("haydari", "🥣"), ("quark", "🥛"),
        ("tereyag", "🧈"), ("kaymak", "🧈"), ("krema", "🧈"), ("zeytinyag", "🫒"), ("zeytin", "🫒"), ("yag", "🫒"),
        ("bal", "🍯"), ("recel", "🍯"), ("pekmez", "🍯"), ("tahin", "🥜"), ("fistik ezmesi", "🥜"), ("findik kremasi", "🍫"),
        ("badem", "🌰"), ("ceviz", "🌰"), ("findik", "🌰"), ("kaju", "🌰"), ("antep", "🥜"), ("fistik", "🥜"), ("leblebi", "🥜"),
        ("cekirdek", "🌻"), ("kuruyemis", "🥜"), ("chia", "🌱"), ("keten", "🌱"), ("kestane", "🌰"),
        ("muz", "🍌"), ("elma", "🍎"), ("armut", "🍐"), ("portakal", "🍊"), ("mandalina", "🍊"), ("greyfurt", "🍊"), ("limon", "🍋"),
        ("cilek", "🍓"), ("kiraz", "🍒"), ("visne", "🍒"), ("uzum", "🍇"), ("karpuz", "🍉"), ("kavun", "🍈"), ("ananas", "🍍"), ("mango", "🥭"),
        ("seftali", "🍑"), ("kayisi", "🍑"), ("erik", "🍑"), ("kivi", "🥝"), ("nar", "🍎"), ("incir", "🍇"), ("hurma", "🌴"), ("yaban mersini", "🫐"),
        ("bogurtlen", "🫐"), ("ahududu", "🍓"), ("avokado", "🥑"), ("hindistan cevizi", "🥥"),
        ("domates", "🍅"), ("salatalik", "🥒"), ("tursu", "🥒"), ("biber", "🫑"), ("patlican", "🍆"), ("havuc", "🥕"), ("misir", "🌽"),
        ("brokoli", "🥦"), ("karnabahar", "🥦"), ("ispanak", "🥬"), ("marul", "🥬"), ("lahana", "🥬"), ("roka", "🥬"), ("pazi", "🥬"),
        ("mantar", "🍄"), ("sogan", "🧅"), ("sarimsak", "🧄"), ("patates", "🥔"), ("tatli patates", "🍠"), ("kabak", "🥒"), ("salata", "🥗"),
        ("dolma", "🫑"), ("sarma", "🍃"), ("imam bayildi", "🍆"), ("karniyarik", "🍆"), ("musakka", "🍆"), ("sebze", "🥗"),
        ("ketcap", "🥫"), ("mayonez", "🥫"), ("hardal", "🥫"), ("sos", "🥫"), ("salca", "🥫"),
        ("turk kahvesi", "☕"), ("kahve", "☕"), ("latte", "☕"), ("cappuccino", "☕"), ("americano", "☕"), ("espresso", "☕"), ("mocha", "☕"),
        ("salep", "☕"), ("cay", "🍵"), ("bira", "🍺"), ("sarap", "🍷"), ("raki", "🥃"), ("viski", "🥃"), ("votka", "🥃"), ("kokteyl", "🍸"),
        ("kola", "🥤"), ("gazoz", "🥤"), ("enerji", "🥤"), ("limonata", "🍋"), ("meyve suyu", "🧃"), ("smoothie", "🥤"), ("boza", "🥛"),
        ("salgam", "🥤"), ("maden suyu", "💧"), ("su", "💧"),
    ]
    static func of(_ name: String) -> String? {
        let n = " " + TextNorm.norm(name) + " "
        // short keys must match whole words ("kekik" isn't "kek", "balkabağı" isn't "bal")
        for (k, e) in rules where k.count <= 4 ? n.contains(" " + k + " ") : n.contains(" " + k) { return e }
        return nil
    }
}
