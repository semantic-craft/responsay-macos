import Foundation

/// Recognition parameters for the Volcengine bidirectional-streaming ASR request.
/// The server keeps ITN/punctuation permanently available; these toggles ride in the
/// `request` block of the full-client-request JSON. `hotwords` map the app's 词典 +
/// 屏幕临时词 into ByteDance's `corpus.context` biasing channel.
public struct VolcengineRealtimeConfig: Sendable, Equatable {
    public var sampleRate: Int
    public var enableITN: Bool
    public var enablePunc: Bool
    public var enableDDC: Bool
    public var hotwords: [String]
    public var language: String?
    public var endWindowSize: Int?
    /// #579 — semantic-segmentation silence ceiling (ms). The server default (3000) still
    /// splits a sentence when the speaker pauses deliberately — exactly what 口述释字 sounds
    /// like — and every split lands a sentence-final period inside a name. 8000 keeps
    /// spelled-out speech in one sentence; only active when `endWindowSize` is unset
    /// (setting that switches the server to silence-driven splitting, per Volcengine docs).
    public var vadSegmentDuration: Int?
    /// #579 — Volcengine two-pass mode (`enable_nonstream`): each utterance is re-recognized
    /// by the non-streaming model at finalization, so the FINAL punctuation is decided from
    /// the whole utterance semantically instead of pause acoustics. Streaming partials are
    /// unchanged; only the definite text improves — which is all the app ever inserts.
    public var enableTwoPass: Bool

    public init(
        sampleRate: Int = 16000,
        enableITN: Bool = true,
        enablePunc: Bool = true,
        enableDDC: Bool = false,
        hotwords: [String] = [],
        language: String? = nil,
        endWindowSize: Int? = nil,
        vadSegmentDuration: Int? = nil,
        enableTwoPass: Bool = false
    ) {
        self.sampleRate = sampleRate
        self.enableITN = enableITN
        self.enablePunc = enablePunc
        self.enableDDC = enableDDC
        self.hotwords = hotwords
        self.language = language
        self.endWindowSize = endWindowSize
        self.vadSegmentDuration = vadSegmentDuration
        self.enableTwoPass = enableTwoPass
    }
}
