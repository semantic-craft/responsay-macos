import SwiftUI
import AppKit
import ResponsayCore

/// 107 — the wide structured output panel for a run legal skill. Distinct from the
/// narrow voice-review card: it renders `LegalSkillResponse.cards` (evidence matrix,
/// counterargument, CNKI query, [待核] todos, insertable paragraph, fallback) and offers
/// gated inserts (插入正文 / 插入待核清单 / 插入检索式) + copy. Never auto-inserts.
///
/// good-ui pass: spacing/radii from `MacMetrics`; Dynamic-Type semantic fonts; empty state.
struct LegalSkillOutputView: View {
    let response: LegalSkillResponse
    var searchPermission: SearchPrivacyGate.SearchPermission = .disabled
    var onSearchVerify: (VerificationAnchor) async throws -> VerifiedSource? = { _ in nil }
    var onConfirmBeforeSearch: ((VerificationAnchor, @escaping () -> Void) -> Void)? = nil
    var onAnchorConfirmed: (VerificationAnchor, VerifiedSource) -> Void = { _, _ in }
    var onInsert: (LegalInsertAffordance) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    /// 继续对抗 — non-nil only when this skill has a 对抗 script and an assistant is wired,
    /// so the affordance can't appear where it would dead-end.
    var onDebate: (() -> Void)? = nil
    // 488 找类案：results + in-flight + trigger (default-off; only shown when search is permitted).
    var caseCandidates: [ScreenedCase] = []
    var isFindingCases: Bool = false
    var onFindSimilarCases: (() -> Void)? = nil

    private let renderer = LegalCardRenderer()

    @State private var searchStates: [String: AnchorSearchState] = [:]
    @State private var copiedAnchorId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetrics.m) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: MacMetrics.m) {
                    if response.cards.isEmpty && response.verificationAnchors.isEmpty {
                        Text("本次没有结构化输出。可复制摘要，或调整选区后重试。")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(response.cards.enumerated()), id: \.offset) { _, card in
                        cardSection(card)
                    }
                    if !response.verificationAnchors.isEmpty {
                        LegalSkillVerificationAnchorsView(
                            anchors: response.verificationAnchors,
                            searchPermission: searchPermission,
                            // 引注源验: this skill's whole point is auto-verify on appear; other skills'
                            // [待核] anchors stay manual (don't spend network/tokens unasked).
                            autoVerify: response.skillId == "verification.fact_check.cn",
                            searchStates: $searchStates,
                            copiedAnchorId: $copiedAnchorId,
                            onSearchVerify: onSearchVerify,
                            onConfirmBeforeSearch: onConfirmBeforeSearch,
                            onAnchorConfirmed: onAnchorConfirmed)
                    }
                }
            }
            .frame(maxHeight: 420)
            actionRow
            if !response.warnings.isEmpty {
                ForEach(response.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(MacMetrics.xl)
        .frame(width: 540, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: MacMetrics.radiusCard, style: .continuous).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: MacMetrics.radiusCard, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: MacMetrics.radiusCard, style: .continuous)
            .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        .padding(MacMetrics.xxl)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: MacMetrics.s) {
            Image(systemName: "scale.3d").font(.callout).foregroundStyle(MacPalette.accent)
            Text("法律技能输出 · \(sceneLabel(response.scene))")
                .font(.caption.weight(.semibold)).textCase(.uppercase).kerning(0.4)
                .foregroundStyle(MacPalette.accent)
            Spacer(minLength: 0)
            if !response.summary.isEmpty {
                Text(response.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    // MARK: - Per-card content

    @ViewBuilder private func cardSection(_ card: LegalOutputCard) -> some View {
        VStack(alignment: .leading, spacing: MacMetrics.s) {
            Text(renderer.title(for: card))
                .font(.caption.weight(.semibold)).foregroundStyle(MacPalette.prosody)
            content(for: card)
        }
        .padding(MacMetrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: MacMetrics.radiusSmall, style: .continuous))
    }

    @ViewBuilder private func content(for card: LegalOutputCard) -> some View {
        switch card {
        case let .evidenceArgumentMatrix(c):
            VStack(alignment: .leading, spacing: MacMetrics.s) {
                ForEach(c.rows) { row in matrixRow(row) }
            }
        case let .claimEvidenceMap(c):
            VStack(alignment: .leading, spacing: MacMetrics.xs) {
                ForEach(c.mappings) { m in
                    Text("• \(m.evidence) → \(m.supportsClaims.joined(separator: "、"))").font(.callout)
                }
            }
        case let .counterargument(c):
            VStack(alignment: .leading, spacing: MacMetrics.s) {
                Text(c.thesis).font(.callout.weight(.medium))
                if !c.implicitPremises.isEmpty {
                    Text("隐含前提：" + c.implicitPremises.joined(separator: "；"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(c.items) { item in
                    VStack(alignment: .leading, spacing: MacMetrics.hairline) {
                        Text("反方：\(item.counterargument)").font(.callout)
                        Text("依据：\(item.basis)").font(.caption).foregroundStyle(.secondary)
                        Text("回应：\(item.replyStrategy)").font(.caption).foregroundStyle(MacPalette.prosody)
                    }
                    .padding(.leading, MacMetrics.s)
                    .overlay(alignment: .leading) { Rectangle().fill(MacPalette.prosody.opacity(0.4)).frame(width: MacMetrics.hairline) }
                }
            }
        case let .nextStepDecisionTree(c):
            VStack(alignment: .leading, spacing: MacMetrics.xs) {
                ForEach(c.options) { o in
                    Text("◇ \(o.label)（\(o.condition)）").font(.callout)
                }
            }
        case let .cnkiQuery(c):
            VStack(alignment: .leading, spacing: MacMetrics.xs) {
                Text(c.expertQuery).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                if let plain = c.plainQuery, !plain.isEmpty {
                    Text(plain).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        case let .verificationTodos(c):
            Text(LegalCardRenderer.formatTodos(c, anchors: response.verificationAnchors))
                .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        case let .insertableParagraph(c):
            VStack(alignment: .leading, spacing: MacMetrics.xs) {
                Text(c.text).font(.system(.callout)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if c.containsPendingVerification { pendingBadge }
            }
        case let .legalAnalysis(c):
            VStack(alignment: .leading, spacing: MacMetrics.s) {
                ForEach(c.items) { item in
                    VStack(alignment: .leading, spacing: MacMetrics.hairline) {
                        Text(item.label).font(.callout.weight(.medium))
                        Text(item.content).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        case let .strategyRecommendation(c):
            VStack(alignment: .leading, spacing: MacMetrics.s) {
                ForEach(c.recommendations) { item in
                    VStack(alignment: .leading, spacing: MacMetrics.hairline) {
                        Text("策略：\(item.strategy)").font(.callout)
                        Text("理由：\(item.rationale)").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.leading, MacMetrics.s)
                    .overlay(alignment: .leading) { Rectangle().fill(MacPalette.prosody.opacity(0.4)).frame(width: MacMetrics.hairline) }
                }
            }
        case let .fallbackText(c):
            VStack(alignment: .leading, spacing: MacMetrics.s) {
                Text(c.text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                // Fallback text is the highest-risk path: the model output failed
                // structured parsing, so copied text still passes [待核] discipline.
                Button {
                    copy(VerificationPostProcessor().ensureTags(
                        in: c.text, anchors: response.verificationAnchors))
                } label: { Label("复制", systemImage: "doc.on.doc") }
                    .controlSize(.small)   // fallback: copy enabled, insert disabled
            }
        case let .caseRetrievalReport(c):
            // 487 — 检索作战图：每行渲染，链接可点、检索式可选中复制。
            VStack(alignment: .leading, spacing: MacMetrics.xs) {
                ForEach(Array(c.markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, raw in
                    retrievalLine(String(raw))
                }
                HStack(spacing: MacMetrics.s) {
                    Button { copy(c.markdown) } label: { Label("复制作战图", systemImage: "doc.on.doc") }
                        .controlSize(.small)
                    findCasesEntry   // 488 — 默认不联网；用户点才触发
                }
                caseCandidatesSection   // 488 — 联网候选结果（过案号验证闸 + 标注）
            }
        case let .caseFacts(c):
            // app 通常把它替换成作战图卡片；万一直达此处，最小展示焦点标题。
            VStack(alignment: .leading, spacing: MacMetrics.hairline) {
                ForEach(c.focuses) { f in Text("• \(f.label)").font(.callout) }
            }
        }
    }

    /// One Markdown line of the 作战图: heading → bold; list/note → inline Markdown
    /// (links tappable, `code` spans monospaced), selectable for copying queries.
    @ViewBuilder private func retrievalLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            EmptyView()
        } else if trimmed.hasPrefix("### ") {
            Text(trimmed.replacingOccurrences(of: "### ", with: ""))
                .font(.callout.weight(.semibold)).foregroundStyle(MacPalette.prosody)
                .padding(.top, MacMetrics.xs)
        } else if let attributed = try? AttributedString(markdown: trimmed) {
            Text(attributed).font(.callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(trimmed).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 488 找类案（联网，默认关）

    /// Trigger — only when search is permitted (default-off otherwise) and a handler is wired.
    @ViewBuilder private var findCasesEntry: some View {
        if searchPermission.isSearchEnabled, let onFindSimilarCases {
            if isFindingCases {
                HStack(spacing: MacMetrics.xs) {
                    ProgressView().controlSize(.small)
                    Text("正在联网找类案…").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button { onFindSimilarCases() } label: { Label("找类案（联网）", systemImage: "magnifyingglass") }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder private var caseCandidatesSection: some View {
        if !caseCandidates.isEmpty {
            VStack(alignment: .leading, spacing: MacMetrics.s) {
                Text("联网候选类案").font(.caption.weight(.semibold)).foregroundStyle(MacPalette.accent)
                ForEach(Array(caseCandidates.enumerated()), id: \.offset) { _, screened in
                    candidateRow(screened)
                }
            }
            .padding(.top, MacMetrics.xs)
        }
    }

    private func candidateRow(_ screened: ScreenedCase) -> some View {
        VStack(alignment: .leading, spacing: MacMetrics.hairline) {
            HStack(spacing: MacMetrics.xs) {
                candidateBadge(screened.label)
                Text(screened.candidate.title).font(.callout.weight(.medium))
            }
            Text(screened.candidate.text).font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            ForEach(screened.candidate.sourceURLs, id: \.self) { url in
                if let link = URL(string: url) { Link(url, destination: link).font(.caption2) }
            }
        }
        .padding(.leading, MacMetrics.s)
        .overlay(alignment: .leading) {
            Rectangle().fill(badgeTint(screened.label).opacity(0.4)).frame(width: MacMetrics.hairline)
        }
    }

    private func candidateBadge(_ label: CaseCandidateLabel) -> some View {
        let text = label == .verified ? "✅ 已核验来源" : "⚠️ AI 生成·未核验"
        return Text(text).font(.system(.caption2).weight(.medium))
            .padding(.horizontal, MacMetrics.xs).padding(.vertical, MacMetrics.hairline)
            .background(Capsule().fill(badgeTint(label).opacity(0.18)))
            .foregroundStyle(badgeTint(label))
    }

    private func badgeTint(_ label: CaseCandidateLabel) -> Color {
        label == .verified ? MacPalette.prosody : MacPalette.accent
    }

    private func matrixRow(_ row: EvidenceArgumentRow) -> some View {
        VStack(alignment: .leading, spacing: MacMetrics.hairline) {
            Text("\(row.claim) → \(row.legalElement)").font(.callout.weight(.medium))
            Text("待证：\(row.factToProve)").font(.caption).foregroundStyle(.secondary)
            Text("证据：\(row.evidence)").font(.caption).foregroundStyle(.secondary)
            Text("三性 真\(mark(row.authenticity))/合\(mark(row.legality))/关\(mark(row.relevance)) · 证明力 \(mark(row.probativeForce))")
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
            if !row.rebuttalRisk.isEmpty {
                Text("反驳风险：\(row.rebuttalRisk)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, MacMetrics.s)
        .overlay(alignment: .leading) { Rectangle().fill(MacPalette.accent.opacity(0.4)).frame(width: MacMetrics.hairline) }
    }

    private var pendingBadge: some View {
        Text("含 [待核]").font(.system(.caption2, design: .default).weight(.medium))
            .padding(.horizontal, MacMetrics.xs).padding(.vertical, MacMetrics.hairline)
            .background(Capsule().fill(MacPalette.accent.opacity(0.18)))
            .foregroundStyle(MacPalette.accent)
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: MacMetrics.s) {
            ForEach(Array(renderer.affordances(for: response).enumerated()), id: \.offset) { _, aff in
                Button { onInsert(aff) } label: {
                    Label(aff.label, systemImage: "text.insert")
                }
                .buttonStyle(.borderedProminent).tint(MacPalette.accent).foregroundStyle(MacPalette.accentInk)
            }
            // 继续对抗 / 继续完善 — only for skills that declare a 对抗 script (反方观点 / 思路
            // 推演 / 提示词优化). The card played the opening round; this hands it to the
            // assistant for 加压 ↔ 应答. The label follows the script so a 补全类 session
            // doesn't get sold as an adversarial one.
            if let onDebate {
                let title = DebateScript.forSkill(id: response.skillId)?.continueActionTitle ?? "继续对抗"
                Button { onDebate() } label: {
                    Label(title, systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.bordered).tint(MacPalette.accent)
                .accessibilityLabel("\(title)，把这张卡片交给多轮追问")
            }
            Spacer(minLength: 0)
            Button("关闭") { onDismiss() }.keyboardShortcut(.escape, modifiers: [])
        }
    }

    // MARK: - Helpers

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func mark(_ a: EvidenceAssessment) -> String {
        switch a { case .strong: return "强"; case .medium: return "中"; case .weak: return "弱"; case .unknown: return "?" }
    }
    private func mark(_ p: ProbativeForce) -> String {
        switch p { case .strong: return "强"; case .medium: return "中"; case .weak: return "弱"; case .unknown: return "?" }
    }

    private func sceneLabel(_ scene: LegalScene) -> String {
        switch scene {
        case .litigation: return "诉讼"
        case .academicWriting: return "学术"
        case .privacy: return "隐私"
        case .contract: return "合同"
        case .productCompliance: return "合规"
        case .unknown: return "通用"
        }
    }
}

#if DEBUG
#Preview("Legal output — evidence matrix") {
    let row = EvidenceArgumentRow(
        id: "1", claim: "被告应承担违约责任", legalElement: "违约行为",
        factToProve: "被告未按期付款", evidence: "银行流水、催款函",
        authenticity: .strong, legality: .strong, relevance: .medium, probativeForce: .medium,
        rebuttalRisk: "对方可能主张已部分清偿", gapFilling: "调取完整对账单",
        verificationAnchorIds: ["a1"])
    let response = LegalSkillResponse(
        runId: "demo", skillId: "litigation.evidence_argument_chain.cn",
        scene: .litigation, stage: .briefDrafting, summary: "已生成证据论证矩阵",
        cards: [
            .evidenceArgumentMatrix(EvidenceArgumentMatrixCard(title: "证据论证矩阵", rows: [row])),
            .verificationTodos(VerificationTodosCard(title: "待核清单", anchorIds: ["a1"])),
        ],
        verificationAnchors: [
            VerificationAnchor(id: "a1", label: "《民法典》第577条", kind: .law, query: "民法典 577"),
        ],
        warnings: ["本输出为辅助分析，不构成法律意见；事实与法条需核验。"])
    return LegalSkillOutputView(response: response).frame(width: 600, height: 640)
}
#endif
