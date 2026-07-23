import Foundation

// MARK: - Kind

enum FeatureDemoKind: String, CaseIterable, Identifiable, Sendable {
    case coach, dictate, translate, english, selectTranslate
    case verify, keywords, fallback
    case snapOCR

    var id: String { rawValue }

    var durationMs: Double {
        switch self {
        case .coach:           8200
        case .dictate:         7600
        case .translate:       7000
        case .english:         8400
        case .selectTranslate: 8000
        case .verify:          12800
        case .keywords:        7400
        case .fallback:        8000
        case .snapOCR:         8500
        }
    }

    var offsetMs: Double {
        switch self {
        case .coach:           0
        case .dictate:         1100
        case .translate:       2100
        case .english:         3100
        case .selectTranslate: 4100
        case .verify:          0
        case .keywords:        1100
        case .fallback:        2100
        case .snapOCR:         0
        }
    }

    var reducedTimeMs: Double {
        switch self {
        case .coach:           4200
        case .dictate:         5650
        case .translate:       5650
        case .english:         6100
        case .selectTranslate: 5200
        case .verify:          9600
        case .keywords:        4600
        case .fallback:        5200
        case .snapOCR:         5400
        }
    }

    var outcomeToast: String {
        switch self {
        case .coach:           "改写已写入"
        case .dictate:         "已写入当前光标"
        case .translate:       "译文已写入"
        case .english:         "回答已准备好"
        case .selectTranslate: "译文已生成（只读）"
        case .verify:          "来源证据已带回"
        case .keywords:        "检索式已插入"
        case .fallback:        "来源链接已带回"
        case .snapOCR:         "已取字"
        }
    }
}

// MARK: - Result content shapes

struct DemoAnchorItem: Sendable, Equatable {
    let label: String
    let kind: String
    let sourceTitle: String
    let sourceURL: String
    let evidence: String
    let searchQuery: String
    let resultTitle: String
    let resultMeta: String
    let resultSnippet: String
    let matchFields: [String]

    init(label: String, kind: String, sourceTitle: String = "", sourceURL: String = "", evidence: String = "",
         searchQuery: String = "", resultTitle: String = "", resultMeta: String = "",
         resultSnippet: String = "", matchFields: [String] = []) {
        self.label = label
        self.kind = kind
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
        self.evidence = evidence
        self.searchQuery = searchQuery
        self.resultTitle = resultTitle
        self.resultMeta = resultMeta
        self.resultSnippet = resultSnippet
        self.matchFields = matchFields
    }
}

struct DemoKeywordGroup: Sendable, Equatable {
    let category: String
    let terms: [String]
}

struct DemoWebResultItem: Sendable, Equatable {
    let title: String
    let url: String
    let snippet: String
}

enum DemoResultContent: Sendable, Equatable {
    case standard
    case anchors(items: [DemoAnchorItem])
    case keywords(groups: [DemoKeywordGroup], cnkiQuery: String)
    case webResults(items: [DemoWebResultItem])
}

// MARK: - Host content

enum DemoHostContent: Sendable, Equatable {
    case document(title: String, before: String, selected: String, after: String, muted: String)
    case dictation(title: String)
    case translation(title: String, source: String, tail: String)
    case mail(toLabel: String, recipient: String, subjectLabel: String, subjectText: String)
    case webSearchHost(title: String, query: String)
    /// 截图识别 host: a scanned page with a marquee region. The extracted text is the
    /// result panel's `target` (rendered as the OCR result card).
    case snap(title: String, scanLines: [String])
}

// MARK: - Script

struct FeatureDemoScript: Sendable, Equatable {
    let kicker: String
    let title: String
    let blurb: String

    let hostName: String
    let host: DemoHostContent

    let listeningLabel: String
    let thinkingLabel: String

    let resultLabel: String
    let target: String
    let diffDeleted: String
    let diffInserted: String
    let reason: String
    let primaryAction: String

    let wordTokens: [String]
    let resultContent: DemoResultContent

    static func script(for kind: FeatureDemoKind) -> FeatureDemoScript {
        switch kind {
        case .coach:           coach
        case .dictate:         dictate
        case .translate:       translate
        case .english:         english
        case .selectTranslate: selectTranslate
        case .verify:          verify
        case .keywords:        keywords
        case .fallback:        fallback
        case .snapOCR:         snapOCR
        }
    }

    // MARK: - Basics

    static let coach = FeatureDemoScript(
        kicker: "选中文本改写",
        title: "选区命令改写",
        blurb: "选中一段法律工作说明，按住你指定的“选中文本改写”快捷键说要怎么改，松开后改写结果替换选区。改写快捷键在设置里自行指定（默认未绑定）；这是脚本动画，不联网。",
        hostName: "X 草稿",
        host: .document(title: "Legal tech post",
                        before: "",
                        selected: "Legal teams need voice input that keeps contract review moving without switching apps.",
                        after: "",
                        muted: "发布前仍可继续编辑。"),
        listeningLabel: "正在听指令 · 松开提交",
        thinkingLabel: "改写中…",
        resultLabel: "改写成 X 帖子",
        target: "Contract review should not stop just because you need to write.\n\nTap Fn, speak once, keep the legal work moving. #LegalTech #VoiceInput",
        diffDeleted: "keeps contract review moving without switching apps",
        diffInserted: "speak once, keep the legal work moving",
        reason: "加上法律工作 hook、短句和 hashtags，保留原意但更适合社交发布。",
        primaryAction: "写入",
        wordTokens: [],
        resultContent: .standard)

    // Startup demo: scripted, provider-free, and faithful to the default Fn dictation path.
    static let dictate = FeatureDemoScript(
        kicker: "Tier-1 入口",
        title: "Fn 听写",
        blurb: "轻点 Fn 开始说中文，再轻点同一个键结束；默认帮你整理成通顺文字，演示只播放本地脚本，不请求模型或网络。",
        hostName: "腾讯文档",
        host: .dictation(title: "庭后阅卷纪要"),
        listeningLabel: "正在听 · 再按 Fn 结束",
        thinkingLabel: "定稿中…",
        resultLabel: "写入文本",
        target: "阅卷纪要：\n- 原告主张继续履行合同\n- 被告抗辩已完成主要义务\n- 争议焦点待整理为庭审提纲",
        diffDeleted: "",
        diffInserted: "",
        reason: "",
        primaryAction: "插入",
        wordTokens: ["原告主张继续履行合同", "被告抗辩已完成主要义务", "争议焦点", "整理为庭审提纲"],
        resultContent: .standard)

    // Startup demo: spoken translate uses the same Fn stop key as dictation, then writes the
    // translated sentence straight into the active target.
    static let translate = FeatureDemoScript(
        kicker: "跨语言",
        title: "Fn Shift 语音翻译",
        blurb: "在微信/企业微信里按 Fn Shift 说中文，再按 Fn 结束，英文译文直接进入当前聊天框；这里是启动演示的虚拟场景。",
        hostName: "微信",
        host: .dictation(title: "涉外合同项目群"),
        listeningLabel: "正在听中文 · 再按 Fn 结束",
        thinkingLabel: "翻译并写入…",
        resultLabel: "译文",
        target: "I'll send over the revised NDA this afternoon. The dispute resolution clause still needs confirmation from our China law team.",
        diffDeleted: "",
        diffInserted: "",
        reason: "",
        primaryAction: "",
        wordTokens: ["修订版保密协议", "我今天下午发过去", "争议解决条款", "还要中国法团队确认"],
        resultContent: .standard)

    // Ask Anything is a scripted onboarding story. Real answers/actions still depend on
    // the user's enabled model and the web-search setting.
    // 任意提问（Fn Space）= 只读答卡。真实路径回答 + 可朗读/复制/重新生成/追问，
    // **不执行**「打开 App」类动作，也不写回文档。文案据此收敛（#450 feature-match）。
    static let english = FeatureDemoScript(
        kicker: "任意提问",
        title: "无选区提问 · 只读答卡",
        blurb: "按 Fn Space 问一个问题或说一个想法，结果出现在屏幕中央的只读答卡里——可以朗读、复制、重新生成、追问，但不会改动你的文档。",
        hostName: "Responsay",
        host: .webSearchHost(title: "任意提问",
                             query: "把这起合同案整理成庭审争议焦点"),
        listeningLabel: "正在听问题 · 再按 Fn 结束",
        thinkingLabel: "准备回答…",
        resultLabel: "示例回答（只读）",
        target: "争议焦点：\n1. 合同主要义务是否已实际履行\n2. 继续履行是否构成给付不能\n3. 解除权行使是否超过合理期限",
        diffDeleted: "",
        diffInserted: "",
        reason: "只读答卡，不会写回文档；是否联网取决于任意提问的搜索开关。",
        primaryAction: "复制",
        wordTokens: ["把这起合同案整理成庭审争议焦点"],
        resultContent: .standard)

    // MARK: - 截图识别 (snap OCR)

    // 截图识别（截图键）= 框选屏幕区域 → 取字进可编辑面板（复制 / 智能分段 / 翻译）。
    // 脚本动画：框选反白 → OCR 结果面板。原图不变；取字后可编辑。
    static let snapOCR = FeatureDemoScript(
        kicker: "Tier-1 入口",
        title: "截图识别",
        blurb: "框选屏幕上任意一块区域，把图片里的文字取出来进可编辑面板——复制、智能分段，或换引擎再识别、翻译。扫描件、PDF 截图、别人发来的图都能取字。",
        hostName: "预览",
        host: .snap(title: "（2024）京01民终1234号 · 扫描件",
                    scanLines: [
                        "本院认为，双方就争议解决条款的适用法律未达成一致，",
                        "应依照合同签订地法律确定管辖。原告提交的证据不足",
                        "以证明被告存在根本违约，其解除合同的主张缺乏依据……",
                        "综上，依照《中华人民共和国民法典》第五百六十三条",
                        "之规定，判决如下……",
                    ]),
        listeningLabel: "",
        thinkingLabel: "识别中…",
        resultLabel: "识别结果",
        target: "本院认为，双方就争议解决条款的适用法律未达成一致，应依照合同签订地法律确定管辖。",
        diffDeleted: "",
        diffInserted: "",
        reason: "取字后可编辑，原图不变。",
        primaryAction: "复制",
        wordTokens: [],
        resultContent: .standard)

    // Startup demo (#449): select legal text → Fn Space 任意提问 → "翻译成英文" → read-only answer card.
    // Faithful to the real 任意提问 path: a selection question routes into the Global Voice Assistant,
    // which returns a **read-only** floating answer card (复制 / 朗读 / 追问 — see AnswerActionBar). It
    // never auto-inserts into the document; the takeaway is 复制. Scripted, provider-free, no network.
    static let selectTranslate = FeatureDemoScript(
        kicker: "任意提问 · 选区",
        title: "选区翻译（只读）",
        blurb: "选中裁判文书或合同段落，按 Fn Space 说“翻译成英文”；译文出现在只读结果卡里，可复制带走，不会改动原文。脚本动画，不联网。",
        hostName: "裁判文书",
        host: .document(title: "涉外合同纠纷 · 本院认为",
                        before: "经审理查明，",
                        selected: "双方就争议解决条款的适用法律未达成一致，应依照合同签订地法律确定管辖。",
                        after: "",
                        muted: "需译成英文同步给境外律师，原文保留备查。"),
        listeningLabel: "正在听指令 · 再按 Fn 结束",
        thinkingLabel: "翻译中…",
        resultLabel: "英文译文（只读结果卡）",
        target: "The parties did not reach agreement on the governing law for the dispute-resolution clause; jurisdiction shall be determined under the law of the place where the contract was concluded.",
        diffDeleted: "",
        diffInserted: "",
        reason: "任意提问的译文是只读结果卡，可复制带走；不会自动改动原文。",
        primaryAction: "复制",
        wordTokens: [],
        resultContent: .standard)

}
