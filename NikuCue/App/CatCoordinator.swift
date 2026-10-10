import Foundation
import NikuCueDomain

/// P06 wiring between the habit service, the pure reaction engine and the scene controller.
///
/// Event → `CatReactionEngine.intent` → `CatSceneController.handle`. When a reaction actually starts
/// the milestone / all-done tokens are recorded through `HabitService.markShown`; before a waiting
/// reaction starts it is re-validated against the current records (docs/05 §4–§5).
@MainActor
final class CatCoordinator {
    let scene: CatScene
    private let habitService: HabitService
    private let clock: any Clock
    private var engine: CatReactionEngine
    /// Latest committed records for today, used to re-validate queued intents.
    private var latestRecords: [UUID: HabitDayRecord] = [:]
    private var latestDay: DayKey?

    init(scene: CatScene, habitService: HabitService, catalog: ReactionCatalog, clock: any Clock) {
        self.scene = scene
        self.habitService = habitService
        self.clock = clock
        self.engine = CatReactionEngine(catalog: catalog)
        scene.controller.onReactionStarted = { [weak self] intent in
            guard let self, !intent.event.isDemo else { return }
            let milestone = intent.marksMilestone
            let allDone = intent.marksAllDoneDay
            guard milestone != nil || allDone != nil else { return }
            Task { try? await self.habitService.markShown(milestone: milestone, allDoneDay: allDone) }
        }
        scene.controller.isStillValid = { [weak self] intent in
            guard let self else { return false }
            return self.isStillValid(intent)
        }
    }

    var controller: CatSceneController { scene.controller }

    /// Routes a write outcome: undo cancels, completion/skip react, history corrections stay silent.
    func handle(outcome: WriteOutcome, todayRows: [HomeHabitRow]) {
        latestDay = outcome.snapshot.dayKey
        latestRecords = Dictionary(uniqueKeysWithValues: todayRows.compactMap { row in row.record.map { (row.id, $0) } })
        guard let event = outcome.event else { return }
        if event.kind == .completionUndone, let habitId = event.habitId {
            controller.cancelReactions(habitId: habitId, dayKey: event.dayKey)
            return
        }
        dispatch(event, snapshot: outcome.snapshot)
    }

    func dispatch(_ event: CatEvent, snapshot: ReactionSnapshot) {
        guard let intent = engine.intent(for: event, snapshot: snapshot) else { return }
        controller.handle(intent)
    }

    /// Home appeared in the foreground: greeting / welcome back and the ambient state for the hour.
    func sceneEntered(timeOfDay: TimeOfDay) async {
        scene.setTimeOfDay(timeOfDay, animated: false)
        controller.enterScene(ambient: timeOfDay.ambient, owner: "home")
        if let (event, snapshot) = try? await habitService.sceneEntered() {
            latestDay = snapshot.dayKey
            dispatch(event, snapshot: snapshot)
        }
    }

    func sceneLeft() {
        controller.leaveScene(owner: "home")
    }

    func dispatchDemo(kind: CatEventKind, category: HabitCategory? = nil) {
        let day = CalendarService(clock: clock).dayKey(for: clock.now)
        let event = CatEvent(kind: kind, occurredAt: clock.now, dayKey: day, category: category, isDemo: true)
        dispatch(event, snapshot: .demo(dayKey: day))
    }

    func petTapped() {
        let day = CalendarService(clock: clock).dayKey(for: clock.now)
        let event = CatEvent(kind: .petTapped, occurredAt: clock.now, dayKey: day)
        let snapshot = ReactionSnapshot(dayKey: day, progress: .empty, distinctDoneDays: 0, seenMilestones: [], allDoneShownToday: true, greetedToday: true)
        dispatch(event, snapshot: snapshot)
    }

    /// A waiting intent is valid only if it belongs to today and its record still exists with the same revision.
    private func isStillValid(_ intent: ReactionIntent) -> Bool {
        if intent.event.isDemo { return true }
        guard let latestDay, intent.event.dayKey == latestDay else { return false }
        switch intent.event.kind {
        case .completionCommitted:
            guard let habitId = intent.event.habitId, let record = latestRecords[habitId] else { return false }
            return record.status == .done && record.revision == intent.event.revision
        case .skipCommitted:
            guard let habitId = intent.event.habitId, let record = latestRecords[habitId] else { return false }
            return record.status == .skipped
        default:
            return true
        }
    }
}
