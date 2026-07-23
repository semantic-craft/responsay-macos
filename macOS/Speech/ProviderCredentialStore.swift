import Foundation
import Security

/// Reads / writes per-provider API keys in the user's Keychain (BYOK — ADR-0023).
/// Extracted from the retired `RealtimeQwenSpeechCaptureService` (issue 289):
/// the app-init BYOK header layer (`ResponsayMacApp`) still reads these legacy
/// slots, so the store outlives the engine that introduced it. Keys are never
/// stored in `UserDefaults`, never logged, and entry is masked with `SecureField`.
enum ProviderCredentialStore {
    struct Slot: Sendable {
        let service: String
        let account: String

        /// DashScope / 通义千问 key.
        static let dashscope = Slot(
            service: "com.semanticcraft.responsay.dashscope",
            account: "QWEN_DASHSCOPE_KEY")
        static let mimo = Slot(
            service: "com.semanticcraft.responsay.mimo",
            account: "MIMO_API_KEY")
        static let gemini = Slot(
            service: "com.semanticcraft.responsay.gemini",
            account: "GEMINI_API_KEY")
        static let openai = Slot(
            service: "com.semanticcraft.responsay.openai",
            account: "OPENAI_API_KEY")
        static let customOpenAI = Slot(
            service: "com.semanticcraft.responsay.custom",
            account: "CUSTOM_OPENAI_KEY")
        static let deepseek = Slot(
            service: "com.semanticcraft.responsay.deepseek",
            account: "DEEPSEEK_API_KEY")
        static let minimax = Slot(
            service: "com.semanticcraft.responsay.minimax",
            account: "MINIMAX_API_KEY")
        static let volcengine = Slot(
            service: "com.semanticcraft.responsay.volcengine",
            account: "VOLCENGINE_API_KEY")
    }

    static func read(_ slot: Slot) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: slot.service,
            kSecAttrAccount as String: slot.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Store the key, or clear it when `value` trims to empty. Never logged.
    static func write(_ value: String, to slot: Slot) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: slot.service,
            kSecAttrAccount as String: slot.account,
        ]
        guard !trimmed.isEmpty else {
            _ = SecItemDelete(base as CFDictionary)
            return
        }
        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            _ = SecItemAdd(add as CFDictionary, nil)
        }
    }
}
