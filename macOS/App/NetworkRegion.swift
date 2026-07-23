import Foundation

/// 280 — one first-run choice (国内 / 海外) that drives the sherpa mirror preference
/// (`localMirror`, consumed by `LocalModelDownloader.orderedURLs`) for built-in model downloads.
///
/// `current` never writes: users who finished onboarding before this existed
/// keep their manual `localMirror` choice until they actively pick a region
/// (设置 → 存储, or re-running onboarding).
enum NetworkRegion: String, CaseIterable, Identifiable, Sendable {
    case cn, intl

    static let defaultsKey = "networkRegion"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cn:   "国内网络"
        case .intl: "海外网络"
        }
    }

    var detail: String {
        switch self {
        case .cn:   "内置模型从镜像源优先下载。"
        case .intl: "内置模型走 GitHub / 官方源。"
        }
    }

    /// The persisted choice; unset falls back to a system-locale guess.
    static var current: NetworkRegion {
        stored(in: .standard) ?? localeDefault()
    }

    static func stored(in defaults: UserDefaults) -> NetworkRegion? {
        defaults.string(forKey: defaultsKey).flatMap(NetworkRegion.init(rawValue:))
    }

    /// CN-region system locale preselects 国内; everything else 海外.
    static func localeDefault(_ locale: Locale = .current) -> NetworkRegion {
        locale.region?.identifier == "CN" ? .cn : .intl
    }

    /// One write drives both chains: persists the region and syncs the sherpa
    /// mirror it umbrellas. The 设置 → 存储「下载镜像」picker stays available as
    /// a manual override on top (region→mirror is one-way; flipping the mirror
    /// by hand never rewrites the region).
    static func select(_ region: NetworkRegion, defaults: UserDefaults = .standard) {
        defaults.set(region.rawValue, forKey: defaultsKey)
        defaults.set(region == .cn ? "cnproxy" : "hf", forKey: "localMirror")
    }
}
