import SwiftUI
import AppKit
import ResponsayCore

struct MacControlPanelView: View {
    let controller: CaptureController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppBrand.displayName)
                        .font(.title3.weight(.semibold))
                    Text("语音输入 · 英文表达")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(spacing: 10) {
                Button {
                    controller.triggerRaw()
                } label: {
                    Label("语音输入 / 停止", systemImage: "mic")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("y", modifiers: [.control, .option, .command])

                Button {
                    controller.triggerPolished()
                } label: {
                    Label("改写原话 / 停止", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("y", modifiers: [.control, .option, .command, .shift])

                Button {
                    controller.triggerExpressInEnglish()
                } label: {
                    Label("英文表达 / 停止", systemImage: "text.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("e", modifiers: [.control, .option, .command])

                Button {
                    controller.triggerRewrite()
                } label: {
                    Label("表达教练 / 停止", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("i", modifiers: [.control, .option, .command])

                Button {
                    controller.rewriteSelection()
                } label: {
                    Label("改写选中文本", systemImage: "text.cursor")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("r", modifiers: .option)

                Button {
                    controller.translateSelection()
                } label: {
                    Label("翻译选中文本", systemImage: "translate")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("t", modifiers: .option)

                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 320)
    }
}
