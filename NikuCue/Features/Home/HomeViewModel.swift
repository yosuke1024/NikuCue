import Combine
import Foundation
import NikuCueDomain
import SwiftUI

/// Home state: today's rows, progress, the 10-second undo window and cat event routing (docs/02 §3, docs/03 §2).
/// Every write goes through `HabitService`; success feedback and cat reactions happen only after the save returns.
@MainActor
final class HomeViewModel: ObservableObject {
    struct UndoCandidate: Equatable {
        let habitId: UUID
        let expiresAt: Date
    }

    enum EditorTarget: Identifiable, Equatable {
        case new
        case edit(Habit)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let h): return h.id.uuidString
            }
        }
    }

    @Published private(set) var snapshot: HomeSnapshot?
    @Published private(set) var isLoading = false
    /// Localization key of the error to show (e.g. `error.save`); cleared when the user acts again.
    @Published var errorKey: String?
    @Published private(set) var undoCandidate: UndoCandidate?
    @Published var editorTarget: EditorTarget?
    @Published var showLimitExplanation = false
    /// Habit ids whose write is in flight, so a double tap cannot start a second write (QA Q02).
    @Published private(set) var busyHabitIds: Set<UUID> = []

    static let undoWindow: TimeInterval = 10

    private let container: AppContainer
    private var undoTimer: Task<Void, Never>?

    init(container: AppContainer) {
        self.container = container
    }

    var habitService: HabitService { container.habitService }
    var coordinator: CatCoordinator { container.catCoordinator }
    var today: DayKey? { snapshot?.dayKey }

    // MARK: Lifecycle

    func homeAppeared() async {
        container.appState.isHomeVisible = true
        await load()
        await coordinator.sceneEntered(timeOfDay: container.currentTimeOfDay)
    }

    func homeDisappeared() {
        container.appState.isHomeVisible = false
        coordinator.sceneLeft()
    }

    func load() async {
        isLoading = snapshot == nil
        defer { isLoading = false }
        do {
            let s = try await habitService.homeSnapshot()
            snapshot = s
            container.appState.noteDisplayedDay(s.dayKey)
        } catch {
            errorKey = "error.database"
        }
    }

    /// Called on foreground, timer tick or scene activation: a new local day reloads once and drops stale reactions (QA Q11).
    func checkDayChange() async {
        let today = await habitService.today()
        guard let shown = snapshot?.dayKey, shown != today else { return }
        coordinator.controller.leaveScene()
        undoCandidate = nil
        await load()
        await coordinator.sceneEntered(timeOfDay: container.currentTimeOfDay)
    }

    func refreshTimeOfDay() {
        container.scene.setTimeOfDay(container.currentTimeOfDay, animated: true)
    }

    // MARK: Writes

    func markDone(_ habitId: UUID) async {
        await write(habitId) { try await self.habitService.markDone(habitId: habitId) }
    }

    func markSkipped(_ habitId: UUID) async {
        await write(habitId) { try await self.habitService.markSkipped(habitId: habitId) }
    }

    /// Undo for done (toast) or clearing a rest day; the cat returns to neutral quietly (docs/02 §3).
    func clearStatus(_ habitId: UUID) async {
        undoCandidate = nil
        await write(habitId) { try await self.habitService.undo(habitId: habitId) }
    }

    private func write(_ habitId: UUID, _ operation: @escaping () async throws -> WriteOutcome) async {
        guard !busyHabitIds.contains(habitId) else { return }
        busyHabitIds.insert(habitId)
        errorKey = nil
        defer { busyHabitIds.remove(habitId) }
        do {
            let outcome = try await operation()
            // UI first (docs/02 §3: save → aggregate → UI → cat event)
            await load()
            if outcome.write.newlyCompleted {
                container.haptics.success()
                startUndoWindow(for: habitId)
            } else if outcome.write.changed {
                container.haptics.light()
            }
            coordinator.handle(outcome: outcome, todayRows: snapshot?.rows ?? [])
        } catch HabitServiceError.notScheduled {
            errorKey = "error.unscheduled"
        } catch HabitServiceError.outsideEditableWindow {
            errorKey = "error.editWindow"
        } catch {
            errorKey = "error.save"
            await load() // restore the real state after a failed write (QA Q03)
        }
    }

    private func startUndoWindow(for habitId: UUID) {
        undoTimer?.cancel()
        let candidate = UndoCandidate(habitId: habitId, expiresAt: container.clock.now.addingTimeInterval(HomeViewModel.undoWindow))
        undoCandidate = candidate
        undoTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(HomeViewModel.undoWindow * 1_000_000_000))
            guard !Task.isCancelled, let self, self.undoCandidate == candidate else { return }
            self.undoCandidate = nil
        }
    }

    // MARK: Habit management

    func addHabitTapped() {
        guard let snapshot else { return }
        if snapshot.isAtActiveLimit {
            showLimitExplanation = true
        } else {
            editorTarget = .new
        }
    }

    func edit(_ habit: Habit) {
        editorTarget = .edit(habit)
    }

    func editorFinished() async {
        editorTarget = nil
        await load()
    }

    /// Moves a habit one step within the active habits (docs/02 §2). Reaction priority is unaffected.
    func move(_ habitId: UUID, by offset: Int) async {
        guard let snapshot else { return }
        var ids = snapshot.activeHabits.map(\.id)
        guard let index = ids.firstIndex(of: habitId) else { return }
        let target = index + offset
        guard target >= 0, target < ids.count else { return }
        ids.swapAt(index, target)
        errorKey = nil
        do {
            try await habitService.reorder(ids: ids)
            await load()
        } catch {
            errorKey = "error.save"
        }
    }

    func canMove(_ habitId: UUID, by offset: Int) -> Bool {
        guard let ids = snapshot?.activeHabits.map(\.id), let index = ids.firstIndex(of: habitId) else { return false }
        let target = index + offset
        return target >= 0 && target < ids.count
    }

    func petTapped() {
        coordinator.petTapped()
    }

    // MARK: Presentation helpers

    func progressLine(localizer: Localizer) -> String? {
        guard let p = snapshot?.progress, p.hasSchedule else { return nil }
        var parts = [localizer.t("home.progress", ["done": String(p.done), "total": String(p.scheduled)])]
        if p.skipped > 0 { parts.append(localizer.t("home.restCount", ["count": String(p.skipped)])) }
        return parts.joined(separator: " · ")
    }

    func catAccessibilityValue(localizer: Localizer) -> String {
        switch coordinator.controller.currentClip {
        case .celebrate, .milestone, .pet: return localizer.t("home.catHappy")
        case .greet: return localizer.t("home.catGreeting")
        default: return localizer.t("home.catResting")
        }
    }
}
