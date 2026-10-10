import Combine
import NikuCueDomain
import SwiftUI

/// Home (docs/03 §2): today's date, the cat room, the speech bubble, today's habits, the progress line,
/// the add button and the reserved banner slot at the very bottom.
///
/// `HomeView` only reads the container from the environment and hands it to `HomeContent`, which owns the
/// view model: a `@StateObject` cannot be built from an `@EnvironmentObject` inside `init`.
/// `RootView` presents `HomeView()` with no arguments.
struct HomeView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        HomeContent(container: container)
    }
}

/// The actual Home screen. Every write goes through `HomeViewModel`; the view never touches the store.
struct HomeContent: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var localizer: Localizer
    @StateObject private var vm: HomeViewModel
    @ObservedObject private var controller: CatSceneController
    @ObservedObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// Midnight watch (QA Q11). A tick never writes; it only asks the view model to compare day keys.
    private let dayTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(container: AppContainer) {
        _vm = StateObject(wrappedValue: HomeViewModel(container: container))
        self.controller = container.scene.controller
        self.appState = container.appState
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header
                            // Spec: ~220 pt, reduced to 160 pt for accessibility text sizes / short screens (docs/03 §2).
                            CatRoom(height: catHeight)
                            bubble
                            if let key = vm.errorKey {
                                errorLine(key)
                            }
                            habitsSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        // Keep the last row's controls clear of the undo toast while it is visible (docs/03 §2).
                        .padding(.bottom, vm.undoCandidate == nil ? 24 : 88)
                    }
                    if let candidate = vm.undoCandidate {
                        UndoToast(habitId: candidate.habitId) { id in
                            Task { await vm.clearStatus(id) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: vm.undoCandidate)
                // Reserved banner area: stacked below the content, so it can never overlap a button (docs/03 §2).
                BannerSlot()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label(localizer.t("home.history"), systemImage: "calendar")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(localizer.t("home.history"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label(localizer.t("home.settings"), systemImage: "gearshape")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(localizer.t("home.settings"))
                }
            }
            .sheet(item: $vm.editorTarget, onDismiss: { Task { await vm.editorFinished() } }) { target in
                HabitEditorSheet(target: target)
            }
            .sheet(isPresented: $vm.showLimitExplanation) {
                HabitLimitSheet()
                    .presentationDetents([.medium, .large])
            }
            .task {
                applyReduceMotion()
                applyHaptics()
                await vm.homeAppeared()
            }
            .onDisappear { vm.homeDisappeared() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await vm.checkDayChange()
                    vm.refreshTimeOfDay()
                }
            }
            .onReceive(dayTimer) { _ in
                Task { await vm.checkDayChange() }
            }
            .onChange(of: vm.editorTarget) { _, target in
                appState.isModalPresented = target != nil || vm.showLimitExplanation
            }
            .onChange(of: vm.showLimitExplanation) { _, shown in
                appState.isModalPresented = shown || vm.editorTarget != nil
            }
            .onChange(of: appState.preferences.reduceMotion) { _, _ in applyReduceMotion() }
            .onChange(of: systemReduceMotion) { _, _ in applyReduceMotion() }
            .onChange(of: appState.preferences.hapticsEnabled) { _, _ in applyHaptics() }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localizer.t("home.today"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(formattedToday)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// SwiftUI text, never baked into the scene (docs/03 §2). The key comes from the scene controller.
    private var bubble: some View {
        Text(controller.messageKey.map { localizer.t($0) } ?? " ")
            .font(.body)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.quaternary))
            .animation(.easeInOut(duration: 0.2), value: controller.messageKey)
            .accessibilityHidden(controller.messageKey == nil)
    }

    @ViewBuilder
    private var habitsSection: some View {
        if let snapshot = vm.snapshot {
            if snapshot.rows.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(snapshot.rows) { row in
                        HabitRowView(row: row,
                                     isBusy: vm.busyHabitIds.contains(row.id),
                                     onDone: { Task { await vm.markDone(row.id) } },
                                     onUndo: { Task { await vm.clearStatus(row.id) } },
                                     onRest: { Task { await vm.markSkipped(row.id) } },
                                     onEdit: { vm.edit(row.habit) },
                                     canMoveUp: vm.canMove(row.id, by: -1),
                                     canMoveDown: vm.canMove(row.id, by: 1),
                                     onMoveUp: { Task { await vm.move(row.id, by: -1) } },
                                     onMoveDown: { Task { await vm.move(row.id, by: 1) } })
                    }
                }
                if let line = vm.progressLine(localizer: localizer) {
                    Label(line, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            addButton
            // Habits due on other weekdays and archived habits stay reachable for editing, archiving and resuming
            // (docs/02 §2). These rows have no Done control: only the edit button writes anything.
            editOnlyList(titleKey: "home.otherHabits", habits: otherActiveHabits)
            editOnlyList(titleKey: "home.archivedHabits", habits: snapshot.archivedHabits)
        } else if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var otherActiveHabits: [Habit] {
        guard let s = vm.snapshot else { return [] }
        let todayIds = Set(s.rows.map(\.id))
        return s.activeHabits.filter { !todayIds.contains($0.id) }
    }

    @ViewBuilder
    private func editOnlyList(titleKey: String, habits: [Habit]) -> some View {
        if !habits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(localizer.t(titleKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(habits) { habit in
                    HStack(spacing: 12) {
                        Image(systemName: HabitCategoryIcon.symbol(for: habit.category))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(habit.name)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            vm.edit(habit)
                        } label: {
                            Label(localizer.t("common.edit"), systemImage: "pencil")
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(localizer.t("common.edit"))
                        .accessibilityHint(habit.name)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    /// No schedule today: the cat stays, nothing is counted as missed (docs/03 §6).
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(localizer.t("home.none"), systemImage: "leaf")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(localizer.t("home.noneHelp"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var addButton: some View {
        Button {
            vm.addHabitTapped()
        } label: {
            Label(localizer.t("home.addHabit"), systemImage: "plus.circle")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private func errorLine(_ key: String) -> some View {
        Label(localizer.t(key), systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Helpers

    private var catHeight: CGFloat {
        (dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact) ? 160 : 220
    }

    /// The displayed day is the view model's day key (not the wall clock), so the header and the rows never
    /// disagree around midnight. Presentation may use the Thai Buddhist calendar; the key stays Gregorian.
    private var formattedToday: String {
        let service = CalendarService(clock: container.clock)
        let date = vm.today.map { service.date(startOf: $0) } ?? container.clock.now
        let formatter = DateFormatter()
        formatter.locale = localizer.locale
        formatter.calendar = localizer.locale.calendar
        formatter.timeZone = container.clock.timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// App setting OR OS setting (docs/03 §7).
    private func applyReduceMotion() {
        controller.reduceMotion = appState.preferences.reduceMotion || systemReduceMotion
    }

    private func applyHaptics() {
        container.haptics.isEnabled = appState.preferences.hapticsEnabled
    }
}
