import SwiftUI

/// Reserved banner area at the very bottom of Home (docs/03 §2, docs/08).
///
/// P10 fills this with the banner host. Rules for that change: a fixed height while a banner is active
/// (0 when `AdGate` says no or nothing loaded), a non-interactive margin between the slot and the habit
/// controls, never overlapping buttons or the undo toast, no error text and no layout jump when a request
/// fails. `HomeContent` stacks it below the scrolling content, so the position is already reserved.
/// Until then it is a zero-height spacer.
struct BannerSlot: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .accessibilityHidden(true)
    }
}
