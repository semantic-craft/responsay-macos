enum OCRTextScript {
    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                 0x3040...0x30FF, 0xAC00...0xD7AF,
                 0x3000...0x303F, 0xFF00...0xFFEF:
                true
            default:
                false
            }
        }
    }
}
