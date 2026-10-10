import NikuCueDomain
import SwiftUI

/// Shared chrome for the pushed onboarding steps: inline bar, system back hidden, localized Back button.
struct OnboardingStepChrome: ViewModifier {
    @EnvironmentObject private var localizer: Localizer
    @ObservedObject var model: OnboardingViewModel

    init(model: OnboardingViewModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localizer.t("common.back")) { model.back() }
                        .disabled(model.isBusy)
                }
            }
    }
}

/// Seven weekday chips, ISO Monday = 1 … Sunday = 7. Labels come from the app locale's calendar symbols
/// (presentation only; the stored value is the ISO set). Selection is shown by weight, border and a check mark,
/// never by colour alone, and exposed to VoiceOver as `isSelected`. At accessibility text sizes the chips
/// become full-width toggles so Thai and long symbols never clip.
struct OnboardingWeekdayChips: View {
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let selected: WeekdaySet
    let onToggle: (Int) -> Void

    init(selected: WeekdaySet, onToggle: @escaping (Int) -> Void) {
        self.selected = selected
        self.onToggle = onToggle
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                ForEach(1...7, id: \.self) { iso in
                    Toggle(isOn: Binding(get: { selected.contains(isoWeekday: iso) }, set: { _ in onToggle(iso) })) {
                        Text(symbol(iso: iso, short: false))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: 44)
                }
            }
        } else {
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { iso in
                    chip(iso)
                }
            }
        }
    }

    private func chip(_ iso: Int) -> some View {
        let isOn = selected.contains(isoWeekday: iso)
        let traits: AccessibilityTraits = isOn ? .isSelected : []
        return Button {
            onToggle(iso)
        } label: {
            Text(symbol(iso: iso, short: true))
                .font(.subheadline.weight(isOn ? .bold : .regular))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isOn ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: isOn ? 2 : 1))
                .overlay(alignment: .topTrailing) {
                    if isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .padding(3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol(iso: iso, short: false))
        .accessibilityAddTraits(traits)
    }

    private func symbol(iso: Int, short: Bool) -> String {
        guard (1...7).contains(iso) else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = localizer.locale
        let symbols = short ? calendar.shortStandaloneWeekdaySymbols : calendar.standaloneWeekdaySymbols
        let index = CalendarService.appleWeekday(fromISO: iso) - 1 // Sunday = 0 … Saturday = 6
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }
}

/// One selectable template row: icon, label and an explicit check mark (icon + label, docs/03 §3).
struct OnboardingTemplateRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    init(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    private var traits: AccessibilityTraits { isSelected ? .isSelected : [] }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28)
                Text(title)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(traits)
    }
}

/// Icon + text notice (errors, permission state). Text wraps freely so Thai diacritics are never clipped.
struct OnboardingNotice: View {
    let text: String
    let systemImage: String

    init(text: String, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}
