import SwiftUI

/// The ten-second "Saved · Undo" strip after a Done (docs/02 §3). It is an overlay at the bottom of the
/// list area, above the banner slot; the list stays fully interactive while it is shown.
struct UndoToast: View {
    @EnvironmentObject private var localizer: Localizer
    let habitId: UUID
    let onUndo: (UUID) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(localizer.t("home.saved"), systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                onUndo(habitId)
            } label: {
                Text(localizer.t("common.undo"))
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
    }
}
