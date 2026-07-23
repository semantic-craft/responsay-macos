import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ResponsayCore

/// Wraps a parsed import plan for `.sheet(item:)`, carrying the source filename
/// for the preview header. Identifiable so the sheet drives off it directly.
struct DictionaryImportPreview: Identifiable {
    let id = UUID()
    var plan: DictionaryImportPlan
    var fileName: String
}

extension DictionarySettingsPane {
    // MARK: - 批量导入（#519）

    /// Pick a .txt / .csv file, parse it against the current manual dictionary,
    /// and stage a preview. Nothing is written until the user confirms.
    func beginImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]
        panel.prompt = "导入"
        panel.message = "选择 .txt（一行一词）或 .csv（首列为词）文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            importErrorText = "无法读取所选文件——请确认它是 UTF-8 编码的 .txt / .csv 文本。"
            return
        }
        let format: DictionaryImportFormat = url.pathExtension.lowercased() == "csv" ? .csv : .txt
        let existing = store.userTermEntries(source: .manual).map(\.text)
        let plan = DictionaryImportParser.parse(text, format: format, existing: existing)
        importPreview = DictionaryImportPreview(plan: plan, fileName: url.lastPathComponent)
    }

    /// Write the staged additions into the dictionary and dismiss. Reversed so the
    /// file's first line lands on top (addManual inserts each at index 0).
    func commitImport(_ plan: DictionaryImportPlan) {
        for term in plan.additions.reversed() {
            dictionaryStore.addManual(term)
        }
        refreshDictionaryBindings()
        filter = .all
        importPreview = nil
    }

    @ViewBuilder
    func importPreviewSheet(_ preview: DictionaryImportPreview) -> some View {
        let plan = preview.plan
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("导入预览").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(appearanceStore.palette.ink)
                Text(preview.fileName).font(.system(size: 11))
                    .foregroundStyle(appearanceStore.palette.ink3)
            }

            importStatRow(count: plan.addCount, label: "新增词条", examples: plan.additions,
                          tint: appearanceStore.palette.accent)
            importStatRow(count: plan.duplicateCount, label: "跳过重复词", examples: plan.duplicates,
                          tint: appearanceStore.palette.ink3)
            importStatRow(count: plan.invalidCount, label: "无效 / 超长（不导入）", examples: plan.invalid,
                          tint: SettingsTheme.wine)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("取消") { importPreview = nil }
                    .keyboardShortcut(.cancelAction)
                Button("导入 \(plan.addCount) 词") { commitImport(plan) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan.addCount == 0)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    @ViewBuilder
    func importStatRow(count: Int, label: String, examples: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("\(count)").font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                Text(label).font(.system(size: 13)).foregroundStyle(appearanceStore.palette.ink2)
            }
            if !examples.isEmpty {
                Text(examples.prefix(5).joined(separator: "、") + (examples.count > 5 ? " …" : ""))
                    .font(.system(size: 11))
                    .foregroundStyle(appearanceStore.palette.ink3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
