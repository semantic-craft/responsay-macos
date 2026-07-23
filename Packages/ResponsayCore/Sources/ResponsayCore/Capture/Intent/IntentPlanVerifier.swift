import Foundation

enum IntentPlanVerifier {
    struct VerifiedPlan: Sendable {
        let plan: IntentPlan
        let sourceUnits: [IntentSourceUnit]
        let renderedSourceIDs: [String]
        /// The full app-built candidate table (for conflict detection at finalize time).
        let entityCandidates: [IntentEntityCandidate]
        /// The plan's selections, resolved against the table in selection order.
        let selectedCandidates: [IntentEntityCandidate]
    }

    enum VerificationError: Error {
        case unsupportedVersion
        case invalidCoverage
        case invalidReference
        case invalidRelationship
        case invalidDecision
    }

    static func verify(
        _ plan: IntentPlan,
        sourceUnits: [IntentSourceUnit],
        transcript: String,
        entityCandidates: [IntentEntityCandidate] = []
    ) throws -> VerifiedPlan {
        guard plan.version == 1 else { throw VerificationError.unsupportedVersion }

        let sourceByID = Dictionary(uniqueKeysWithValues: sourceUnits.map { ($0.id, $0) })
        let planIDs = plan.units.map { $0.source.sourceID }
        guard plan.units.count == sourceUnits.count,
              Set(planIDs).count == planIDs.count,
              Set(planIDs) == Set(sourceByID.keys)
        else { throw VerificationError.invalidCoverage }

        for unit in plan.units {
            try validate(unit.source, sourceByID: sourceByID, transcript: transcript)
            guard let source = sourceByID[unit.source.sourceID],
                  unit.source.range == source.utf16Range,
                  unit.source.exactQuote == source.originalText
            else { throw VerificationError.invalidReference }
        }

        let roleByID = Dictionary(uniqueKeysWithValues: plan.units.map { ($0.source.sourceID, $0.role) })
        let correctionIDs = Set(roleByID.compactMap { $0.value == .correction ? $0.key : nil })
        var edges = [String: Set<String>]()
        var loserIDs = Set<String>()
        var cueIDs = Set<String>()

        for relationship in plan.supersessions {
            try validate(relationship.winner, sourceByID: sourceByID, transcript: transcript)
            try validate(relationship.loser, sourceByID: sourceByID, transcript: transcript)
            try validate(relationship.cue, sourceByID: sourceByID, transcript: transcript)

            let winnerID = relationship.winner.sourceID
            let loserID = relationship.loser.sourceID
            let cueID = relationship.cue.sourceID
            guard winnerID != loserID,
                  roleByID[winnerID] == .content,
                  roleByID[loserID] == .content,
                  roleByID[cueID] == .correction,
                  loserIDs.insert(loserID).inserted,
                  cueIDs.insert(cueID).inserted,
                  relationship.loser.range.location + relationship.loser.range.length
                    <= relationship.cue.range.location,
                  relationship.cue.range.location + relationship.cue.range.length
                    <= relationship.winner.range.location
            else { throw VerificationError.invalidRelationship }
            edges[winnerID, default: []].insert(loserID)
        }

        guard !containsCycle(edges: edges) else { throw VerificationError.invalidRelationship }

        if plan.decision == .render {
            guard cueIDs == correctionIDs else { throw VerificationError.invalidRelationship }
        }

        if plan.decision == .noIntentControl {
            guard plan.supersessions.isEmpty,
                  plan.units.allSatisfy({ $0.role == .content }),
                  plan.entities.isEmpty,
                  plan.structure == nil,
                  planIDs == sourceUnits.map(\.id)
            else { throw VerificationError.invalidDecision }
        }

        var renderedIDs = plan.units.compactMap { unit -> String? in
            let id = unit.source.sourceID
            return unit.role == .content && !loserIDs.contains(id) ? id : nil
        }
        guard plan.decision == .needsReview || !renderedIDs.isEmpty else {
            throw VerificationError.invalidDecision
        }

        // #563 — structure: a pure arrangement of the renderable IDs. Conservation is the hard
        // boundary (spec decision 17): every renderable unit appears exactly once across the
        // groups — nothing added, dropped or repeated; never a cue/note/clue/loser.
        //
        // #575 amendment to decision 17: ONE group listing the renderable IDs in their original
        // order is prose wearing a costume — and weak models put that costume on stochastically
        // (live eval: mimo-v2.5 slipped on a different case each run; the plan was otherwise
        // byte-perfect). Rendering such a group is IDENTICAL to omitting structure, so the
        // verifier takes the costume off itself (normalizedPlan drops it — the renderer must
        // never see a one-group structure, or bullets/numbering would alter the text). A
        // single group that REORDERS the units still rejects: normalization may never change
        // meaning. Every other violation rejects exactly as before.
        var normalizedPlan = plan
        if let structure = plan.structure {
            let flattened = structure.groups.flatMap { $0 }
            guard plan.decision == .render,
                  structure.groups.allSatisfy({ !$0.isEmpty }),
                  flattened.count == renderedIDs.count,
                  Set(flattened) == Set(renderedIDs)
            else { throw VerificationError.invalidDecision }
            if structure.groups.count >= 2 {
                renderedIDs = flattened
            } else if flattened == renderedIDs {
                normalizedPlan = IntentPlan(
                    version: plan.version, decision: plan.decision, units: plan.units,
                    supersessions: plan.supersessions, entities: plan.entities, structure: nil)
            } else {
                throw VerificationError.invalidDecision
            }
        }

        // #562 — entity selections: pure whitelist references. Unknown or duplicate ID →
        // invalid; a slot inside a unit that never renders (cue / note / grounding / loser)
        // is model confusion, not a safe no-op → invalid. Clues can't silently vanish: a
        // render plan that marks grounding units MUST resolve at least one entity — with an
        // empty table that is unsatisfiable, forcing the abstention decision instead.
        let candidateByID = Dictionary(uniqueKeysWithValues: entityCandidates.map { ($0.id, $0) })
        guard Set(plan.entities).count == plan.entities.count else {
            throw VerificationError.invalidReference
        }
        let selected = try plan.entities.map { id -> IntentEntityCandidate in
            guard let candidate = candidateByID[id] else { throw VerificationError.invalidReference }
            guard roleByID[candidate.target.sourceID] == .content,
                  !loserIDs.contains(candidate.target.sourceID)
            else { throw VerificationError.invalidRelationship }
            return candidate
        }
        // #575: with a NON-empty table this shape no longer throws — the pipeline's
        // unresolved-grounding arbiter turns it into a candidate-confirm review instead
        // (weak models skip the selection stochastically; live eval 2026-07-13). With an
        // empty table it stays unsatisfiable → the model should have abstained → invalid.
        if plan.decision == .render,
           plan.units.contains(where: { $0.role == .grounding }),
           selected.isEmpty,
           entityCandidates.isEmpty {
            throw VerificationError.invalidDecision
        }

        return VerifiedPlan(
            plan: normalizedPlan,
            sourceUnits: sourceUnits,
            renderedSourceIDs: renderedIDs,
            entityCandidates: entityCandidates,
            selectedCandidates: selected)
    }

    private static func validate(
        _ reference: IntentPlanSourceReference,
        sourceByID: [String: IntentSourceUnit],
        transcript: String
    ) throws {
        guard let source = sourceByID[reference.sourceID],
              reference.range.length > 0,
              !reference.exactQuote.isEmpty,
              reference.range.isWithin(utf16Count: transcript.utf16.count),
              reference.range.isWithin(source.utf16Range)
        else { throw VerificationError.invalidReference }

        let actualQuote = (transcript as NSString).substring(with: reference.range.nsRange)
        guard actualQuote == reference.exactQuote else { throw VerificationError.invalidReference }
    }

    private static func containsCycle(edges: [String: Set<String>]) -> Bool {
        enum Visit { case active, complete }
        var visits = [String: Visit]()

        func visit(_ id: String) -> Bool {
            if visits[id] == .active { return true }
            if visits[id] == .complete { return false }
            visits[id] = .active
            for next in edges[id, default: []] where visit(next) { return true }
            visits[id] = .complete
            return false
        }

        return edges.keys.contains(where: visit)
    }
}
