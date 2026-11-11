import Foundation

/// App identifiers and the optional backend in one place.
/// In the open-source build values come from `Config/Secrets.xcconfig` → Info.plist; when empty, backend features
/// (FatSecret search, Team) stay off and the rest of the app works offline.
public enum AppConfig {
    /// Bundle id root; the App Group and iCloud container derive from it
    public static let bundleBase: String = {
        let v = Bundle.main.object(forInfoDictionaryKey: "GPBundleBase") as? String
        return (v?.isEmpty == false && v?.hasPrefix("$(") == false) ? v! : "com.example.gympaper"
    }()
    public static let appGroup = "group.\(bundleBase)"
    public static let iCloudContainer = "iCloud.\(bundleBase)"

    public struct Backend: Sendable {
        public let url: URL
        public let anonKey: String
    }

    /// Supabase (FatSecret proxy + Team). GPSupabaseHost / GPSupabaseAnonKey in Info.plist take precedence.
    public static let backend: Backend? = {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ k: String) -> String? {
            guard let v = info[k] as? String, !v.isEmpty, !v.hasPrefix("$(") else { return nil }
            return v
        }
        guard let host = value("GPSupabaseHost") ?? fallbackHost, let key = value("GPSupabaseAnonKey") ?? fallbackAnonKey,
              let url = URL(string: "https://\(host)") else { return nil }
        return Backend(url: url, anonKey: key)
    }()

    // public (anon) values; access is limited by server rules (RLS, RPC only)
    private static let fallbackHost: String? = nil
    private static let fallbackAnonKey: String? = nil
}
