import Foundation

/// Reads user-picked files with a size limit so a huge or wrong file doesn't fill memory
public enum SafeRead {
    public struct TooLarge: LocalizedError {
        public let limitMB: Int
        public var errorDescription: String? { String(localized: "Dosya çok büyük (en fazla \(limitMB) MB).") }
    }
    /// Backup file limit: years of data are a few MB; 50 MB is plenty
    public static let backupLimit = 50 * 1024 * 1024
    /// Food/recipe share file limit
    public static let shareLimit = 5 * 1024 * 1024

    public static func data(_ url: URL, limit: Int) throws -> Data {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= limit else { throw TooLarge(limitMB: limit / 1_048_576) }
        let d = try Data(contentsOf: url, options: .mappedIfSafe)
        guard d.count <= limit else { throw TooLarge(limitMB: limit / 1_048_576) }
        return d
    }
}
