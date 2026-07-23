# 思路推演

把还很粗糙的想法推演成「能拍板」的方案：说清在做什么、明确不做什么、选定路径与理由、关键决策、以及仍然未知的部分。产出结构化卡片后，可继续进入「评审压力测试 ↔ 提案人修订」的多轮对抗，把方案里含糊的地方逼出来。

```legal-skill
{
  "schemaVersion": "LEGAL_SKILL/v1",
  "id": "academic.idea_planning.cn",
  "title": "思路推演",
  "domain": "academicWriting",
  "language": "zh",
  "kind": "generation",
  "author": "Responsay",
  "version": "1.0",
  "description": "把粗糙想法推演成决策完备的方案：在做什么 / 明确不做什么 / 选定路径与理由 / 关键决策 / 未知项。方案结构衍生自开源技能 Waza (github.com/tw93/Waza, MIT, Copyright (c) 2026 Tw93)，提示词为面向研究与写作场景的重写。",
  "tags": ["思路推演", "方案规划", "关键决策", "压力测试"],
  "icon": "square.stack.3d.up",
  "triggers": {
    "keywords": ["思路", "推演", "方案", "计划", "怎么做", "该不该", "取舍", "选题", "设计", "路径"],
    "appHints": ["Word", "Pages", "Obsidian", "WPS", "Notion", "Safari"],
    "windowTitleHints": ["开题", "提纲", "计划", "方案", "笔记"],
    "minSelectedTextLength": 5
  },
  "inputs": ["selectedText", "textBeforeCursor"],
  "sceneLayer": {
    "scene": "academicWriting",
    "applicableStages": ["argumentDrafting", "literatureReview"],
    "preconditions": ["已选中一段想法、选题或方案草稿"],
    "nextActionCandidates": ["academic.counterargument.cn", "research.search_strategy.cn"]
  },
  "reasoningKernel": {
    "mandatoryMapping": [
      "一句话说清在做什么",
      "明确不做什么(非目标)",
      "选定路径与理由",
      "关键决策及其取舍",
      "仍然未知的部分",
      "可插入的方案陈述"
    ],
    "forbidden": [
      "用「待定 / 以后再说 / 视情况而定」占位充数",
      "罗列所有可能方案却不给出选定路径",
      "编造事实、数据或来源来支撑方案",
      "把模型的判断陈述为既定结论"
    ]
  },
  "outputCards": ["strategyRecommendation", "verificationTodos", "insertableParagraph"],
  "risk": {
    "level": "low",
    "disclaimer": "本输出为思路推演辅助，方案取舍与判断均为逻辑演练而非结论；涉及的外部事实与数据需您自行核验，默认标记 [待核]。"
  }
}
```

## Skill Instructions（技能说明）

对选中的想法 / 选题 / 方案草稿，做一次**决策完备**的推演——目标是让作者读完就能拍板，而不是收获一份"还需要再想想"的清单。

- 先用**一句话**说清这件事到底在做什么。写不出一句话，说明想法本身还没成形，那就先指出它缺什么。
- 明确写出**不做什么**。非目标和目标同样重要：它决定了方案的边界，也挡住后续的范围蔓延。
- 在可能的路径里**选定一条**，并给出选它的理由。可以提到被放弃的路径，但必须说明为什么不选，不允许把选择推回给用户。
- 列出 **3–5 个关键决策**，每个都写清取舍：选了什么、代价是什么。决策不是待办事项，而是"这里有分岔，我选了这边"。
- 只保留**真正未知**的部分，并说明它为什么现在无法决定、需要什么才能决定。已经能判断的不要塞进未知项装谨慎。
- 视情况给出一两句可直接插入文档的**方案陈述**。

**硬性要求：不允许占位符。** 「待定」「以后再说」「视情况而定」这类表述一旦出现，就说明该决策还没做——要么现在做出来，要么明确写进未知项并说明卡在哪里。

## Reasoning Procedure（推理过程）

1. **归纳意图**：读懂选区想做的事，用一句话重述；模糊之处先点名。
2. **划定边界**：写出明确的非目标，把容易蔓延的方向挡在外面。
3. **比较路径**：列出可行路径，按代价 / 可行性 / 与意图的贴合度比较，选定一条并说明理由。
4. **拆出关键决策**：把路径里真正有分岔的地方拆成 3–5 个决策，逐个给出取舍与代价。
5. **收敛未知**：把仍无法决定的点收进未知项，写清阻塞原因与解除条件。
6. **自检占位符**：回看全文，任何「待定 / 以后再说」都必须被替换为一个决策或一个带阻塞原因的未知项。

## Output Constraint（输出约束）

只返回符合 `LegalSkillResponse`（`schemaVersion = "LEGAL_OUTPUT/v1"`）的严格 JSON，不要输出任何额外的解释性自然段落文字。

- `cards` 阵列必须包含一张 `strategyRecommendation` 卡：`title` 是那句"在做什么"，`recommendations` 的每一项是一个关键决策（`strategy` = 决策本身，`rationale` = 选它的理由与代价）。非目标作为其中一项列出，`strategy` 以「不做：」开头。
- 未知项写入 `verificationTodos` 卡，每条说明阻塞原因；若方案依赖任何外部事实、数据或出处而未经真实联网核验，一并存入 `verificationAnchors`（`status = pending`，即 `[待核]`）并由卡片以 anchorId 交叉引用。
- 如果输出了 `insertableParagraph`，其 `containsPendingVerification` 属性必须如实反映文中是否包含未核验的坐标点。
