import NikuCueDomain
import SpriteKit
import XCTest
@testable import NikuCue

/// Queue, cancel and action-count behaviour of the scene controller (QA Q09, Q04, Q22, Q40).
@MainActor
final class CatSceneControllerTests: XCTestCase {
    var scene: CatScene!
    var controller: CatSceneController { scene.controller }
    let day = DayKey(string: "2026-10-10")!

    override func setUp() async throws {
        let rig = try RigSpec.load(from: try BundledResources.data(named: "character_spec", extension: "json", subdirectory: "Character"))
        let art = try ArtPaths.load(from: try BundledResources.data(named: "mali_paths", extension: "json", subdirectory: "Character"))
        let anims = try AnimationSpec.load(from: try BundledResources.data(named: "animations", extension: "json", subdirectory: "Character"))
        let catRig = CatRig(spec: rig, art: VectorArtProvider(paths: art), pixelsPerUnit: 0.5)
        scene = CatScene(size: CGSize(width: 390, height: 260), rig: catRig, library: AnimationLibrary(spec: anims), seed: 1)
    }

    func intent(_ clip: ClipID, habit: UUID = UUID(), key: String = "reaction.complete.1") -> ReactionIntent {
        let event = CatEvent(kind: .completionCommitted, occurredAt: Date(), dayKey: day, habitId: habit, category: .custom, revision: 1)
        return ReactionIntent(reactionId: clip.rawValue, clip: clip, expression: clip.defaultExpression, priority: 60,
                              messageKey: key, textDwellMs: 4000, event: event)
    }

    func testStartsIdleAndRunsOneInteractionAtATime() {
        XCTAssertEqual(controller.currentClip, .idle)
        let baseline = controller.activeActionCount
        XCTAssertGreaterThan(baseline, 0, "idle breathing is running")
        var started: [String] = []
        controller.onReactionStarted = { started.append($0.reactionId) }
        controller.handle(intent(.celebrate))
        controller.handle(intent(.celebrate, key: "reaction.complete.2"))
        controller.handle(intent(.settle, key: "reaction.rest.1"))
        XCTAssertEqual(controller.currentClip, .celebrate)
        XCTAssertEqual(controller.queue.waiting?.clip, .settle, "latest queued reaction replaces the earlier one")
        XCTAssertEqual(started, ["celebrate"])
        XCTAssertEqual(controller.messageKey, "reaction.complete.1")
    }

    func testUndoCancelsRunningCelebrationWithoutSadness() {
        let habit = UUID()
        controller.handle(intent(.celebrate, habit: habit))
        XCTAssertEqual(controller.currentClip, .celebrate)
        controller.cancelReactions(habitId: habit, dayKey: day)
        XCTAssertEqual(controller.currentClip, .idle)
        XCTAssertNil(controller.messageKey)
        XCTAssertFalse(controller.queue.isBusy)
    }

    func testLeaveSceneDiscardsQueueAndPauses() {
        controller.handle(intent(.celebrate))
        controller.handle(intent(.milestone))
        controller.leaveScene()
        XCTAssertFalse(controller.queue.isBusy)
        XCTAssertNil(controller.queue.waiting)
        XCTAssertTrue(controller.isPaused)
        controller.handle(intent(.celebrate))
        XCTAssertFalse(controller.queue.isBusy, "paused controller ignores reactions")
        controller.enterScene(ambient: .idle)
        XCTAssertFalse(controller.isPaused)
        XCTAssertEqual(controller.currentClip, .idle)
    }

    func testRapidDemoPlaysKeepActionCountBounded() {
        var counts: [Int] = []
        for _ in 0..<120 {
            controller.playDemo(.pet, dayKey: day)
            controller.playDemo(.celebrate, dayKey: day)
            counts.append(controller.activeActionCount)
        }
        XCTAssertLessThanOrEqual(counts.max() ?? 0, 24, "actions never accumulate across restarts")
        controller.playDemo(.idle, dayKey: day)
        XCTAssertEqual(controller.currentClip, .idle)
        XCTAssertEqual(scene.rig.root.children.count, scene.rig.root.children.filter { $0.name != nil }.count, "no leftover heart nodes")
    }

    func testReduceMotionUsesReducedTracks() {
        controller.reduceMotion = true
        controller.handle(intent(.celebrate))
        XCTAssertEqual(controller.currentClip, .celebrate)
        XCTAssertLessThanOrEqual(controller.activeActionCount, 3, "reduced motion runs only the expression track")
    }

    func testTimeOfDayChangesRoomAndAmbient() {
        scene.setTimeOfDay(.night, animated: false)
        XCTAssertEqual(controller.ambient, .dozing)
        XCTAssertEqual(controller.currentClip, .doze)
        scene.setTimeOfDay(.morning, animated: false)
        XCTAssertEqual(controller.currentClip, .idle)
    }
}
