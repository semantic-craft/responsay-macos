import SwiftUI
import ResponsayCore

enum DiffProjection { case original, idiomatic }

struct DiffSegmentsText: View {
    let segments: [DiffSegment]
    let projection: DiffProjection
    var body: some View { rendered }

    private var rendered: Text {
        segments.reduce(Text("")) { acc, seg in
            switch (projection, seg.kind) {
            case (.original, .inserted), (.idiomatic, .deleted):
                return acc                                   // omit from this projection
            case (.original, .deleted):
                return acc + Text(seg.text + " ").foregroundColor(MacPalette.deleted).strikethrough()
            case (.idiomatic, .inserted):
                return acc + Text(seg.text + " ").foregroundColor(MacPalette.inserted)
            default:
                return acc + Text(seg.text + " ")
            }
        }
    }
}
