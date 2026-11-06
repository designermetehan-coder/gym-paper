import SwiftUI
import SwiftData
import BalliKit

/// Besinlerim'e eklenen fotoğraflar: ada göre bellekte tutulur, liste küçük resimlerinde kullanılır
@MainActor @Observable
final class FoodImages {
    static let shared = FoodImages()
    var version = 0
    nonisolated(unsafe) private static var store: [String: UIImage] = [:]
    nonisolated private static let lock = NSLock()   // Swift 6: ana aktöre bağlı değil (CR-24)

    nonisolated static func get(_ name: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return store[TextNorm.norm(name)]
    }
    nonisolated static func put(_ name: String, _ img: UIImage?, bump: Bool = true) {
        lock.lock(); store[TextNorm.norm(name)] = img; lock.unlock()
        if bump { Task { @MainActor in FoodImages.shared.version += 1 } }
    }

    /// Yalnız yeni ya da değişen fotoğraflar çözülür; görünümler bir kez yenilenir (CR-41)
    @ObservationIgnored private var loadedSig: [String: Int] = [:]
    func load(_ ctx: ModelContext) {
        let all = (try? ctx.fetch(FetchDescriptor<SavedFood>())) ?? []
        var raw: [(String, Data)] = []
        for f in all {
            let key = TextNorm.norm(f.name)
            guard let d = f.imageData else { continue }
            if loadedSig[key] != d.count { loadedSig[key] = d.count; raw.append((f.name, d)) }
        }
        guard !raw.isEmpty else { return }
        Task.detached(priority: .utility) {
            for (n, d) in raw { FoodImages.put(n, UIImage(data: d), bump: false) }
            await MainActor.run { FoodImages.shared.version += 1 }
        }
    }

    /// Fotoğrafı küçültüp besine yazar
    func set(_ food: SavedFood, image: UIImage?) {
        let small = image.flatMap { UserMotion.shrink($0, max: 600) }
        food.imageData = small?.jpegData(compressionQuality: 0.75)
        Self.put(food.name, small)
    }
}
