import Foundation

/// Precedence layers, highest authority first (spec §1.5/§6):
/// system invariants > output schema > reasoning requirement > style pack > context/profile.
public enum PromptLayer: Int, Sendable, Comparable, Codable {
    case systemInvariants = 0
    case outputSchema = 1
    case reasoningRequirement = 2
    case stylePack = 3
    case contextProfile = 4

    public static func < (lhs: PromptLayer, rhs: PromptLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct PromptSegment: Sendable, Equatable {
    public let layer: PromptLayer
    public let text: String
    public init(layer: PromptLayer, text: String) {
        self.layer = layer
        self.text = text
    }
}

/// The assembled system prompt plus the privacy decision it must not alter.
public struct AssembledPrompt: Sendable, Equatable {
    public let segments: [PromptSegment]
    public let route: ModelRoute
    public let contextScope: ContextScope

    public var systemPrompt: String {
        segments.map(\.text).joined(separator: "\n\n")
    }
}

/// Inputs to assembly. The `route`/`contextScope` come from the privacy layer
/// (issue 110); a `StylePack` has no fields to alter them.
public struct PromptComponents: Sendable {
    public var systemInvariants: [String]
    public var outputSchema: [String]
    public var reasoningRequirement: [String]
    public var stylePack: StylePack?
    public var contextProfile: [String]
    public var route: ModelRoute
    public var contextScope: ContextScope

    public init(
        systemInvariants: [String] = [],
        outputSchema: [String] = [],
        reasoningRequirement: [String] = [],
        stylePack: StylePack? = nil,
        contextProfile: [String] = [],
        route: ModelRoute = .cloudAllowed,
        contextScope: ContextScope = .selectedTextOnly
    ) {
        self.systemInvariants = systemInvariants
        self.outputSchema = outputSchema
        self.reasoningRequirement = reasoningRequirement
        self.stylePack = stylePack
        self.contextProfile = contextProfile
        self.route = route
        self.contextScope = contextScope
    }
}

/// Orders prompt fragments by precedence and passes the privacy route through
/// untouched. The style pack always lands at `.stylePack` — it can never
/// outrank the system invariants or the output schema (issue 121).
public struct PromptAssembler: Sendable {
    public init() {}

    public func assemble(_ components: PromptComponents) -> AssembledPrompt {
        var segments: [PromptSegment] = []
        segments += components.systemInvariants.map { PromptSegment(layer: .systemInvariants, text: $0) }
        segments += components.outputSchema.map { PromptSegment(layer: .outputSchema, text: $0) }
        segments += components.reasoningRequirement.map { PromptSegment(layer: .reasoningRequirement, text: $0) }
        if let pack = components.stylePack, !pack.systemPrompt.isEmpty {
            segments.append(PromptSegment(layer: .stylePack, text: pack.systemPrompt))
        }
        segments += components.contextProfile.map { PromptSegment(layer: .contextProfile, text: $0) }

        // Stable sort by layer (preserve insertion order within a layer).
        let ordered = segments.enumerated()
            .sorted { lhs, rhs in
                lhs.element.layer == rhs.element.layer
                    ? lhs.offset < rhs.offset
                    : lhs.element.layer < rhs.element.layer
            }
            .map(\.element)

        // route + scope are copied verbatim — the pack cannot widen them.
        return AssembledPrompt(segments: ordered, route: components.route, contextScope: components.contextScope)
    }
}
