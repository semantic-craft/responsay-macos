# 反方观点

面向全领域的学术写作：对选中的学术命题，重建隐含前提、预判可成立的反方观点、给出回应路径、需核验清单与学术数据库检索式。推理内核取自公开学术方法（论证重构、可反驳性、文献检索式构造），非任何受限语料的原文/范例。

```legal-skill
{
  "schemaVersion": "LEGAL_SKILL/v1",
  "id": "academic.counterargument.cn",
  "title": "反方观点",
  "domain": "academicWriting",
  "language": "zh",
  "kind": "generation",
  "author": "Responsay",
  "version": "1.0",
  "description": "为你写下的论点自动构造“假想敌”。深挖论证的隐含前提，预判审稿人可能提出的质疑与反驳，并提供可行的回应策略与文献检索线索。",
  "tags": ["学术写作", "论点推演", "质疑与反驳", "审稿人视角"],
  "icon": "person.2.wave.2",
  "triggers": {
    "keywords": ["命题", "论点", "反方", "质疑", "批判", "漏洞", "反驳", "预判", "审稿人"],
    "appHints": ["Word", "Pages", "Obsidian", "WPS", "Notion", "Safari"],
    "windowTitleHints": ["论文", "初稿", "投稿", "综述", "开题"],
    "minSelectedTextLength": 5
  },
  "inputs": ["selectedText", "textBeforeCursor"],
  "sceneLayer": {
    "scene": "academicWriting",
    "applicableStages": ["argumentDrafting", "literatureReview", "peerReview"],
    "preconditions": ["已选中一个可被检验的学术命题或论点句"],
    "nextActionCandidates": ["research.search_strategy.cn", "verification.fact_check.cn"]
  },
  "reasoningKernel": {
    "mandatoryMapping": [
      "命题重述",
      "脆弱隐含前提",
      "最强反方观点预判",
      "反方可能依据(学说/规范/实证/常理)",
      "回应与防御路径",
      "需核验的突破口",
      "针对性检索式",
      "可插入过渡句"
    ],
    "forbidden": [
      "设立极易推翻的'稻草人'反方",
      "编造文献、作者、期刊或出处",
      "虚构数据或实证结论",
      "把模型推断陈述为学界通说"
    ]
  },
  "outputCards": ["counterargument", "cnkiQuery", "verificationTodos", "insertableParagraph"],
  "risk": {
    "level": "medium",
    "disclaimer": "本输出为写作辅助，反方观点与依据为纯逻辑论证演练，并非学界绝对定论；所有文献、出处与数据均需您自行核验定夺，外部事实默认 [待核]。"
  }
}
```

## Skill Instructions（技能说明）

对选中的学术命题，做一次严苛的「自我反驳演练」，帮助作者在投稿前先听见“苛刻审稿人”的声音。该技能不局限于具体学科方向，适用于所有需要严密逻辑论证的写作。

- 先把命题写清楚，挖出它**依赖但未明说的隐含前提**——前提往往是整个论证最脆弱的地方。
- 针对前提与核心命题，构造出**最强的、能自圆其说的反方观点**（不要立容易推翻的“稻草人”），并列出反方可能会援引的**依据类型**（理论学说、规范沿革、实证数据、比较法或常识推论）。
- 对每个反方观点，给出切实可行的**回应路径**：作者应当限缩命题范围、补强前提证据、还是引入新的区分情形进行化解？
- 将回应过程中需要外部支撑的点，汇集成**需核验清单**，并产出一条可直接复制用于检索知网/万方等数据库的**专业布尔检索式**，以便作者去寻找真实文献。
- 视情况给出一两句用于引出辩驳内容的**可插入过渡句**。涉及具体出处的表述一律打上 `[待核]` 标签，绝不替作者将假想文献坐实。

## Reasoning Procedure（推理过程）

1. **精确重述命题**：用一句话准确归纳用户选区的主张。
2. **深挖隐含前提**：剖析出该命题成立所必需、但作者文中并未明文论证的前提要件。
3. **构建核心反方**：对着命题和前提构造能成立的“假想敌”观点，并标注其理论或事实依据类型。
4. **制定回应策略**：对每个反方观点给出清晰的回应路线规划（reply strategy）。
5. **列出待核清单**：把所有依赖文献 / 数据 / 规范的断言收进需核验清单，指导用户进行溯源。
6. **构造验证检索式**：提取核心辩驳概念，构造一条专业检索式（如 `SU=('核心词1' * '核心词2') AND SU=('反驳方向词')`）。

## Output Constraint（输出约束）

只返回符合 `LegalSkillResponse`（`schemaVersion = "LEGAL_OUTPUT/v1"`）的严格 JSON，不要输出任何额外的解释性自然段落文字。

- `cards` 阵列必须包含一张 `counterargument` 卡（要求包含 thesis / implicitPremises / items[counterargument, basis, replyStrategy] 结构）和一张 `cnkiQuery` 卡（包含布尔检索式）。
- 任何具体文献、作者、数据、规范编号只要并未被真实联网核验，必须存入 `verificationAnchors`（`status = pending`，即 `[待核]`），并由相关卡片以 anchorId 进行交叉引用。
- 如果输出了 `insertableParagraph`，其 `containsPendingVerification` 属性必须如实反映文中是否包含未核验的坐标点。
