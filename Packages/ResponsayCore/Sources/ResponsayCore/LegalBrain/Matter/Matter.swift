import Foundation

// MARK: - 188 Matter (工作单元) — default-off, folder-backed state
//
// A `Matter` is one case / 工作单元 (litigation 案件, or a 研究课题). It is the
// optional, **default-off** state spine (spec §5; modeled on anthropics/claude-for-legal
// `matter-workspace`). When the matter layer is off — the default for 研究者自用 /
// single-client — nothing here is touched and skills run stateless. Foundation-only
// (platform boundary, as 101): no AppKit/AX/CGEvent/SwiftUI.

/// Where a matter sits in its lifecycle. Kept coarse on purpose (the router/skills carry
/// the fine `LegalStage`); these are the human-facing case phases.
public enum MatterStage: String, Codable, Sendable, CaseIterable {
    case intake     // 收/接案
    case filing     // 立案
    case evidence   // 举证
    case trial      // 庭审/听证
    case closed
}

/// Confidentiality posture. `heightened`/`cleanTeam` prompt extra care in cross-matter
/// settings (cross-matter read is off by default regardless — see `MatterStore`).
public enum MatterConfidentiality: String, Codable, Sendable, CaseIterable {
    case standard
    case heightened
    case cleanTeam
}

public enum MatterStatus: String, Codable, Sendable {
    case active
    case archived
}

/// One dated obligation on the matter timeline (举证期限 / 上诉期 / 开庭 …). `due` may carry
/// a `[待核]` tag when the date itself is unverified — never silently "confirmed".
public struct MatterDeadline: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let due: String        // ISO-8601 or 手册-style date; may end with [待核]
    public let note: String?

    public init(id: String, label: String, due: String, note: String? = nil) {
        self.id = id
        self.label = label
        self.due = due
        self.note = note
    }
}

/// The canonical per-matter record. Narrative + the structured state skills read/write
/// (要件表 / 证据清单 / 时间线·期限 / 待核清单 / 草稿历史). Persisted by `MatterStore`
/// as `matters/<slug>/matter.md` (YAML frontmatter + markdown body) + `history.md`.
public struct Matter: Codable, Sendable, Identifiable, Equatable {
    public let slug: String
    public var id: String { slug }

    public var title: String                  // 案由 / 一句话描述
    public var scene: LegalScene              // 诉讼 / 隐私 / 学术 …
    public var client: String                 // 我方当事人 / 业务单元
    public var counterparties: [String]       // 对方(可多)
    public var role: String                   // 我方角色(原告/被告/申请人/审查方…)
    public var stage: MatterStage
    public var confidentiality: MatterConfidentiality
    public var status: MatterStatus

    public var keyFacts: String               // 2–5 句:本案是什么、利害何在
    public var elementChecklist: [String]     // 要件表
    public var evidenceList: [String]         // 证据清单
    public var deadlines: [MatterDeadline]    // 时间线·期限
    public var pendingVerifications: [String] // 待核清单(VerificationAnchor.label)
    public var draftHistory: [String]         // 草稿历史(标题/id)
    public var relatedMatters: [String]       // 关联案 slug
    public var overrides: [String]            // 对画像/playbook 的本案覆盖项

    public var createdAt: String
    public var updatedAt: String

    public init(
        slug: String,
        title: String,
        scene: LegalScene,
        client: String,
        counterparties: [String] = [],
        role: String = "",
        stage: MatterStage = .intake,
        confidentiality: MatterConfidentiality = .standard,
        status: MatterStatus = .active,
        keyFacts: String = "",
        elementChecklist: [String] = [],
        evidenceList: [String] = [],
        deadlines: [MatterDeadline] = [],
        pendingVerifications: [String] = [],
        draftHistory: [String] = [],
        relatedMatters: [String] = [],
        overrides: [String] = [],
        createdAt: String,
        updatedAt: String
    ) {
        self.slug = slug
        self.title = title
        self.scene = scene
        self.client = client
        self.counterparties = counterparties
        self.role = role
        self.stage = stage
        self.confidentiality = confidentiality
        self.status = status
        self.keyFacts = keyFacts
        self.elementChecklist = elementChecklist
        self.evidenceList = evidenceList
        self.deadlines = deadlines
        self.pendingVerifications = pendingVerifications
        self.draftHistory = draftHistory
        self.relatedMatters = relatedMatters
        self.overrides = overrides
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One row of the portfolio ledger (`matters/_log.yaml`) — the parseable index used for
/// rollups and by `MatterLinker` (190) to answer "是否已有案件?". A projection of `Matter`.
public struct MatterLedgerEntry: Codable, Sendable, Identifiable, Equatable {
    public let slug: String
    public var id: String { slug }
    public var title: String
    public var scene: LegalScene
    public var client: String
    public var counterparties: [String]
    public var status: MatterStatus
    public var stage: MatterStage
    public var relatedMatters: [String]
    public var openedAt: String
    public var lastActiveAt: String

    public init(
        slug: String, title: String, scene: LegalScene, client: String,
        counterparties: [String], status: MatterStatus, stage: MatterStage,
        relatedMatters: [String], openedAt: String, lastActiveAt: String
    ) {
        self.slug = slug
        self.title = title
        self.scene = scene
        self.client = client
        self.counterparties = counterparties
        self.status = status
        self.stage = stage
        self.relatedMatters = relatedMatters
        self.openedAt = openedAt
        self.lastActiveAt = lastActiveAt
    }

    /// Project a full `Matter` into its ledger row.
    public init(from matter: Matter) {
        self.init(
            slug: matter.slug, title: matter.title, scene: matter.scene, client: matter.client,
            counterparties: matter.counterparties, status: matter.status, stage: matter.stage,
            relatedMatters: matter.relatedMatters, openedAt: matter.createdAt,
            lastActiveAt: matter.updatedAt)
    }
}
