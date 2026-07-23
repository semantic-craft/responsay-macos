/// Explicit, local-only cleanup commands for editable OCR text.
public enum OCRTextCleanupAction: Sendable, Equatable {
    case chinesePunctuation
    case englishPunctuation
    case cjkSpacing

    public func apply(to text: String) -> String {
        switch self {
        case .chinesePunctuation:
            return Self.chinesePunctuation(in: text)
        case .englishPunctuation:
            return Self.englishPunctuation(in: text)
        case .cjkSpacing:
            return Self.cjkSpacing(in: text)
        }
    }

    private static func chinesePunctuation(in text: String) -> String {
        let replacements: [Character: Character] = [
            ",": "，", ".": "。", ";": "；", ":": "：", "!": "！", "?": "？",
        ]
        let characters = Array(text)
        let protectedIndices = protectedPunctuationIndices(in: characters)
        return String(characters.enumerated().map { index, character in
            guard let replacement = replacements[character] else { return character }
            guard !protectedIndices.contains(index) else { return character }
            let leftIsCJK = index > 0 && OCRTextScript.isCJK(characters[index - 1])
            let rightIsCJK = index + 1 < characters.count && OCRTextScript.isCJK(characters[index + 1])
            return leftIsCJK || rightIsCJK ? replacement : character
        })
    }

    private static func protectedPunctuationIndices(in characters: [Character]) -> Set<Int> {
        var protected: Set<Int> = []
        markBacktickSpans(in: characters, protected: &protected)
        markURLSpans(in: characters, protected: &protected)
        markEmailSpans(in: characters, protected: &protected)
        markCodeLikePunctuation(in: characters, protected: &protected)
        return protected
    }

    private static func markBacktickSpans(
        in characters: [Character],
        protected: inout Set<Int>
    ) {
        var index = 0
        while index < characters.count {
            guard characters[index] == "`" else {
                index += 1
                continue
            }

            let openingStart = index
            while index < characters.count, characters[index] == "`" { index += 1 }
            let delimiterLength = index - openingStart
            var search = index
            var closingEnd: Int?

            while search < characters.count {
                guard characters[search] == "`" else {
                    search += 1
                    continue
                }
                let runStart = search
                while search < characters.count, characters[search] == "`" { search += 1 }
                if search - runStart >= delimiterLength {
                    closingEnd = runStart + delimiterLength
                    break
                }
            }

            let spanEnd = closingEnd ?? characters.count
            protected.formUnion(openingStart..<spanEnd)
            index = spanEnd
        }
    }

    private static func markURLSpans(
        in characters: [Character],
        protected: inout Set<Int>
    ) {
        let prefixes = [Array("https://"), Array("http://"), Array("www.")]
        var index = 0

        while index < characters.count {
            guard let prefix = prefixes.first(where: { matches($0, at: index, in: characters) }) else {
                index += 1
                continue
            }

            var end = index + prefix.count
            while end < characters.count, !isURLBoundary(characters[end]) { end += 1 }
            while end > index + prefix.count, ".:".contains(characters[end - 1]) { end -= 1 }
            protected.formUnion(index..<end)
            index = max(end, index + 1)
        }
    }

    private static func markEmailSpans(
        in characters: [Character],
        protected: inout Set<Int>
    ) {
        for atIndex in characters.indices where characters[atIndex] == "@" {
            var start = atIndex
            var end = atIndex + 1
            while start > 0, isEmailCharacter(characters[start - 1]) { start -= 1 }
            while end < characters.count, isEmailCharacter(characters[end]) { end += 1 }
            while end > atIndex + 1, characters[end - 1] == "." { end -= 1 }
            guard start < atIndex, end > atIndex + 1 else { continue }
            protected.formUnion(start..<end)
        }
    }

    private static func markCodeLikePunctuation(
        in characters: [Character],
        protected: inout Set<Int>
    ) {
        var start = 0
        while start < characters.count {
            while start < characters.count, characters[start].isWhitespace { start += 1 }
            guard start < characters.count else { break }

            var end = start
            while end < characters.count, !characters[end].isWhitespace { end += 1 }
            for offset in codePunctuationOffsets(in: characters[start..<end]) {
                protected.insert(start + offset)
            }
            start = end
        }
    }

    private static func codePunctuationOffsets(
        in segment: ArraySlice<Character>
    ) -> Set<Int> {
        let text = String(segment)
        guard !text.contains("://"), !text.contains("@") else { return [] }

        let characters = Array(segment)
        var protected: Set<Int> = []
        var isCodeLike = ["->", "=>", "=="].contains(where: text.contains)

        for index in characters.indices {
            if characters[index] == ".",
               index > 0,
               index + 1 < characters.count {
                let left = characters[index - 1]
                let right = characters[index + 1]
                if isIdentifierCharacter(left), isIdentifierCharacter(right),
                   isASCIIIdentifier(left) || isASCIIIdentifier(right) {
                    protected.insert(index)
                    isCodeLike = true
                }
            }

            if characters[index] == ":",
               (index > 0 && characters[index - 1] == ":"
                || index + 1 < characters.count && characters[index + 1] == ":") {
                protected.insert(index)
                isCodeLike = true
            }
        }

        guard isCodeLike else { return [] }
        var bracketDepth = 0
        for index in characters.indices {
            if "([{<".contains(characters[index]) {
                bracketDepth += 1
            } else if ")]}>".contains(characters[index]) {
                bracketDepth = max(0, bracketDepth - 1)
            } else if bracketDepth > 0, ",.;:!?".contains(characters[index]) {
                protected.insert(index)
            }
        }
        return protected
    }

    private static func matches(
        _ prefix: [Character],
        at index: Int,
        in characters: [Character]
    ) -> Bool {
        guard index + prefix.count <= characters.count else { return false }
        return characters[index..<(index + prefix.count)].elementsEqual(prefix)
    }

    private static func isURLBoundary(_ character: Character) -> Bool {
        character.isWhitespace || ",，;；!！`".contains(character)
    }

    private static func isEmailCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || "._%+-".contains(character)
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func isASCIIIdentifier(_ character: Character) -> Bool {
        isIdentifierCharacter(character) && character.unicodeScalars.allSatisfy { $0.isASCII }
    }

    private static func englishPunctuation(in text: String) -> String {
        let replacements: [Character: Character] = [
            "，": ",", "。": ".", "；": ";", "：": ":", "！": "!", "？": "?",
        ]
        return String(text.map { replacements[$0] ?? $0 })
    }

    private static func cjkSpacing(in text: String) -> String {
        let characters = Array(text)
        var output = ""
        var index = 0

        while index < characters.count {
            let character = characters[index]
            guard character.isWhitespace, !character.isNewline else {
                output.append(character)
                index += 1
                continue
            }

            let start = index
            while index < characters.count,
                  characters[index].isWhitespace,
                  !characters[index].isNewline {
                index += 1
            }
            let leftIsCJK = start > 0 && OCRTextScript.isCJK(characters[start - 1])
            let rightIsCJK = index < characters.count && OCRTextScript.isCJK(characters[index])
            if !(leftIsCJK && rightIsCJK) {
                output.append(contentsOf: characters[start..<index])
            }
        }
        return output
    }
}
