import Combine
import Foundation
import NikuCueDomain
import SwiftUI

/// One day's breakdown and its corrections (docs/02 §3–§4). Writes go through `HabitService.setStatus`
/// and get only the ordinary "Saved" feedback: no haptics, no cat reaction, no welcome-back event.
/// The cat coordinator is deliberately never called from here.
@MainActor
final class DayDetailViewModel: ObservableObject {
    let day: DayKey

    @Published private(set) var summary: DaySummary?
    @Published private(set) var isLoading = false
    /// Localization key of the error to show (`error.editWindow`, `error.unscheduled`, `error.save`, `error.database`).
    @Published var errorKey: String?
    /// Brief "Saved" indicator after a successful correction.
    @Published private(set) var showSaved = false
    /// Habit ids whose write is in flight, so a double tap cannot start a second write (QA Q02).
    @Published private(set) var busyHabitIds: Set<UUID> = []

    static let savedIndicatorDuration: TimeInterval = 2

    private let container: AppContainer
    private var savedTimer: Task<Void, Never>?

    init(container: AppContainer, day: DayKey) {
        self.container = container
        self.day = day
    }

    var isEditable: Bool { summary?.isEditable ?? false }

    func load() async {
        isLoading = summary == nil
        defer { isLoading = false }
        do {
            summary = try await container.habitService.daySummary(day)
        } catch {
            errorKey = "error.database"
        }
    }

    /// Applies a correction for one habit on this day. The outcome's cat event (if any) is intentionally dropped.
    func apply(_ desired: DesiredStatus, to habitId: UUID) async {
        guard !busyHabitIds.contains(habitId) else { return }
        busyHabitIds.insert(habitId)
        errorKey = nil
        defer { busyHabitIds.remove(habitId) }
        do {
            _ = try await container.habitService.setStatus(habitId: habitId, day: day, desired: desired)
            await load()
            flashSaved()
        } catch HabitServiceError.outsideEditableWindow {
            errorKey = "error.editWindow"
            await load() // the window may have moved past midnight; show the real state
        } catch HabitServiceError.futureDay {
            errorKey = "error.editWindow"
            await load()
        } catch HabitServiceError.notScheduled {
            errorKey = "error.unscheduled"
            await load()
        } catch {
            errorKey = "error.save"
            await load() // restore the real state after a failed write (QA Q03)
        }
    }

    /// Progress of this day in the same wording as Home: done / scheduled, resting counted separately.
    func progressLine(localizer: Localizer) -> String? {
        guard let progress = summary?.progress, progress.hasSchedule else { return nil }
        var parts = [localizer.t("home.progress", ["done": String(progress.done), "total": String(progress.scheduled)])]
        if progress.skipped > 0 {
            parts.append(localizer.t("home.restCount", ["count": String(progress.skipped)]))
        }
        return parts.joined(separator: " · ")
    }

    private func flashSaved() {
        savedTimer?.cancel()
        showSaved = true
        savedTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(DayDetailViewModel.savedIndicatorDuration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.showSaved = false
        }
    }
}
