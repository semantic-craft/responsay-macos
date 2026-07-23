import ResponsayCore

/// Shared user-facing text for `LegalSkillCompileError` — used by the 导入/编辑 flow
/// (`LegalSkillsScreen`) and the 目录安装 flow (`LegalSkillCatalogSheet`) so the messages
/// stay in one place and never drift.
enum LegalSkillImportErrorText {
    static func message(for error: LegalSkillCompileError) -> String {
        switch error {
        case .missingMetadataBlock: return "文件里没有 ```legal-skill 元数据块。"
        case .invalidMetadataJSON: return "元数据 JSON 格式有误。"
        case .emptyMandatoryMapping: return "生成技能缺少推理内核（mandatoryMapping）。"
        case .emptyDisclaimer: return "生成技能缺少风险免责（disclaimer）。"
        case .emptyRewritePrompt: return "改写技能缺少提示词或技能说明。"
        case let .duplicateSkillID(id): return "技能 id「\(id)」与内置技能重复，请改 id 后再导入。"
        }
    }
}
