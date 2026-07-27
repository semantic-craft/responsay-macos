# 目标七问

把选中的模糊需求（或一段口述的"想让 Agent 做成一件事"的描述）按「目标七问」——目的 Why / 完成态 Done / 证据 Proof / 反作弊 Anti / 边界 Bounds / 取舍 Trade / 未知 Unknown——整理成一份 Agent 可独立执行数小时的目标任务书，并列出缺口清单。方法源自 Khazix 的开源 Leader.skill。产出卡片后，可继续进入「教练追问 ↔ 成稿修订」多轮补全，把缺的信息逐轮问出来。

```legal-skill
{
  "schemaVersion": "LEGAL_SKILL/v1",
  "id": "academic.goal_brief.cn",
  "title": "目标七问",
  "domain": "academicWriting",
  "language": "zh",
  "kind": "generation",
  "author": "Responsay",
  "version": "1.0",
  "description": "按「目标七问」（目的 Why / 完成态 Done / 证据 Proof / 反作弊 Anti / 边界 Bounds / 取舍 Trade / 未知 Unknown）把模糊需求整理成 Agent 可独立执行的目标任务书，并列出缺口清单。方法源自 Khazix 的开源 Leader.skill（github.com/KKKKhazix/khazix-skills）。",
  "tags": ["目标七问", "任务书", "Agent", "长任务", "需求", "验收", "AI 协作"],
  "icon": "target",
  "triggers": {
    "keywords": ["任务书", "目标", "验收", "需求", "agent", "智能体", "交给", "帮我做", "长任务"],
    "appHints": ["Safari", "Notion", "Obsidian", "Cursor", "WPS", "Word", "Terminal"],
    "windowTitleHints": ["任务", "目标", "需求", "ChatGPT", "Claude", "Cursor", "笔记"],
    "minSelectedTextLength": 5
  },
  "inputs": ["selectedText", "textBeforeCursor"],
  "sceneLayer": {
    "scene": "academicWriting",
    "applicableStages": ["argumentDrafting"],
    "preconditions": ["已选中一段描述任务目标的文字：需求、想法，或准备交给 Agent 的指令草稿"],
    "nextActionCandidates": ["academic.prompt_optimization.cn"]
  },
  "reasoningKernel": {
    "mandatoryMapping": [
      "一句话重述这个任务真正要做成什么",
      "目的 Why(这活为什么干、真需求还是假手段)",
      "完成态 Done(可判定的验收硬指标)",
      "证据 Proof(用什么证明确实完成)",
      "反作弊 Anti(明令禁止的糊弄方式)",
      "边界 Bounds(能动什么、不能动什么)",
      "取舍 Trade(冲突时优先保什么、替用户拍的板)",
      "未知 Unknown(未验证的假设与风险)",
      "缺口清单(七问里还缺哪些关键信息)"
    ],
    "forbidden": [
      "编造用户没有说过的目标、指标、约束或环境事实来填补缺口",
      "把未验证的假设写成既定事实(必须标「假设，未验证」)",
      "写执行者无法自行判定的验收标准(如「领导满意」「效果不错」)",
      "在任务书里加入「中途来问我」类指令(任务书必须自足)",
      "在任务书里要求模型复述或展示内部推理过程"
    ]
  },
  "outputCards": ["strategyRecommendation", "insertableParagraph"],
  "risk": {
    "level": "low",
    "disclaimer": "本输出为任务书整理辅助，任务书完全基于您选中的内容重组，未补充任何虚构目标或事实；标注「拍板」的默认假设可推翻，标注「缺口」的信息需您补充后效果最佳。"
  }
}
```

## Skill Instructions（技能说明）

把选中的内容当作一份"想让 Agent 独立做成一件事"的模糊需求，先推断用户的**真实目的**，再重组成一份 Agent 可以数小时不回头问人、照着独立执行的目标任务书。方法取自「目标七问」：任务书写错的事实会被一字不差地执行，所以每一条都必须可判定、可溯源，全文不许出现「来找我 / 中途再问」。

**七问结构**（任务书按此组织，已有的信息归位，缺的留给缺口清单）：

- **目的 Why**：这活为什么干、成了什么样算值。把想法升华成可测量的指标，区分真需求与假手段——用户说「加缓存」，真目的可能是「响应时间 < 100ms」。
- **完成态 Done**：怎样算做完，写成执行者可以自行判定的硬指标（能跑的命令、能查的数字），基线不可退（测试数、覆盖率不得低于现状）。
- **证据 Proof**：用什么证明确实完成——写进任务书的验收步骤是"明卷"；另附 2–3 条建议用户亲自抽查的检查点，验收不交给执行者自评。
- **反作弊 Anti**：明令禁止的糊弄方式——跳过测试、编造命令输出、削减断言凑绿、静默吞掉事故。只写针对本任务真实风险的条目，不堆通用套话。
- **边界 Bounds**：能动什么、不能动什么，有名有姓（文件、模块、时间、风险偏好）；非目标和目标同样重要。
- **取舍 Trade**：目标冲突时优先保什么（快 vs 稳、范围 vs 深度）。用户没说的取舍不留白：给出「拍板」默认选择并显式标注，让用户一眼能推翻。
- **未知 Unknown**：从选区推不出、也无法就地验证的事实，一律标「假设，未验证」；摸不到的环境写成任务书开头的"任务 0"，让执行者先自检再开工。

**硬性要求：任务书只能基于选区已有的信息重组。** 缺什么就写进缺口清单——每条说清为什么重要、补上后放进哪一问——绝不许编造目标、指标或环境事实来填空。保留用户原话里的具体细节、术语和数字——那是任务书里最值钱的部分。

## Reasoning Procedure（推理过程）

1. **归纳目的**：一句话重述这个任务真正要做成什么；用户给的是手段（"加个缓存"）就向上追一层真目的，并标注这是推断。
2. **逐问盘点**：把选区现有内容分别归入七问；归不进去的冗余内容标记待删，空缺的问记为缺口候选。
3. **重组成书**：按七问重写为一份完整、可直接交给执行 Agent 的任务书；无法验证的环境事实转成"任务 0：开工自检"。
4. **替用户拍板**：影响写法但用户没说的取舍，选一个合理默认并标注「拍板」，附一句理由。
5. **收敛缺口**：只保留真正影响执行结果的缺口，按重要性排序，每条写清补上后放进哪一问。
6. **自检红线**：逐条核对——验收是否可自行判定、假设是否都已标注、全文是否无「来找我」类指令。

## Output Constraint（输出约束）

只返回符合 `LegalSkillResponse`（`schemaVersion = "LEGAL_OUTPUT/v1"`）的严格 JSON，不要输出任何额外的解释性自然段落文字。

- `cards` 阵列必须包含一张 `strategyRecommendation` 卡：`title` 是那句一句话目的重述；`recommendations` 的每一项是一处关键整理（`strategy` = 做了什么归位或拍板，`rationale` = 依据的七问维度与理由）。替用户拍的板以「拍板：」开头；缺口以「缺口：」开头（`rationale` = 为什么这条信息重要、补上后放进哪一问）。
- 必须输出一张 `insertableParagraph`：内容是按七问组织的**完整任务书全文**，可直接复制交给执行 Agent；`containsPendingVerification` 如实填写（含未验证假设时为 true）。
- 本技能不涉及外部事实核验，不产生 `verificationAnchors`。
