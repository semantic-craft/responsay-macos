import Foundation

// MARK: - Verification source display names
//
// One place names each source for the selection-verify menu and the legal-skill
// output card. Kept apart from the routing so renames never touch URL logic.

public extension VerificationSourcePreference {
    /// Human label shown in the 来源核验 source menu.
    var displayName: String {
        switch self {
        case .govLaw:       return "国家法规库"
        case .pkulaw:       return "北大法宝"
        case .cnki:         return "知网"
        case .vip:          return "维普"
        case .wanfang:      return "万方"
        case .baiduScholar: return "百度学术"
        case .itslaw:       return "无讼"
        case .wenshu:       return "裁判文书网"
        case .rmfyalk:      return "人民法院案例库"
        case .bing:         return "必应"
        case .webSearch:    return "百度"
        case .qwenSearch:   return "AI 联网搜索"
        case .manual:       return "复制检索词"
        }
    }
}
