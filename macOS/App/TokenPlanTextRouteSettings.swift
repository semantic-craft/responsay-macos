import Foundation

enum TokenPlanTextRouteSettings {
    static let plusRoute = "plus"
    static let flashRoute = "flash"
    static let plusModelKey = "QWEN_TOKEN_PLAN_PLUS_MODEL"
    static let flashModelKey = "QWEN_TOKEN_PLAN_FLASH_MODEL"
    static let defaultPlusModel = "qwen3.6-plus"
    static let defaultFlashModel = "qwen3.6-flash"

    static func model(for route: String) -> String {
        let key = route == flashRoute ? flashModelKey : plusModelKey
        let fallback = route == flashRoute ? defaultFlashModel : defaultPlusModel
        guard let raw = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return fallback
        }
        return raw
    }
}
