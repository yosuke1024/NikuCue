import Foundation
import XCTest
@testable import NikuCueDomain

final class CatReactionEngineTests: XCTestCase {
    let day = Fixtures.day("2026-10-10")
    let t0 = Fixtures.date("2026-10-10T05:00:00Z")

    func snapshot(scheduled: Int = 2, done: Int = 1, skipped: Int = 0, distinct: Int = 1, seen: Set<Int> = [],
                  allDoneShown: Bool = false, greeted: Bool = false) -> ReactionSnapshot {
        ReactionSnapshot(dayKey: day, progress: DayProgress(scheduled: scheduled, done: done, skipped: skipped),
                         distinctDoneDays: distinct, seenMilestones: seen, allDoneShownToday: allDoneShown, greetedToday: greeted)
    }

    func completion(_ category: HabitCategory = .custom, demo: Bool = false, at: TimeInterval = 0) -> CatEvent {
        CatEvent(kind: .completionCommitted, occurredAt: t0.addingTimeInterval(at), dayKey: day, habitId: UUID(), category: category, revision: 1, isDemo: demo)
    }

    func testCategoryAndGenericSelection() {
        var engine = CatReactionEngine(catalog: Fixtures.syntheticCatalog(), seed: 1)
        XCTAssertEqual(engine.intent(for: completion(.water), snapshot: snapshot())?.reactionId, "complete_water")
        XCTAssertEqual(engine.intent(for: completion(.stretch), snapshot: snapshot())?.reactionId, "complete_stretch")
        XCTAssertEqual(engine.intent(for: completion(.read), snapshot: snapshot())?.reactionId, "complete_read")
        XCTAssertEqual(engine.intent(for: completion(.tidy), snapshot: snapshot())?.reactionId, "complete_tidy")
        let generic = engine.intent(for: completion(.custom), snapshot: snapshot())
        XCTAssertEqual(generic?.reactionId, "complete_generic")
        XCTAssertEqual(generic?.clip, .celebrate)
        XCTAssertEqual(generic?.expression, .closedHappy)
        XCTAssertNil(generic?.marksMilestone)
        XCTAssertNil(generic?.marksAllDoneDay)
    }

    func testPriorityOrderMilestoneAllDoneResolvedCategory() {
        var engine = CatReactionEngine(catalog: Fixtures.syntheticCatalog(), seed: 1)
        // all done, no milestone
        let allDone = engine.intent(for: completion(.water), snapshot: snapshot(scheduled: 2, done: 2))
        XCTAssertEqual(allDone?.reactionId, "all_done")
        XCTAssertEqual(allDone?.marksAllDoneDay, day)
        // all done but already shown today → category wins
        XCTAssertEqual(engine.intent(for: completion(.water), snapshot: snapshot(scheduled: 2, done: 2, allDoneShown: true))?.reactionId, "complete_water")
        // all resolved with a skip → settle, never all_done
        let resolved = engine.intent(for: completion(.read), snapshot: snapshot(scheduled: 3, done: 2, skipped: 1))
        XCTAssertEqual(resolved?.reactionId, "all_resolved")
        XCTAssertEqual(resolved?.clip, .settle)
        // milestone beats everything and consumes the all-done token (Q08)
        let milestone = engine.intent(for: completion(.tidy), snapshot: snapshot(scheduled: 2, done: 2, distinct: 7, seen: [3]))
        XCTAssertEqual(milestone?.reactionId, "milestone_7")
        XCTAssertEqual(milestone?.marksMilestone, 7)
        XCTAssertEqual(milestone?.marksAllDoneDay, day)
        XCTAssertEqual(milestone?.clip, .milestone)
        // milestone without all done: only the milestone token
        let m3 = engine.intent(for: completion(.tidy), snapshot: snapshot(scheduled: 2, done: 1, distinct: 3))
        XCTAssertEqual(m3?.marksMilestone, 3)
        XCTAssertNil(m3?.marksAllDoneDay)
        // seen milestone is not repeated
        XCTAssertEqual(engine.intent(for: completion(.tidy), snapshot: snapshot(distinct: 3, seen: [3]))?.reactionId, "complete_tidy")
    }

    func testDemoEventsNeverMarkAnything() {
        var engine = CatReactionEngine(catalog: Fixtures.syntheticCatalog(), seed: 1)
        let intent = engine.intent(for: completion(.water, demo: true), snapshot: snapshot(scheduled: 1, done: 1, distinct: 3))
        XCTAssertEqual(intent?.reactionId, "complete_water")
        XCTAssertNil(intent?.marksMilestone)
        XCTAssertNil(intent?.marksAllDoneDay)
        XCTAssertTrue(intent?.event.isDemo ?? false)
    }

    func testSkipGreetingReturningAndAmbient() {
        var engine = CatReactionEngine(catalog: Fixtures.syntheticCatalog(), seed: 1)
        let skip = engine.intent(for: CatEvent(kind: .skipCommitted, occurredAt: t0, dayKey: day, habitId: UUID(), category: .water), snapshot: snapshot())
        XCTAssertEqual(skip?.reactionId, "rest")
        XCTAssertEqual(skip?.clip, .settle)
        XCTAssertEqual(engine.intent(for: CatEvent(kind: .sceneEntered, occurredAt: t0, dayKey: day), snapshot: snapshot())?.reactionId, "greeting")
        XCTAssertNil(engine.intent(for: CatEvent(kind: .sceneEntered, occurredAt: t0, dayKey: day), snapshot: snapshot(greeted: true)))
        XCTAssertEqual(engine.intent(for: CatEvent(kind: .welcomeBack, occurredAt: t0, dayKey: day), snapshot: snapshot(greeted: true))?.reactionId, "returning")
        XCTAssertEqual(engine.intent(for: CatEvent(kind: .nightAmbient, occurredAt: t0, dayKey: day), snapshot: snapshot())?.clip, .doze)
        XCTAssertEqual(engine.intent(for: CatEvent(kind: .userRequestedEncouragement, occurredAt: t0, dayKey: day), snapshot: snapshot())?.clip, .cheer)
        for kind in [CatEventKind.completionUndone, .historyCorrected, .sceneLeft, .dayChanged, .modalPresented, .modalDismissed] {
            XCTAssertNil(engine.intent(for: CatEvent(kind: kind, occurredAt: t0, dayKey: day), snapshot: snapshot()), "\(kind) is silent")
        }
    }

    func testPetCooldown() {
        var engine = CatReactionEngine(catalog: Fixtures.syntheticCatalog(), seed: 1)
        func pet(_ offset: TimeInterval) -> ReactionIntent? {
            engine.intent(for: CatEvent(kind: .petTapped, occurredAt: t0.addingTimeInterval(offset), dayKey: day), snapshot: snapshot())
        }
        XCTAssertNotNil(pet(0))
        XCTAssertNil(pet(0.5))
        XCTAssertNil(pet(1.99))
        XCTAssertNotNil(pet(2.0))
        XCTAssertNil(pet(3.0))
        XCTAssertNotNil(pet(4.5))
        XCTAssertFalse(pet(10)!.isQueueable)
    }

    func testMessagesAvoidImmediateRepeatsAndAreSeeded() {
        var a = CatReactionEngine(catalog: Fixtures.syntheticCatalog(), seed: 42)
        var b = CatReactionEngine(catalog: Fixtures.syntheticCatalog(), seed: 42)
        var keys: [String] = []
        for i in 0..<12 {
            let ka = a.intent(for: completion(.custom, at: Double(i)), snapshot: snapshot())!.messageKey
            let kb = b.intent(for: completion(.custom, at: Double(i)), snapshot: snapshot())!.messageKey
            XCTAssertEqual(ka, kb, "same seed, same sequence")
            keys.append(ka)
        }
        for i in 2..<keys.count {
            XCTAssertNotEqual(keys[i], keys[i - 1])
            XCTAssertNotEqual(keys[i], keys[i - 2])
        }
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("reaction.complete.") })
        // with a single candidate, repeats are allowed rather than failing
        var c = CatReactionEngine(catalog: Fixtures.syntheticCatalog(), seed: 1)
        let resolved = (0..<3).map { _ in c.intent(for: completion(.custom), snapshot: snapshot(scheduled: 2, done: 1, skipped: 1))!.messageKey }
        XCTAssertEqual(resolved, ["reaction.resolved.1", "reaction.resolved.1", "reaction.resolved.1"])
    }

    func testBundledCatalogIsStructurallyValid() throws {
        let catalog = try Fixtures.catalog()
        let en = try JSONDecoder().decode([String: String].self, from: try RepoFiles.data("NikuCue/Resources/Localization/en.json"))
        XCTAssertEqual(catalog.validate(knownMessageKeys: Set(en.keys)), [])
        XCTAssertEqual(catalog.items.count, 16)
        var engine = CatReactionEngine(catalog: catalog, seed: 3)
        XCTAssertEqual(engine.intent(for: completion(.water), snapshot: snapshot(scheduled: 2, done: 2, distinct: 14, seen: [3, 7]))?.reactionId, "milestone_14")
        XCTAssertEqual(catalog.item(id: "pet")?.when.cooldownMs, CatReactionEngine.petCooldownMs)
        for item in catalog.items {
            XCTAssertEqual(item.clipId.defaultExpression.rawValue, expectedExpression(for: item.clipId), "clip \(item.clipId) expression")
        }
    }

    private func expectedExpression(for clip: ClipID) -> String {
        guard let data = try? RepoFiles.data("NikuCue/Resources/Character/animations.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clips = json["clips"] as? [[String: Any]],
              let match = clips.first(where: { $0["id"] as? String == clip.rawValue }) else { return clip.defaultExpression.rawValue }
        return match["expression"] as? String ?? ""
    }
}

final class ReactionQueueTests: XCTestCase {
    let day = Fixtures.day("2026-10-10")

    func intent(_ id: String, clip: ClipID, habit: UUID = UUID(), revision: Int = 1) -> ReactionIntent {
        let event = CatEvent(kind: .completionCommitted, occurredAt: Date(timeIntervalSince1970: 0), dayKey: day, habitId: habit, category: .custom, revision: revision)
        return ReactionIntent(reactionId: id, clip: clip, expression: clip.defaultExpression, priority: 60, messageKey: "k", textDwellMs: 4000, event: event)
    }

    func testOneRunningOneWaitingLatestWins() { // Q09
        var q = ReactionQueue()
        let a = intent("a", clip: .celebrate), b = intent("b", clip: .celebrate), c = intent("c", clip: .celebrate)
        XCTAssertEqual(q.enqueue(a), .startNow(a))
        XCTAssertEqual(q.enqueue(b), .queued(b))
        XCTAssertEqual(q.enqueue(c), .queued(c))
        XCTAssertEqual(q.waiting, c, "the waiting slot is replaced, never grown")
        XCTAssertEqual(q.finishCurrent { _ in true }, c)
        XCTAssertNil(q.waiting)
        XCTAssertNil(q.finishCurrent { _ in true })
        XCTAssertFalse(q.isBusy)
    }

    func testPetDroppedWhileBusy() {
        var q = ReactionQueue()
        _ = q.enqueue(intent("a", clip: .celebrate))
        XCTAssertEqual(q.enqueue(intent("pet", clip: .pet)), .dropped)
        XCTAssertNil(q.waiting)
        let rest = intent("rest", clip: .settle)
        XCTAssertEqual(q.enqueue(rest), .queued(rest), "settle is queueable")
        XCTAssertEqual(q.enqueue(intent("greet", clip: .greet)), .dropped)
        XCTAssertEqual(q.waiting, rest)
    }

    func testStaleWaitingIsDiscardedAndUndoCancels() { // Q04 / Q11
        var q = ReactionQueue()
        let habit = UUID()
        let a = intent("a", clip: .celebrate, habit: habit)
        let b = intent("b", clip: .celebrate, habit: UUID())
        _ = q.enqueue(a)
        _ = q.enqueue(b)
        XCTAssertTrue(q.cancel { $0.event.habitId == habit }, "running celebration cancelled by undo")
        XCTAssertNil(q.current)
        XCTAssertEqual(q.waiting, b)
        XCTAssertNil(q.finishCurrent { _ in false }, "stale waiting intent discarded by validation")
        XCTAssertNil(q.current)
        _ = q.enqueue(a)
        q.discardAll()
        XCTAssertNil(q.current)
        XCTAssertNil(q.waiting)
    }
}
