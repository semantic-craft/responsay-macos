import SwiftUI

/// Retired left/right Option picker kept as an empty compatibility shell while the settings
/// surface moves to `AnchorSchemeSection(anchor: .rightOption)`. Runtime no longer routes
/// left Option; right Option uses the same anchor binding table as Fn.
struct TriggerModeSection: View {
    var body: some View {
        EmptyView()
    }
}
