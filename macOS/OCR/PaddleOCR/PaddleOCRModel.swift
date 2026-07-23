import Foundation
import ResponsayCore

struct PaddleOCRModel: Sendable {
    let root: URL
    let detModel: URL
    let recModel: URL
    let recConfig: URL
    let characters: [String]

    init(root: URL) throws {
        self.root = root
        detModel = root.appendingPathComponent("det/inference.onnx")
        recModel = root.appendingPathComponent("rec/inference.onnx")
        recConfig = root.appendingPathComponent("rec/inference.yml")
        let fm = FileManager.default
        for file in [detModel, recModel, recConfig] where !fm.fileExists(atPath: file.path) {
            throw OCRError.recognitionFailed("PaddleOCR 模型未安装完整，请重新下载。")
        }
        characters = try Self.parseCharacters(from: recConfig)
    }

    private static func parseCharacters(from url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var found = false
        var chars: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "character_dict:" {
                found = true
                continue
            }
            guard found else { continue }
            guard trimmed.hasPrefix("- ") else {
                if !chars.isEmpty { break }
                continue
            }
            let raw = String(trimmed.dropFirst(2))
            chars.append(unquote(raw))
        }
        guard !chars.isEmpty else {
            throw OCRError.recognitionFailed("PaddleOCR 字典为空，请重新下载模型。")
        }
        return chars
    }

    private static func unquote(_ raw: String) -> String {
        if raw == "''''" { return "'" }
        if raw == "\\" { return "\\" }
        if raw.count >= 2, raw.first == "'", raw.last == "'" {
            return String(raw.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if raw.count >= 2, raw.first == "\"", raw.last == "\"" {
            return String(raw.dropFirst().dropLast())
        }
        return raw
    }
}
