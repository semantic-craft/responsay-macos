import Foundation
import ResponsayCore

/// Resolves the user's OCR engine choice (`OCREngine.selected`) into a concrete `OCRProvider`,
/// reading BYOK keys from the Keychain. The OCR analogue of `RoutedSpeechCaptureService`:
/// `CaptureSnapOCRController` builds a fresh `SnapOCRRunner(provider:)` from `resolve()` on each snap,
/// so the choice is honored live without restarting.
///
/// A cloud engine whose key isn't configured yet falls back to Apple Vision so Snap & Translate
/// keeps working on-device (anamra does the same — "未填则取字回落本地"); the Settings pane shows a
/// hint when that will happen. `keyReader` is injected so the resolution table is unit-testable
/// without touching the real Keychain.
struct RoutedOCRProvider {
    private let engine: OCREngine
    private let keyReader: (String) -> String?
    private let paddleModelInstalled: () -> Bool
    private let paddleProviderFactory: @MainActor () throws -> any OCRProvider

    init(
        engine: OCREngine = .selected,
        keyReader: @escaping (String) -> String? = BYOKKeychain.read,
        paddleModelInstalled: @escaping () -> Bool = { LocalModelRegistry.defaultOCR.isInstalled },
        paddleProviderFactory: @escaping @MainActor () throws -> any OCRProvider = {
            ResidentPaddleOCRProvider()
        }
    ) {
        self.engine = engine
        self.keyReader = keyReader
        self.paddleModelInstalled = paddleModelInstalled
        self.paddleProviderFactory = paddleProviderFactory
    }

    @MainActor
    func resolve() -> any OCRProvider {
        switch engine {
        case .appleVision:
            return AppleVisionOCRProvider()
        case .paddleOCRLocal:
            guard paddleModelInstalled() else { return AppleVisionOCRProvider() }
            do {
                return try paddleProviderFactory()
            } catch {
                return AppleVisionOCRProvider()
            }

        case .mistral:
            let key = trimmedKey(OCRCredentialAccount.mistralAPIKey)
            guard let key else { return AppleVisionOCRProvider() }
            return MistralOCRProvider(apiKeyProvider: { key })

        case .baidu:
            guard let apiKey = trimmedKey(OCRCredentialAccount.baiduAPIKey),
                  let secret = trimmedKey(OCRCredentialAccount.baiduSecretKey) else {
                return AppleVisionOCRProvider()
            }
            return BaiduOCRProvider(credentialsProvider: { (apiKey, secret) })
        }
    }

    /// True when `resolve()` will return a real *cloud* provider (a cloud engine with its key(s)
    /// configured) — i.e. the recognize is a network round-trip. Drives whether Snap & Translate
    /// shows the "识别中…" spinner; the instant on-device path skips it.
    var resolvesToCloud: Bool {
        switch engine {
        case .mistral, .baidu:
            return !willFallBackToLocal
        case .appleVision, .paddleOCRLocal:
            return false
        }
    }

    var showsRecognitionProgress: Bool {
        resolvesToCloud || (engine == .paddleOCRLocal && paddleModelInstalled())
    }

    /// True when the selected cloud engine is missing a credential and will silently fall back to
    /// Apple Vision — drives the Settings pane's hint.
    var willFallBackToLocal: Bool {
        switch engine {
        case .appleVision:
            return false
        case .paddleOCRLocal:
            return !paddleModelInstalled()
        case .mistral:
            return trimmedKey(OCRCredentialAccount.mistralAPIKey) == nil
        case .baidu:
            return trimmedKey(OCRCredentialAccount.baiduAPIKey) == nil
                || trimmedKey(OCRCredentialAccount.baiduSecretKey) == nil
        }
    }

    private func trimmedKey(_ account: String) -> String? {
        guard let value = keyReader(account)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
