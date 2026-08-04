import Foundation
import AppKit
import ResponsayCore

@MainActor
public enum DiagnosticExporter {
    
    /// Collects system diagnostics and copies them to the clipboard as formatted JSON.
    public static func exportAndCopyToClipboard() {
        let payload = collectDiagnostics()
        
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let string = String(data: data, encoding: .utf8) {
            
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        }
    }
    
    static func collectDiagnostics(
        dispatcher: ProviderConfigDispatcher = ProviderConfigDispatcher()
    ) -> [String: Any] {
        var payload: [String: Any] = [:]
        
        // 1. System Info
        let processInfo = ProcessInfo.processInfo
        payload["system_os_version"] = processInfo.operatingSystemVersionString
        payload["system_arch"] = getSystemArch()
        
        // 2. App Info
        if let info = Bundle.main.infoDictionary {
            payload["app_version"] = info["CFBundleShortVersionString"] as? String ?? "Unknown"
            payload["app_build"] = info["CFBundleVersion"] as? String ?? "Unknown"
        }
        
        // 3. App-direct provider configuration. The old backend-era keys
        // (`SpeechEngine` / `ttsProvider` / `coachProvider`) are no longer
        // authoritative after ADR-0029.
        let defaults = UserDefaults.standard
        let asrEngine = ASREngine.selected
        if let providerId = asrEngine.associatedProviderId {
            payload["config_asr_active"] = providerConfigPayload(
                dispatcher.resolve(.asr, providerId: providerId),
                extra: ["engine": asrEngine.rawValue, "title": asrEngine.title, "providerMode": "cloud"])
        } else {
            payload["config_asr_active"] = localASRPayload(asrEngine)
            let savedCloud = dispatcher.resolve(.asr)
            if savedCloud.providerId != "apple" {
                payload["config_asr_saved_cloud"] = providerConfigPayload(savedCloud)
            }
        }
        payload["config_tts_active"] = providerConfigPayload(
            dispatcher.resolve(.tts),
            extra: ["engine": TTSEngine.selected.rawValue, "title": TTSEngine.selected.title])
        payload["config_coach_active"] = providerConfigPayload(dispatcher.resolve(.llm))
        
        // Extra boolean flags for agent debugging
        let settingsDict: [String: Any] = [
            "accessibility_trusted": AXIsProcessTrusted(),
            "capsule_position": defaults.string(forKey: "capsulePosition") ?? "cursor",
            "shortcut_scheme": defaults.string(forKey: "shortcutScheme") ?? "fn",
            "restore_clipboard": defaults.bool(forKey: "restoreClipboard"),
            "light_rewrite": DictationRewriteSettings.lightRewriteEnabled(defaults),
            "debug_log": defaults.bool(forKey: "debugLog")
        ]
        payload["app_settings"] = settingsDict
        
        // 4. Backend health: the Node backend is retired (ADR-0029, issue 353);
        // the app is app-direct/BYOK, so there is no backend to probe.
        payload["backend_health"] = "Retired / App-Direct"
        
        // 5. Recent ASR/TTS Events (bumped to 50 for agent bug fixing)
        let recentEvents = DiagnosticsCenter.shared.events.suffix(50).map { event -> [String: Any] in
            return [
                "timestamp": ISO8601DateFormatter().string(from: event.timestamp),
                "category": event.category.rawValue,
                "level": event.level.rawValue,
                "title": event.title,
                "fields": event.fields,
                "error": event.errorMessage ?? ""
            ]
        }
        payload["recent_events"] = recentEvents
        
        return payload
    }

    private static func providerConfigPayload(
        _ config: ResolvedProviderConfig,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "provider": config.providerId,
            "region": config.region.rawValue,
            "plan": config.plan.rawValue,
            "baseURL": config.baseURL,
            "model": config.model,
            "hasKey": config.hasKey
        ]
        for (key, value) in extra { payload[key] = value }
        return payload
    }

    private static func localASRPayload(_ engine: ASREngine) -> [String: Any] {
        [
            "engine": engine.rawValue,
            "title": engine.title,
            "providerMode": "local",
            "provider": "local",
            "hasKey": false
        ]
    }
    
    private static func getSystemArch() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
        return String(bytes: data, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "Unknown"
    }
}
