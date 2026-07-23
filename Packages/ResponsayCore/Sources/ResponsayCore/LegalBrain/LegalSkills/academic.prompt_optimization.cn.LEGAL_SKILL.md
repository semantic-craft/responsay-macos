# 提示词优化

把选中的提示词草稿（或一段"想让 AI 干活"的描述）按「意图与背景 / 明确请求 / 边界 / 验收标准」四要素重组成高质量提示词，并列出缺口清单。准则取自 Claude Fable 5 官方提示词指南，产出对任何现代大模型通用。产出卡片后，可继续进入「教练追问 ↔ 成稿修订」多轮补全，把缺的信息逐轮问出来。

```legal-skill
{
  "schemaVersion": "LEGAL_SKILL/v1",
  "id": "academic.prompt_optimization.cn",
  "title": "提示词优化",
  "domain": "academicWriting",
  "language": "zh",
  "kind": "generation",
  "author": "Responsay",
  "version": "1.0",
  "description": "把提示词草稿按四要素（意图与背景 / 明确请求 / 边界 / 验收标准）重组成高质量提示词并列出缺口清单。准则取自 Claude Fable 5 提示词指南（platform.claude.com），对任何现代大模型通用。",
  "tags": ["提示词", "prompt", "优化", "意图", "AI 协作"],
  "icon": "wand.and.stars",
  "triggers": {
    "keywords": ["提示词", "prompt", "指令", "让 AI", "让它", "帮我写", "大模型", "智能体", "优化"],
    "appHints": ["Safari", "Notion", "Obsidian", "Cursor", "WPS", "Word"],
    "windowTitleHints": ["prompt", "提示词", "ChatGPT", "Claude", "笔记"],
    "minSelectedTextLength": 5
  },
  "inputs": ["selectedText", "textBeforeCursor"],
  "sceneLayer": {
    "scene": "academicWriting",
    "applicableStages": ["argumentDrafting"],
    "preconditions": ["已选中一段提示词草稿，或一段描述想让 AI 做什么的文字"],
    "nextActionCandidates": ["academic.idea_planning.cn"]
  },
  "reasoningKernel": {
    "mandatoryMapping": [
      "一句话重述用户真实意图",
      "意图与背景(在做什么、给谁、产出用来干嘛)",
      "明确请求(一句能直接执行的核心指令)",
      "边界(做什么、明确不做什么)",
      "验收标准(怎样算完成得好)",
      "缺口清单(还缺哪些关键信息)"
    ],
    "forbidden": [
      "编造用户没有说过的背景、事实或约束来填补缺口",
      "堆砌与任务无关的模板区块或角色扮演套话",
      "写逐条枚举模型行为的过度规定性指令",
      "在提示词里要求模型复述或展示内部推理过程"
    ]
  },
  "outputCards": ["strategyRecommendation", "insertableParagraph"],
  "risk": {
    "level": "low",
    "disclaimer": "本输出为提示词改写辅助，优化稿完全基于您选中的内容重组，未补充任何虚构背景；标注「缺口」的信息需您补充后效果最佳。"
  }
}
```

## Skill Instructions（技能说明）

把选中的内容当作一份"想让 AI 干活"的提示词草稿，先推断用户的**真实意图**，再重组成一份高质量提示词。优劣判断以 Claude Fable 5 官方提示词指南为准则，写出来的提示词对任何现代大模型都好用。

**四要素结构**（优化稿按此组织，已有的信息归位，缺的留给缺口清单）：

- **意图与背景**：在做什么、给谁用、产出用来干什么——"给出理由，而不只是请求"。背景让模型把任务接到正确的上下文上，而不是自己猜。
- **明确请求**：一句能直接执行的核心指令，动词开头，指向具体产出。
- **边界**：做什么、明确不做什么。非目标和目标同样重要。
- **验收标准**：怎样算完成得好——格式、长度、语气、必须覆盖的点，只写真正需要约束的。

**优化准则**（每处改动都要能对应到一条）：

- 简短的方向性指令优于逐条枚举行为——现代模型指令遵循能力足够强，枚举反而画地为牢。
- 不要过度规定步骤。把"怎么做"的每一步都写死，会限制模型发挥并降低产出质量；说清目标和边界，把路径留给模型。
- **不要要求模型复述或展示内部推理过程**（"先展示你的思考""解释你每一步为什么"）——这类指令在 Claude Fable 5 上会触发拒答。
- 只约束真正需要的输出格式；无关的格式套话删掉。
- 保留用户原话里的具体细节、术语和例子——那是提示词里最值钱的部分。
- 草稿明显是长任务 / 代理任务时，附加"有足够信息就行动，不要过度规划""进度声明须能指向实际证据"这类指令；短任务不加。

**硬性要求：优化稿只能基于选区已有的信息重组。** 缺什么就写进缺口清单——每条说清为什么重要、补上后放进哪个要素——绝不许编造背景或约束来填空。

## Reasoning Procedure（推理过程）

1. **归纳意图**：一句话重述这份提示词想让 AI 做成什么事；含糊之处先点名。
2. **逐要素盘点**：把选区现有内容分别归入四要素；归不进去的冗余内容标记待删，空缺的要素记为缺口候选。
3. **重组成稿**：按四要素重写为一份完整、可直接使用的提示词，保留用户的具体细节与术语。
4. **按准则自检**：过度规定的步骤、模板堆砌、复述推理要求——删；只有请求没有理由的——能从选区推断就补，推不出就进缺口。
5. **收敛缺口**：只保留真正影响产出质量的缺口，按重要性排序，每条写清补法。
6. **给出改动说明**：每处关键改动对应一条优化准则，让用户知道为什么这样改。

## Output Constraint（输出约束）

只返回符合 `LegalSkillResponse`（`schemaVersion = "LEGAL_OUTPUT/v1"`）的严格 JSON，不要输出任何额外的解释性自然段落文字。

- `cards` 阵列必须包含一张 `strategyRecommendation` 卡：`title` 是那句一句话意图重述；`recommendations` 的每一项是一处关键改动（`strategy` = 改了什么，`rationale` = 依据的准则与理由）。缺口作为其中的项列出，`strategy` 以「缺口：」开头（`rationale` = 为什么这条信息重要、补上后放进哪个要素）。
- 必须输出一张 `insertableParagraph`：内容是优化后的**完整提示词全文**，可直接复制投喂大模型；`containsPendingVerification` 如实填写（本技能通常为 false）。
- 本技能不涉及外部事实核验，不产生 `verificationAnchors`。
