import SwiftUI
import ResponsayCore
import OSLog
import AppKit
import AVFoundation

/// Native macOS settings: a sidebar of grouped settings panes, modeless with
/// immediate `@AppStorage` apply. The controller reads the same keys at capture time.
struct SettingsView: View {
    @AppStorage("defaultLocale") private var localeRaw = CaptureLocale.english.rawValue
    @AppStorage(ASREngine.defaultsKey) private var asrEngineRaw = ASREngine.apple.rawValue
    @AppStorage(OCREngine.defaultsKey) private var ocrEngineRaw = OCREngine.appleVision.rawValue
    @AppStorage(RealtimeQwenSettings.regionKey) private var realtimeRegionRaw = QwenRealtimeRegion.china.rawValue
    @AppStorage("startSound") private var startSound = true
    @AppStorage(InteractionSoundStyle.key) private var interactionSoundStyle = InteractionSoundStyle.pianoUpright.rawValue
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var audioInputDevices: [(id: String, name: String)] = []
    @State private var shortcutSettingsStore = ShortcutSettingsStore.shared
    @State private var modelManagerSummary = "未检查"
    @State private var modelManagers: [LocalModelDownloadManager] = []
    @State private var residency = LocalEngineResidency.shared
    @State private var residencyError: String?
    @State private var storageMigrationStatus: String?
    @State private var showEngineCompare = false
    @State private var selection: SettingsSection? = .general

    @Environment(AppearanceStore.self) private var appearanceStore
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("capsulePosition") private var capsulePosition = "cursor"
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("shortcutScheme") private var shortcutScheme = "fn"
    // Same resolution as SettingsModelsPane: when no engine has been picked, fall to whatever
    // TTSEngine.selected resolves (a configured cloud voice, else Kokoro) rather than hardcoding
    // Kokoro — the two panes must not disagree about the current 朗读 engine.
    @AppStorage(TTSEngine.defaultsKey) private var ttsEngineRaw = TTSEngine.selected.rawValue
    @AppStorage("practiceSpeed") private var practiceSpeed = "0.9"
    @AppStorage("keepHistory") private var keepHistory = true
    @AppStorage("historyCleanup") private var historyCleanup = "30"
    @AppStorage("debugLog") private var debugLog = false
    @AppStorage("ttsProvider") private var ttsProvider = "qwen-tts"
    @AppStorage("micDeviceID") private var micDeviceID = ""
    @AppStorage("avoidBluetoothMic") private var avoidBluetoothMic = true
    @AppStorage("showCapsule") private var showCapsule = true
    @AppStorage("muteWhileRecording") private var muteWhileRecording = true
    @AppStorage("restoreClipboard") private var restoreClipboard = true
    @AppStorage("copyToClipboard") private var copyToClipboard = false
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @AppStorage("startMinimized") private var startMinimized = false
    private let updateService = AutoUpdateService.shared
    @AppStorage("keepRawRecording") private var keepRawRecording = false
    @AppStorage("maxRawRecordings") private var maxRawRecordings = 200
    @AppStorage("localMirror") private var localMirror = "hf"
    @AppStorage(NetworkRegion.defaultsKey) private var networkRegionRaw = ""
    @AppStorage("localEngineTTL") private var localEngineTTL = "5"

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            detailPane
                .background(appearanceStore.palette.bg)
        }
        .tint(appearanceStore.palette.accent)
        .frame(minWidth: 900, idealWidth: 1040, maxWidth: .infinity,
               minHeight: 600, idealHeight: 720, maxHeight: .infinity)
        .onAppear {
            loadMics()
            Task { await refreshModelManagerStatus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenSettingsSection"))) { note in
            if let raw = note.object as? String, let section = SettingsSection(rawValue: raw) {
                selection = section
            }
        }
    }

    @ViewBuilder private var detailPane: some View {
        switch selection ?? .general {
        case .general:
            SettingsGeneralPane(
                micDeviceID: $micDeviceID,
                avoidBluetoothMic: $avoidBluetoothMic,
                showCapsule: $showCapsule,
                muteWhileRecording: $muteWhileRecording,
                startSound: $startSound,
                interactionSoundStyle: $interactionSoundStyle,
                restoreClipboard: $restoreClipboard,
                copyToClipboard: $copyToClipboard,
                launchAtLogin: $launchAtLogin,
                startMinimized: $startMinimized,
                audioInputDevices: audioInputDevices,
                updateLaunchAtLogin: updateLaunchAtLogin,
                previewCaptureCues: previewCaptureCues)
        case .hotkeys:
            SettingsShortcutPane(shortcutScheme: $shortcutScheme, shortcutSettingsStore: shortcutSettingsStore)
        case .rewrite:
            SettingsRewritePane(openSection: { selection = $0 })
        case .models:
            SettingsModelsPane(openSection: { selection = $0 })
        case .asr:
            SettingsASRPane(
                asrEngineRaw: $asrEngineRaw,
                localeRaw: $localeRaw,
                showEngineCompare: $showEngineCompare,
                modelManagers: modelManagers,
                residency: residency,
                residencyError: $residencyError,
                openDictionary: { selection = .dictionary },
                ensureModelManagers: ensureModelManagers,
                refreshModelManagerStatus: refreshModelManagerStatus)
        case .llm:
            SettingsLLMPane(llmEngineSelection: llmEngineSelection)
        case .tts:
            SettingsTTSPane(
                ttsEngineRaw: $ttsEngineRaw,
                practiceSpeed: $practiceSpeed,
                modelManagers: modelManagers,
                residency: residency,
                residencyError: $residencyError,
                ensureModelManagers: ensureModelManagers)
        case .ocr:
            SettingsOCRPane(
                ocrEngineRaw: $ocrEngineRaw,
                modelManagers: modelManagers,
                residency: residency,
                residencyError: $residencyError,
                ensureModelManagers: ensureModelManagers,
                refreshModelManagerStatus: refreshModelManagerStatus)
        case .selectionMenu:
            SettingsSelectionMenuPane(openSkillsLibrary: { selection = .legalSkills })
        case .dictionary:
            DictionarySettingsPane()
        case .legalSkills:
            LegalSkillsScreen()
        case .legalConfig:
            SettingsLegalConfigPane()
        case .verify:
            SourceVerificationPane()
        case .appearance:
            AppearanceScreen(interfaceLanguage: $interfaceLanguage)
                .background(appearanceStore.palette.bg)
                .navigationTitle("外观主题")
        case .privacy:
            SettingsPrivacyPane()
        case .data:
            SettingsDataPane(keepHistory: $keepHistory, historyCleanup: $historyCleanup)
        case .storage:
            SettingsStoragePane(
                networkRegionRaw: $networkRegionRaw,
                localMirror: $localMirror,
                localEngineTTL: $localEngineTTL,
                modelManagerSummary: modelManagerSummary,
                modelManagers: $modelManagers,
                residency: residency,
                residencyError: $residencyError,
                storageMigrationStatus: $storageMigrationStatus,
                ensureModelManagers: ensureModelManagers,
                refreshModelManagerStatus: refreshModelManagerStatus)
        case .diagnostics:
            SettingsDiagnosticsPane(
                debugLog: $debugLog,
                keepRawRecording: $keepRawRecording,
                maxRawRecordings: $maxRawRecordings,
                exportErrorLog: exportErrorLog,
                exportDiagnostics: exportDiagnostics)
        case .about:
            SettingsAboutPane(updateService: updateService)
        }
    }

    private var llmEngineSelection: Binding<String> {
        Binding(
            get: {
                let providers = ProviderCatalog.presets(for: .llm)
                if let stored = UserDefaults.standard.string(forKey: "byok.llm.provider"),
                   providers.contains(where: { $0.id == stored }) {
                    return stored
                }
                return providers.first?.id ?? "custom"
            },
            set: { newValue in
                ModelRouteSelectionActions.applyLLMSelection(newValue)
            }
        )
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
        } catch {
            Logger(subsystem: AppBrand.loggerSubsystem, category: "settings")
                .error("Login item toggle failed: \(error.localizedDescription, privacy: .public)")
            launchAtLogin = !enabled
        }
    }

    private func loadMics() {
        Task.detached {
            let devices = AVCaptureDevice.devices(for: .audio).map { ($0.uniqueID, $0.localizedName) }
            await MainActor.run { self.audioInputDevices = devices }
        }
    }

    private func previewCaptureCues() {
        InteractionSoundPlayer.shared.playCaptureStart()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            InteractionSoundPlayer.shared.playCaptureStop()
        }
    }

    private func exportErrorLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "responsay-errorlog.txt"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            let body = "Responsay error log — route / error codes only (no transcript).\n"
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func exportDiagnostics() {
        DiagnosticExporter.exportAndCopyToClipboard()
        let alert = NSAlert()
        alert.messageText = String(localized: "已复制诊断信息")
        alert.informativeText = String(localized: "诊断信息已经复制到剪贴板，包含了系统版本、应用版本、当前配置和引擎近期的状态记录。")
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func ensureModelManagers() {
        if modelManagers.isEmpty {
            modelManagers = LocalModelRegistry.downloadable.map { LocalModelDownloadManager(spec: $0) }
        }
        modelManagers.forEach { $0.refresh() }
    }


    private func refreshModelManagerStatus() async {
        let specs = LocalModelRegistry.downloadable
        let ready = specs.filter { $0.isInstalled }.count
        modelManagerSummary = "模型 \(ready)/\(specs.count) 已就绪"
        modelManagers.forEach { $0.refresh() }
    }
}
