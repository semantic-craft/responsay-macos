import Foundation

/// Splits text into UTF-16 chunks safe to hand to one synthetic key event.
///
/// `CGEventKeyboardSetUnicodeString` has a documented soft cap (~20 UTF-16 units)
/// per event; payloads beyond it are truncated or dropped by the HID layer. Posting
/// a whole streamed delta in one event therefore garbles or loses the tail of long
/// CJK/emoji text. This chunker caps each event well under the limit **and never
/// splits a grapheme cluster** (a ZWJ emoji or a base+combining-mark pair stays
/// whole), so a chunk boundary can't break a character.
public enum UnicodeKeystrokeChunker {
    /// Headroom under the ~20-unit HID cap.
    public static let defaultMaxUnits = 18

    /// Split `text` into `[UInt16]` chunks, each `<= maxUnits` UTF-16 units, without
    /// breaking any grapheme cluster. A single grapheme longer than `maxUnits`
    /// (pathological — e.g. a long ZWJ sequence) is emitted whole in its own chunk,
    /// since splitting it would corrupt the cluster.
    public static func chunks(_ text: String, maxUnits: Int = defaultMaxUnits) -> [[UInt16]] {
        let cap = max(2, maxUnits)
        var chunks: [[UInt16]] = []
        var current: [UInt16] = []
        for character in text {
            let units = Array(String(character).utf16)
            if !current.isEmpty, current.count + units.count > cap {
                chunks.append(current)
                current = []
            }
            current.append(contentsOf: units)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
