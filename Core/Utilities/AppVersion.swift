import Foundation

/// Marketing and build versions from the app bundle (M10 release readiness).
enum AppVersion {
    /// `CFBundleShortVersionString`, for example `0.1.0`.
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// `CFBundleVersion` build number.
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var displayString: String {
        "\(marketing) (\(build))"
    }
}
