import Foundation

// Preview / offline fixtures for ProsodyAnalysis. Defined in core because `Word`'s
// memberwise init is module-internal, so only the package can build these literals.
public extension ProsodyAnalysis {
    /// Simple sample for previews ("I'll call you.").
    static let sample = ProsodyAnalysis(
        text: "I'll call you.",
        isGeneratedExample: false,
        sourceWord: nil,
        ipa: "/aɪl ˈkɔl ju/",
        thoughtGroups: [
            ThoughtGroup(tone: .fall, words: [
                Word(text: "I'll", syllables: ["I'll"], stressIndex: nil, stressed: false, nuclear: false, ipa: nil, linkToNext: nil),
                Word(text: "call", syllables: ["call"], stressIndex: 0, stressed: true, nuclear: true, ipa: nil, linkToNext: nil),
                Word(text: "you", syllables: ["you"], stressIndex: nil, stressed: false, nuclear: false, ipa: nil, linkToNext: nil)
            ])
        ],
        notes: nil
    )

    /// Richer sample ("I'm not sure that conclusion holds up.").
    static let holdsUp: ProsodyAnalysis = {
        func w(_ t: String, _ syl: [String], _ si: Int?, _ s: Bool, _ n: Bool, _ l: Link? = nil) -> Word {
            Word(text: t, syllables: syl, stressIndex: si, stressed: s, nuclear: n, ipa: nil, linkToNext: l)
        }
        return ProsodyAnalysis(
            text: "I'm not sure that conclusion holds up.",
            isGeneratedExample: false,
            sourceWord: nil,
            ipa: "/aɪm nɑt ʃʊr ðæt kənˈkluʒən ˈhoʊldz ʌp/",
            thoughtGroups: [
                ThoughtGroup(tone: .fallRise, words: [
                    w("I'm", ["I'm"], nil, false, false),
                    w("not", ["not"], 0, true, false),
                    w("sure", ["sure"], 0, true, true)
                ]),
                ThoughtGroup(tone: .fall, words: [
                    w("that", ["that"], nil, false, false),
                    w("conclusion", ["con", "clu", "sion"], 1, true, false),
                    w("holds", ["holds"], 0, true, true, .liaison),
                    w("up", ["up"], 0, true, false)
                ])
            ],
            notes: "Stress the new info; let holds up carry the fall."
        )
    }()
}
