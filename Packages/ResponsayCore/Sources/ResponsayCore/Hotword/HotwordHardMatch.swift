import Foundation

/// One spelling repair the enforcer made: the surface text it found (`from`)
/// and the canonical hotword spelling it swapped in (`to`).
public struct HotwordReplacement: Sendable, Equatable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// The result of a hard-match pass: the (possibly rewritten) transcript plus the
/// list of replacements applied, left-to-right. `replacements` is empty for a no-op.
public struct HotwordEnforcement: Sendable, Equatable {
    public let text: String
    public let replacements: [HotwordReplacement]

    public init(text: String, replacements: [HotwordReplacement]) {
        self.text = text
        self.replacements = replacements
    }
}

/// Hotword **hard-match enforcement** (ADR-0011) — the app-side Swift port of the
/// retired backend `hotword_match.mjs`, restored after the Node backend was
/// deleted (ADR-0029) so the Mac app stops shipping weak hints only.
///
/// A conservative, anchor-required post-pass over an ASR transcript: when the text
/// already contains a token (or short run of tokens) that is a near-miss of a domain
/// hotword, the span is rewritten to the hotword's exact spelling. It **never inserts**
/// a term that was not spoken — it only repairs the spelling of something already there
/// — so the faithful transcript (ADR-0008) is preserved. Idempotent; a no-op on empty
/// input or an empty hotword list.
public enum HotwordHardMatch {
    /// Widest token run a single hotword may span. Caps the acronym/space-split
    /// window so a long sentence never fans out into huge candidate windows.
    private static let maxWindowTokens = 12

    /// Rewrite near-miss spans of `text` to the exact spelling of any matching `hotword`.
    /// Legacy signature: every term is treated as user-taught (full fuzzy snap).
    public static func enforce(_ text: String, hotwords: [String]) -> HotwordEnforcement {
        enforce(text, userTerms: hotwords, seedTerms: [])
    }

    /// Provenance-gated enforcement (#470): `userTerms` (typed + auto-learned) get the full
    /// #465 confusion-weighted phonetic snap; `seedTerms` (generic seeds) are exact-only — never
    /// phonetically snapped — so a common seed can't eat an unrelated homophone (书局↛数据).
    public static func enforce(
        _ text: String,
        userTerms: [String],
        seedTerms: [String],
        learnedAliases: [String: String] = [:]
    ) -> HotwordEnforcement {
        let terms = prepareHotwords(userTerms: userTerms, seedTerms: seedTerms)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !terms.isEmpty || !learnedAliases.isEmpty else {
            return HotwordEnforcement(text: text, replacements: [])
        }

        let asciiTerms = terms.filter { $0.kind == .ascii }
        let tokens = tokenize(text)
        let longestKey = asciiTerms.reduce(1) { max($0, $1.key.count) }
        let maxWindow = min(maxWindowTokens, longestKey)

        var candidates = collectLearnedAliasCandidates(in: text, learnedAliases: learnedAliases)
        candidates += collectCandidates(in: text, tokens: tokens, terms: asciiTerms, maxWindow: maxWindow)
        candidates += collectCJKCandidates(in: text, terms: terms)
        let chosen = resolveOverlaps(candidates)
        guard !chosen.isEmpty else {
            return HotwordEnforcement(text: text, replacements: [])
        }
        return applyReplacements(to: text, chosen: chosen)
    }

    // MARK: - Hotword preparation

    /// A hotword reduced to its canonical spelling plus its comparison form.
    private struct Term {
        enum Kind { case ascii, cjk }
        let spelling: String
        let key: String          // ascii-normalized key (ascii); dedup key (cjk)
        let kind: Kind
        let cjkLen: Int          // CJK syllable count = window width for the pinyin pass; 0 for ascii
        let syllables: [String]  // per-char toneless pinyin syllables (cjk only)
        let allowsFuzzy: Bool    // user-taught terms snap near-misses; seeds are exact-only (#470)
    }

    /// De-duplicate by comparison key, dropping blanks; preserves first-seen spelling.
    /// A hotword with any ASCII letters/digits is an `.ascii` term (Latin near-miss path);
    /// a pure-CJK hotword (≥2 chars) becomes a `.cjk` term matched by pinyin syllables (#465).
    /// User terms (allowsFuzzy) are prepared first so a term that is *also* a seed keeps the
    /// user-provenance (fuzzy) variant; seed terms are exact-only (allowsFuzzy = false, #470).
    private static func prepareHotwords(userTerms: [String], seedTerms: [String]) -> [Term] {
        var seen = Set<String>()
        var terms: [Term] = []
        for raw in userTerms {
            guard let term = makeTerm(raw, allowsFuzzy: true, seen: &seen) else { continue }
            terms.append(term)
            // #469: an ASCII term may have been heard as its Chinese transliteration (Token→脱肯) —
            // register each curated reading as a synthetic CJK term snapping to the ASCII spelling.
            if term.kind == .ascii {
                terms.append(contentsOf: transliterationTerms(for: term, seen: &seen))
            }
            // #500 S2: a registered hotword may have a curated cross-form CJK alias (拉伦兹→拉伦茨)
            // the fuzzy pass can't reach — register each as a synthetic CJK term snapping to canonical.
            terms.append(contentsOf: aliasTerms(for: term, seen: &seen))
        }
        for raw in seedTerms { if let term = makeTerm(raw, allowsFuzzy: false, seen: &seen) { terms.append(term) } }
        return terms
    }

    /// Synthetic `.cjk` terms for a registered hotword's curated cross-form aliases (#500 S2): each
    /// alias surface becomes a CJK term carrying the alias's own toneless pinyin, so the #465 pinyin
    /// pass snaps that exact surface to the canonical spelling. Anchored to user-provenance terms
    /// (seeds stay exact-only, #470); the proximity blacklist still guards against eating a common word.
    private static func aliasTerms(for term: Term, seen: inout Set<String>) -> [Term] {
        var out: [Term] = []
        for surface in HotwordAliases.aliases(forCanonical: term.spelling) {
            let syllables = pinyinSyllables(surface)
            guard syllables.count >= 2 else { continue }
            let dedup = "al:" + term.spelling + ":" + syllables.joined(separator: ".")
            guard !seen.contains(dedup) else { continue }
            seen.insert(dedup)
            out.append(Term(spelling: term.spelling, key: dedup, kind: .cjk,
                            cjkLen: syllables.count, syllables: syllables, allowsFuzzy: true))
        }
        return out
    }

    /// Synthetic `.cjk` terms for an ASCII term's curated Chinese readings (#469): each reading
    /// becomes a CJK term whose window match snaps to the ASCII spelling, reusing the #465 pinyin
    /// pass. Only user-provenance ASCII terms get these (seeds stay exact-only, #470).
    private static func transliterationTerms(for asciiTerm: Term, seen: inout Set<String>) -> [Term] {
        var out: [Term] = []
        for reading in HotwordTransliterations.readings(forKey: asciiTerm.key) {
            let syllables = pinyinSyllables(reading)
            guard syllables.count >= 2 else { continue }
            let dedup = "t:" + asciiTerm.key + ":" + syllables.joined(separator: ".")
            guard !seen.contains(dedup) else { continue }
            seen.insert(dedup)
            out.append(Term(spelling: asciiTerm.spelling, key: dedup, kind: .cjk,
                            cjkLen: syllables.count, syllables: syllables, allowsFuzzy: true))
        }
        return out
    }

    /// Build one `Term` from a raw hotword, de-duplicating against `seen`. A hotword with any
    /// ASCII letters/digits is an `.ascii` term (Latin near-miss path); a pure-CJK hotword
    /// (≥2 chars) becomes a `.cjk` term matched by pinyin syllables (#465). nil when blank,
    /// a duplicate, or a single-char CJK term (too ambiguous to phonetically snap).
    private static func makeTerm(_ raw: String, allowsFuzzy: Bool, seen: inout Set<String>) -> Term? {
        let spelling = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spelling.isEmpty else { return nil }
        let asciiKey = normalizeKey(spelling)
        if !asciiKey.isEmpty {
            let dedup = "a:" + asciiKey
            guard !seen.contains(dedup) else { return nil }
            seen.insert(dedup)
            return Term(spelling: spelling, key: asciiKey, kind: .ascii,
                        cjkLen: 0, syllables: [], allowsFuzzy: allowsFuzzy)
        } else {
            let syllables = pinyinSyllables(spelling)
            let dedup = "c:" + syllables.joined(separator: ".")
            guard syllables.count >= 2, !seen.contains(dedup) else { return nil }
            seen.insert(dedup)
            return Term(spelling: spelling, key: dedup, kind: .cjk,
                        cjkLen: syllables.count, syllables: syllables, allowsFuzzy: allowsFuzzy)
        }
    }

    // MARK: - Tokenization

    /// A maximal ASCII-alphanumeric run, with its range in the original string.
    private struct Token {
        let range: Range<String.Index>
    }

    /// Maximal `[A-Za-z0-9]+` runs — the same token shape the backend regex used.
    /// CJK and other non-ASCII characters are not token characters, so a Latin term
    /// embedded in Chinese tokenizes cleanly without disturbing the surrounding text.
    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isASCIIAlphanumeric else {
                index = text.index(after: index)
                continue
            }
            let start = index
            var end = index
            while end < text.endIndex, text[end].isASCIIAlphanumeric {
                end = text.index(after: end)
            }
            tokens.append(Token(range: start..<end))
            index = end
        }
        return tokens
    }

    // MARK: - Candidate collection

    /// A window may only join adjacent tokens separated by ≤3 spacing/dot/underscore/
    /// hyphen characters (how an ASR splits an acronym or hyphenated term), never
    /// across other characters.
    private static func isJoinableGap(_ gap: Substring) -> Bool {
        guard gap.count <= 3 else { return false }
        return gap.allSatisfy { $0.isWhitespace || $0 == "." || $0 == "_" || $0 == "-" }
    }

    private struct Candidate {
        let range: Range<String.Index>
        let from: String
        let to: String
        let windowLen: Int
        let dist: Int
    }

    private static func collectLearnedAliasCandidates(
        in text: String,
        learnedAliases: [String: String]
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        for source in learnedAliases.keys.sorted(by: { $0.count > $1.count }) {
            guard let target = learnedAliases[source] else { continue }
            let surface = source.trimmingCharacters(in: .whitespacesAndNewlines)
            let spelling = target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !surface.isEmpty, !spelling.isEmpty, surface != spelling else { continue }

            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: surface, options: [.caseInsensitive], range: searchRange) {
                let from = String(text[range])
                if from != spelling, isAliasBoundary(in: text, range: range) {
                    candidates.append(Candidate(
                        range: range,
                        from: from,
                        to: spelling,
                        windowLen: max(1, surface.split(whereSeparator: \.isWhitespace).count),
                        dist: 0))
                }
                searchRange = range.upperBound..<text.endIndex
            }
        }
        return candidates
    }

    private static func isAliasBoundary(in text: String, range: Range<String.Index>) -> Bool {
        if range.lowerBound > text.startIndex {
            let before = text.index(before: range.lowerBound)
            if text[before].isASCIIAlphanumeric { return false }
        }
        if range.upperBound < text.endIndex, text[range.upperBound].isASCIIAlphanumeric {
            return false
        }
        return true
    }

    private static func collectCandidates(
        in text: String,
        tokens: [Token],
        terms: [Term],
        maxWindow: Int
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        for i in tokens.indices {
            var length = 1
            while length <= maxWindow, i + length <= tokens.count {
                if length > 1 {
                    let previous = tokens[i + length - 2]
                    let current = tokens[i + length - 1]
                    if !isJoinableGap(text[previous.range.upperBound..<current.range.lowerBound]) {
                        break
                    }
                }
                let start = tokens[i].range.lowerBound
                let end = tokens[i + length - 1].range.upperBound
                let surface = String(text[start..<end])
                let windowKey = normalizeKey(surface)
                if !windowKey.isEmpty,
                   let match = matchTerm(windowKey, terms: terms),
                   surface != match.term.spelling {
                    candidates.append(Candidate(
                        range: start..<end,
                        from: surface,
                        to: match.term.spelling,
                        windowLen: length,
                        dist: match.dist
                    ))
                }
                length += 1
            }
        }
        return candidates
    }

    // MARK: - CJK pinyin pass (#465)

    /// Contiguous runs of CJK characters, each as the list of its single-char ranges —
    /// a window may only join chars inside one run (never across Latin/punctuation).
    private static func cjkRuns(_ text: String) -> [[Range<String.Index>]] {
        var runs: [[Range<String.Index>]] = []
        var current: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if text[index].isCJK {
                current.append(index..<next)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
            index = next
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// Slide a `cjkLen`-char window over each CJK run; a window whose toneless pinyin
    /// matches a `.cjk` hotword (and differs in surface) becomes a replacement candidate.
    private static func collectCJKCandidates(in text: String, terms: [Term]) -> [Candidate] {
        // Seeds (allowsFuzzy == false) never take the phonetic pass — a common seed must not
        // eat an unrelated toneless-homophone (书局↛数据). Only user-taught CJK terms snap (#470).
        let cjkTerms = terms.filter { $0.kind == .cjk && $0.allowsFuzzy }
        guard !cjkTerms.isEmpty else { return [] }
        let runs = cjkRuns(text)
        var candidates: [Candidate] = []
        for term in cjkTerms {
            let width = term.cjkLen
            guard width >= 2 else { continue }   // single CJK chars are too ambiguous to phonetically snap
            for run in runs where run.count >= width {
                var start = 0
                while start + width <= run.count {
                    let lower = run[start].lowerBound
                    let upper = run[start + width - 1].upperBound
                    let surface = String(text[lower..<upper])
                    if surface == term.spelling {
                        // #480: an exact whole-term CJK match claims its span with a protective
                        // no-op candidate (dist 0, full width) so a shorter transliteration/fuzzy
                        // snap can't rewrite text that is already a registered hotword (思可瑞特平台
                        // must not be eaten by a Secret transliteration of its 思可瑞特 prefix). It is
                        // a no-op (from == to) and is not recorded as a replacement.
                        candidates.append(Candidate(
                            range: lower..<upper, from: surface, to: term.spelling,
                            windowLen: width, dist: 0))
                    } else if let cost = windowCost(pinyinSyllables(surface), term.syllables),
                              cost <= costBudget(forSyllables: term.cjkLen),
                              !cost0SnapIsUnsafeAcrossPolyphone(cost: cost, surface: surface, spelling: term.spelling),
                              !isProtectedSurface(surface) {   // #500 S2: never eat a common word
                        candidates.append(Candidate(
                            range: lower..<upper, from: surface, to: term.spelling,
                            windowLen: width, dist: cost))
                    }
                    start += 1
                }
            }
        }
        return candidates
    }

    // MARK: - Near-miss matching

    /// An exact normalized hit always wins; otherwise the closest hotword within a
    /// length-tiered edit-distance budget. Short hotwords demand an exact match
    /// (budget 0) so common words are never clobbered.
    private static func matchTerm(_ windowKey: String, terms: [Term]) -> (term: Term, dist: Int)? {
        var best: (term: Term, dist: Int)?
        for term in terms {
            if term.key == windowKey { return (term, 0) }
            guard term.allowsFuzzy else { continue }   // seeds: exact normalized hit only (#470)
            let budget = maxDistance(forLength: term.key.count)
            if budget == 0 || abs(term.key.count - windowKey.count) > budget { continue }
            let dist = levenshtein(windowKey, term.key)
            if dist <= budget, best == nil || dist < best!.dist {
                best = (term, dist)
            }
        }
        return best
    }

    // MARK: - Overlap resolution + application

    /// Prefer exact over fuzzy, then longer windows, then leftmost; drop overlaps.
    private static func resolveOverlaps(_ candidates: [Candidate]) -> [Candidate] {
        let ranked = candidates.sorted { lhs, rhs in
            if lhs.dist != rhs.dist { return lhs.dist < rhs.dist }
            if lhs.windowLen != rhs.windowLen { return lhs.windowLen > rhs.windowLen }
            return lhs.range.lowerBound < rhs.range.lowerBound
        }
        var chosen: [Candidate] = []
        for candidate in ranked {
            let overlaps = chosen.contains { existing in
                candidate.range.lowerBound < existing.range.upperBound
                    && existing.range.lowerBound < candidate.range.upperBound
            }
            if !overlaps { chosen.append(candidate) }
        }
        return chosen.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func applyReplacements(to text: String, chosen: [Candidate]) -> HotwordEnforcement {
        var output = ""
        var cursor = text.startIndex
        var replacements: [HotwordReplacement] = []
        for candidate in chosen {
            output += text[cursor..<candidate.range.lowerBound]
            output += candidate.to
            cursor = candidate.range.upperBound
            // A protective no-op (#480, from == to) emits the same text but is not a replacement.
            if candidate.from != candidate.to {
                replacements.append(HotwordReplacement(from: candidate.from, to: candidate.to))
            }
        }
        output += text[cursor...]
        return HotwordEnforcement(text: output, replacements: replacements)
    }
}

private extension Character {
    /// Matches the backend's `[A-Za-z0-9]` token class — ASCII letters/digits only.
    var isASCIIAlphanumeric: Bool {
        guard let ascii = asciiValue else { return false }
        return (ascii >= 48 && ascii <= 57)
            || (ascii >= 65 && ascii <= 90)
            || (ascii >= 97 && ascii <= 122)
    }

    /// CJK Unified Ideographs (+ Extension A) — the common-Chinese range we pinyin-match.
    var isCJK: Bool {
        unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
        }
    }
}
