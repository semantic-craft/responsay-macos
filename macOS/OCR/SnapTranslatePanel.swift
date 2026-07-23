import AppKit
import SwiftUI
import ResponsayCore

/// 截图翻译 结果面板的窗口宿主，与 `SnapOCRPanel`（截图取字）平行：一个可成 key 的浮动窗口
/// （可读译文 / 可选区复制 / Esc 关闭），内容是 `SnapTranslatePanelView`。
///
/// `show` 在这里组装译文服务列表 + 翻译闭包（读钥匙串、建端点、发网络都在这一层的显式动作里，
/// 不在 SwiftUI `body`）。
@MainActor
final class SnapTranslatePanel {

    static let shared = SnapTranslatePanel()

    private var window: NSWindow?

    private init() {}

    /// `image` 是被截区域，用于「看原图」；识别成功路径下总有图，`nil` 仅作极少数兜底。
    func show(result: OCRResult, image: CGImage?) {
        let nsImage = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        let services = SnapTranslateServiceCatalog.services()
        let initial = SnapTranslateServiceCatalog.defaultServiceId() ?? services.first?.id ?? ""

        let view = SnapTranslatePanelView(
            original: result,
            sourceImage: nsImage,
            services: services,
            initialServiceId: initial,
            resolveTarget: { SnapTranslateTargetSettings.resolve(for: $0) },
            translate: Self.makeTranslate(),
            onClose: { [weak self] in self?.window?.close() })

        let window = self.window ?? makeWindow()
        let hostingView = NSHostingView(rootView: view)
        // #569: the window is the size authority (fixed 480×600) — don't let the hosting
        // view rewrite its min/max or resize it toward content.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 用所选服务翻译。端点解析（读钥匙串）+ 网络都在闭包内部 —— 这是显式动作，不在渲染路径。
    /// 思考一律关（截图翻译是结构化翻译，开思考只会更慢，对齐 435/`LLMEndpointResolver.resolveText`）。
    private static func makeTranslate() -> @MainActor (String, String, TranslationTargetLanguage) async -> Result<String, SnapTranslateError> {
        { text, serviceId, target in
            let cfg = ProviderConfigDispatcher().resolve(.llm, providerId: serviceId)
            guard cfg.hasKey else { return .failure(SnapTranslateError(message: "该服务还没配置密钥，请在设置里填好它的 Key。")) }
            let endpoint = LLMEndpoint(
                providerId: cfg.providerId, baseURL: cfg.baseURL, model: cfg.model,
                apiKey: cfg.apiKey, thinkingEnabled: false)
            guard endpoint.isConfigured else { return .failure(SnapTranslateError(message: "该服务的连接配置不完整。")) }
            do {
                let result = try await DirectTextTranslationAPI(endpoint: endpoint)
                    .translate(text, target: target, style: .literal, context: nil)
                let out = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return out.isEmpty
                    ? .failure(SnapTranslateError(message: "没有返回译文，换个服务再试。"))
                    : .success(out)
            } catch {
                return .failure(SnapTranslateError(message: error.localizedDescription))
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = .floating              // 停留在你刚截图的窗口之上，方便去别处粘贴译文
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(SettingsTheme.card)
        return window
    }
}
