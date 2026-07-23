import Foundation

public struct RewriteContextCarrier: Sendable, Equatable {
    public struct Hotword: Sendable, Equatable {
        public let text: String
        public let provenance: String

        public init(text: String, provenance: String) {
            self.text = text
            self.provenance = provenance
        }
    }

    public struct FrontAppHint: Sendable, Equatable {
        public let appName: String?
        public let windowTitle: String?
        public let provenance: String

        public init(appName: String? = nil, windowTitle: String? = nil, provenance: String) {
            self.appName = appName
            self.windowTitle = windowTitle
            self.provenance = provenance
        }
    }

    public struct PriorTurn: Sendable, Equatable {
        public let rawTranscript: String
        public let polishedText: String?
        public let provenance: String

        public init(rawTranscript: String, polishedText: String? = nil, provenance: String) {
            self.rawTranscript = rawTranscript
            self.polishedText = polishedText
            self.provenance = provenance
        }
    }

    public var hotwords: [Hotword]
    public var frontApp: FrontAppHint?
    public var priorTurns: [PriorTurn]

    public init(
        hotwords: [Hotword] = [],
        frontApp: FrontAppHint? = nil,
        priorTurns: [PriorTurn] = []
    ) {
        self.hotwords = hotwords
        self.frontApp = frontApp
        self.priorTurns = priorTurns
    }

    public var isEmpty: Bool {
        hotwords.isEmpty && frontApp == nil && priorTurns.isEmpty
    }
}
