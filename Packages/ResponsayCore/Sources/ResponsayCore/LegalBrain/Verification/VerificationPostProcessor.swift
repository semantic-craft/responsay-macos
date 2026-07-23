import Foundation

// MARK: - 108 VerificationPostProcessor
//
// Runs after skill execution: back-fills a pending `[待核]` anchor for any fact
// coordinate the model asserted but did not anchor, and keeps the `[待核]` tag on
// inserted body text. Never removes, never "verifies", never fabricates a source.

public struct VerificationPostProcessor: Sendable {
    private let extractor: FactCoordinateExtractor

    public init(extractor: FactCoordinateExtractor = FactCoordinateExtractor()) {
        self.extractor = extractor
    }

    /// Add a pending anchor for every fact coordinate found in the response text that
    /// isn't already anchored (matched by label). Returns the response unchanged if none.
    public func backfill(_ response: LegalSkillResponse) -> LegalSkillResponse {
        let found = extractor.extract(from: Self.collectText(response))
        let existing = Set(response.verificationAnchors.map(\.label))
        let added = found.filter { !existing.contains($0.label) }
        guard !added.isEmpty else { return response }
        return LegalSkillResponse(
            schemaVersion: response.schemaVersion, runId: response.runId, skillId: response.skillId,
            scene: response.scene, stage: response.stage, summary: response.summary,
            cards: response.cards, insertables: response.insertables,
            verificationAnchors: response.verificationAnchors + added,
            warnings: response.warnings)
    }

    /// Ensure each fact coordinate in `text` is followed by `[待核]` (idempotent), so an
    /// inserted body never drops the tag (e.g. `《民法典》第577条[待核]`).
    public func ensureTags(in text: String) -> String {
        ensureTags(in: text, anchors: [])
    }

    /// Anchor-aware variant (issue 297): a coordinate whose anchor has already
    /// left `.pending` (已核 / 用户确认 / rejected) must NOT be re-tagged — only
    /// still-pending (or never-anchored, which defaults to pending) coordinates
    /// keep the inline `[待核]` when the body lands in the host.
    /// Interval-based (猎虫④ F1/F2): the old per-label `replacingOccurrences`
    /// stamped the tag THROUGH longer coordinates sharing a prefix —
    /// `《刑法》第133条之一` became `《刑法》第133条[待核]之一`, substantively
    /// altering the inserted citation — and its "already tagged somewhere"
    /// check left every later occurrence of the same coordinate untagged.
    /// Occurrences are located verbatim, ranges contained in a longer label's
    /// range are dropped, and tags are inserted right-to-left so existing text
    /// is never rewritten. (A label the extractor normalized away from its
    /// verbatim span simply finds no range — same blind spot as before, never
    /// a corruption.)
    public func ensureTags(in text: String, anchors: [VerificationAnchor]) -> String {
        let settled = Set(anchors.filter { $0.status != .pending }.map(\.label))
        let allLabels = Set(extractor.extract(from: text).map(\.label))
        let pendingLabels = allLabels.subtracting(settled)
        guard !pendingLabels.isEmpty else { return text }

        // Settled labels still participate in containment filtering (fix-verifier
        // residual): with 《刑法》第133条之一 settled and 第133条 pending, the
        // short pending label inside the settled long citation must stay shielded.
        func occurrences(of labels: Set<String>) -> [Range<String.Index>] {
            var found: [Range<String.Index>] = []
            for label in labels {
                var search = text.startIndex..<text.endIndex
                while let r = text.range(of: label, range: search) {
                    found.append(r)
                    search = r.upperBound..<text.endIndex
                }
            }
            return found
        }
        let pendingOccurrences = occurrences(of: pendingLabels)
        let shields = occurrences(of: allLabels)
        let kept = pendingOccurrences.filter { candidate in
            !shields.contains { other in
                (other.lowerBound != candidate.lowerBound || other.upperBound != candidate.upperBound)
                    && other.lowerBound <= candidate.lowerBound
                    && candidate.upperBound <= other.upperBound
            }
        }

        let tag = "[待核]"
        var out = text
        for r in kept.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            guard !out[r.upperBound...].hasPrefix(tag) else { continue }
            out.insert(contentsOf: tag, at: r.upperBound)
        }
        return out
    }

    /// Flatten the model-authored text fields for coordinate scanning.
    static func collectText(_ response: LegalSkillResponse) -> String {
        var parts = [response.summary]
        for card in response.cards {
            switch card {
            case let .insertableParagraph(c): parts.append(c.text)
            case let .fallbackText(c): parts.append(c.text)
            case let .cnkiQuery(c): parts.append(c.expertQuery)
            case let .evidenceArgumentMatrix(c):
                parts.append(c.rows.map {
                    "\($0.claim) \($0.legalElement) \($0.factToProve) \($0.evidence) \($0.rebuttalRisk) \($0.gapFilling)"
                }.joined(separator: " "))
            case let .counterargument(c):
                parts.append(([c.thesis] + c.implicitPremises
                    + c.items.map { "\($0.counterargument) \($0.basis) \($0.replyStrategy)" }).joined(separator: " "))
            case let .claimEvidenceMap(c):
                parts.append(c.mappings.map { "\($0.evidence) \($0.supportsClaims.joined(separator: " "))" }.joined(separator: " "))
            case let .nextStepDecisionTree(c):
                parts.append(c.options.map { "\($0.label) \($0.condition) \($0.rationale)" }.joined(separator: " "))
            case .verificationTodos:
                break
            case .caseFacts, .caseRetrievalReport:
                break   // 作战图=确定性检索式(非 model 论断 prose)；焦点卡片随后被替换，均不参与 [待核] 扫描
            case let .legalAnalysis(c):
                parts.append(c.items.map { "\($0.label) \($0.content)" }.joined(separator: " "))
            case let .strategyRecommendation(c):
                parts.append(c.recommendations.map { "\($0.strategy) \($0.rationale)" }.joined(separator: " "))
            }
        }
        for insertable in response.insertables { parts.append(insertable.text) }
        return parts.joined(separator: "\n")
    }
}
