struct FnKey: Codable, Hashable, Identifiable, Sendable {
    var keyCode: UInt16
    var display: String

    var id: String {
        "\(keyCode):\(display)"
    }

    var idSlug: String {
        display.lowercased()
    }

    static func from(keyCode: UInt16) -> FnKey? {
        guard let display = keyCodeToDisplay[keyCode] else { return nil }
        return FnKey(keyCode: keyCode, display: display)
    }

    static let space = FnKey(keyCode: 49, display: "Space")
    static let v = FnKey(keyCode: 9, display: "V")
    static let e = FnKey(keyCode: 14, display: "E")

    /// A–Z in alphabetical order, for the "pick a custom letter" settings menu.
    static let letters: [FnKey] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".compactMap { ch in
        let display = String(ch)
        guard let keyCode = keyCodeToDisplay.first(where: { $0.value == display })?.key else { return nil }
        return FnKey(keyCode: keyCode, display: display)
    }

    private static let keyCodeToDisplay: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G",
        4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N",
        31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U",
        9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "5",
        23: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        space.keyCode: space.display,
    ]
}
