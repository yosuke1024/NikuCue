import NikuCueDomain
import SpriteKit
import XCTest
@testable import NikuCue

/// Owner-supplied whole-body textures drive the same rig/controller through `WholeBodyArtProvider`.
@MainActor
final class WholeBodyArtProviderTests: XCTestCase {
    func loadBundled() throws -> (RigSpec, AnimationSpec, WholeBodyPosePack, ArtPaths) {
        let rig = try RigSpec.load(from: try BundledResources.data(named: "mali_wholebody_spec", extension: "json", subdirectory: "Character"))
        let anims = try AnimationSpec.load(from: try BundledResources.data(named: "mali_wholebody_animations", extension: "json", subdirectory: "Character"))
        let pack = try WholeBodyPosePack.load(from: try BundledResources.data(named: "mali_poses", extension: "json", subdirectory: "Character"))
        let paths = try ArtPaths.load(from: try BundledResources.data(named: "mali_paths", extension: "json", subdirectory: "Character"))
        return (rig, anims, pack, paths)
    }

    func solidTexture(_ name: String) -> SKTexture {
        let size = CGSize(width: 32, height: 32)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemBrown.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }

    func testBundledPoseContractsValidate() throws {
        let (rig, anims, pack, _) = try loadBundled()
        XCTAssertEqual(rig.validate(), [])
        XCTAssertEqual(anims.validate(against: rig), [])
        XCTAssertEqual(pack.validate(against: rig), [])
        XCTAssertEqual(Set(rig.expressions), ["idle", "happy", "celebrate", "pet", "sleepy", "sad"])
        XCTAssertEqual(pack.clipPoses["settle"], "idle", "rest never shows a guilt pose")
        XCTAssertEqual(pack.clipPoses["celebrate"], "celebrate")
        XCTAssertEqual(rig.look(for: .closedHappy), "happy")
        XCTAssertEqual(rig.look(for: .sleepy), "sleepy")
        XCTAssertFalse(pack.isProductionArt, "no sign-off yet (R02)")
        XCTAssertEqual(anims.ambient.blink.enabled, false, "no fake blinking from single portraits")
        for clip in anims.clips {
            for track in clip.tracks where track.node == "bodyPivot" && ["scale", "scaleX", "scaleY"].contains(track.property) {
                for k in track.keyframes { XCTAssertLessThanOrEqual(abs((k.v.number ?? 1) - 1), 0.03, "\(clip.id) keeps the artwork undistorted") }
                XCTAssertTrue(clip.loop, "\(clip.id): only ambient loops breathe; a reaction would snap the breath")
            }
            for track in clip.tracks where track.node == "tailPivot" {
                XCTAssertTrue(clip.loop, "\(clip.id): only the idle loop moves the tail")
            }
            if clip.loop {
                XCTAssertFalse((clip.tracks + clip.reducedMotionTracks).contains { $0.property == "expression" },
                               "\(clip.id): an ambient pose track would cancel every linger")
            }
        }
    }

    func testBundledImageSetsLoad() throws {
        let (_, _, pack, paths) = try loadBundled()
        let provider = WholeBodyArtProvider(pack: pack, decorations: VectorArtProvider(paths: paths), bundle: Bundle(for: AppContainer.self))
        for (name, pose) in pack.poses {
            let art = provider.art(for: "pose", look: name, pixelsPerUnit: 1)
            XCTAssertNotNil(art, "image set \(pose.imageSet) must load from the asset catalog")
            if let art {
                XCTAssertEqual(art.size.width, 1024, accuracy: 0.5)
                XCTAssertEqual(art.size.height, 1024, accuracy: 0.5)
                XCTAssertEqual(art.anchorPoint.x, 0.5, accuracy: 0.001)
                XCTAssertGreaterThan(art.anchorPoint.y, 0, "floor anchor sits inside the frame")
            }
        }
        XCTAssertNotNil(provider.art(for: "shadow", look: nil, pixelsPerUnit: 1), "decorations come from the placeholder provider")
        XCTAssertNotNil(provider.art(for: "heart", look: nil, pixelsPerUnit: 1))
        for (name, pose) in pack.poses {
            for (part, layer) in pose.layers ?? [:] {
                let art = provider.art(for: part, look: name, pixelsPerUnit: 1)
                XCTAssertNotNil(art, "layer image set \(layer.imageSet) must load")
                if let art {
                    XCTAssertEqual(art.size.width, layer.bounds[2] - layer.bounds[0], accuracy: 0.5)
                    XCTAssertEqual(art.size.height, layer.bounds[3] - layer.bounds[1], accuracy: 0.5)
                }
            }
        }
    }

    /// The idle tail is its own layer behind the body; other poses carry their painted tail and show no layer.
    func testIdleTailLayerIsSeparateAndSways() throws {
        let (rig, anims, pack, paths) = try loadBundled()
        XCTAssertEqual(pack.layerParts, ["tail"])
        let tail = try XCTUnwrap(pack.poses["idle"]?.layers?["tail"])
        XCTAssertEqual(tail.imageSet, "MaliIdleTail")
        let pivot = try XCTUnwrap(rig.node("tailPivot"))
        XCTAssertEqual(pivot.parent, "bodyPivot")
        XCTAssertEqual(tail.pivot?[0] ?? -1, pivot.position[0], accuracy: 0.5)
        XCTAssertEqual(tail.pivot?[1] ?? -1, pivot.position[1], accuracy: 0.5)
        XCTAssertLessThan(pivot.z, try XCTUnwrap(rig.node("pose")).z, "tail draws behind the body")
        let provider = WholeBodyArtProvider(pack: pack, decorations: VectorArtProvider(paths: paths)) { self.solidTexture($0) }
        XCTAssertTrue(provider.hasVariants("tail"))
        XCTAssertNotNil(provider.art(for: "tail", look: "idle", pixelsPerUnit: 1))
        XCTAssertNil(provider.art(for: "tail", look: "happy", pixelsPerUnit: 1), "happy keeps its painted tail; the layer is empty")
        XCTAssertNil(provider.art(for: "tail", look: nil, pixelsPerUnit: 1))
        let idle = try XCTUnwrap(anims.clip(.idle))
        let sway = try XCTUnwrap(idle.tracks.first { $0.node == "tailPivot" && $0.property == "rotation" })
        XCTAssertLessThanOrEqual(sway.keyframes.map { abs($0.v.number ?? 0) }.max() ?? 0, 8, "sway stays within the cut's tolerance")
        XCTAssertTrue(idle.reducedMotionTracks.isEmpty, "Reduce Motion: no sway, no breathing")
        XCTAssertEqual(idle.durationMs, 14400, "breathing (3.6 s) and sway (4.8 s) share one loop")

        // A reaction interrupting the sway eases the tail back instead of snapping it. The controller's init
        // starts the ambient loop (which resets the rig), so the mid-sway state is seeded after the scene exists;
        // without an SKView the idle actions never advance, so the seeded rotation is what settle() sees.
        let catRig = CatRig(spec: rig, art: provider, pixelsPerUnit: 1)
        let scene = CatScene(size: CGSize(width: 390, height: 260), rig: catRig, library: AnimationLibrary(spec: anims), seed: 1)
        let tailPivot = try XCTUnwrap(catRig.node("tailPivot"))
        let bodyPivot = try XCTUnwrap(catRig.node("bodyPivot"))
        tailPivot.zRotation = 0.08
        bodyPivot.yScale = 1.012
        bodyPivot.position.y += 6
        scene.controller.playDemo(.greet, dayKey: DayKey(string: "2026-10-11")!)
        XCTAssertEqual(scene.controller.currentClip, .greet)
        XCTAssertEqual(tailPivot.zRotation, 0.08, accuracy: 0.0001, "not snapped: eases over the blend")
        XCTAssertNotNil(tailPivot.action(forKey: CatRig.restEaseKey), "eases back over the blend time")
        XCTAssertEqual(bodyPivot.yScale, 1.012, accuracy: 0.0001, "reactions never drive the breathing scale: it eases")
        XCTAssertNotNil(bodyPivot.action(forKey: CatRig.restEaseKey))
        XCTAssertEqual(bodyPivot.position.y, catRig.rest["bodyPivot"]!.position.y, accuracy: 0.0001, "greet drives offsetY: that snaps to rest")
    }

    func testRigCrossFadesPosesWithoutTouchingTheStateMachine() throws {
        let (rig, anims, pack, paths) = try loadBundled()
        var requested: [String] = []
        let provider = WholeBodyArtProvider(pack: pack, decorations: VectorArtProvider(paths: paths)) { name in
            requested.append(name)
            return self.solidTexture(name)
        }
        let catRig = CatRig(spec: rig, art: provider, pixelsPerUnit: 1)
        XCTAssertEqual(catRig.nodes.count, 6, "root, shadow, bodyPivot, tailPivot, tail, pose")
        XCTAssertEqual(catRig.look, "idle")
        XCTAssertFalse(catRig.hasEyeParts)
        let design = try XCTUnwrap(rig.designSize)
        XCTAssertEqual(catRig.designSize, CGSize(width: design[0], height: design[1]), "whole-body rig states its own design frame")
        XCTAssertEqual(catRig.designSize.height, CGFloat(rig.canvas.height), "design height is the frame height (CatScene fit)")
        XCTAssertEqual(catRig.groundY, CGFloat(rig.canvas.rootGroundY))
        catRig.setExpression(.closedHappy, blend: 0)
        XCTAssertEqual(catRig.look, "happy")
        catRig.setLook("sad", blend: 0.18)
        XCTAssertEqual(catRig.look, "sad")
        catRig.setLook("unknownPose", blend: 0)
        XCTAssertEqual(catRig.look, "sad", "unknown looks are ignored")
        XCTAssertEqual(Set(requested), ["MaliIdleBody", "MaliIdleTail", "MaliHappy", "MaliSad"], "textures load lazily per pose and layer")

        let scene = CatScene(size: CGSize(width: 390, height: 260), rig: catRig, library: AnimationLibrary(spec: anims), seed: 1)
        let controller = scene.controller
        XCTAssertEqual(controller.currentClip, .idle)
        let day = DayKey(string: "2026-10-10")!
        controller.playDemo(.celebrate, dayKey: day)
        XCTAssertEqual(controller.currentClip, .celebrate)
        XCTAssertEqual(catRig.look, "celebrate", "clip start applies the t = 0 pose synchronously (no SKView drives actions here)")
        controller.playDemo(.settle, dayKey: day)
        XCTAssertEqual(catRig.look, "idle", "rest shows idle, never sad")
        XCTAssertLessThanOrEqual(controller.activeActionCount, 6)
    }

    // MARK: Timing ("間"): linger after a reaction, a beat before a queued one, the bubble after the motion

    func completion(_ clip: ClipID, key: String) -> ReactionIntent {
        let event = CatEvent(kind: .completionCommitted, occurredAt: Date(), dayKey: DayKey(string: "2026-10-11")!,
                             habitId: UUID(), category: .custom, revision: 1)
        return ReactionIntent(reactionId: clip.rawValue, clip: clip, expression: clip.defaultExpression, priority: 60,
                              messageKey: key, textDwellMs: 4000, event: event)
    }

    func makeScene() throws -> (CatScene, CatRig, AnimationSpec) {
        let (rig, anims, pack, paths) = try loadBundled()
        let provider = WholeBodyArtProvider(pack: pack, decorations: VectorArtProvider(paths: paths)) { self.solidTexture($0) }
        let catRig = CatRig(spec: rig, art: provider, pixelsPerUnit: 1)
        let scene = CatScene(size: CGSize(width: 390, height: 260), rig: catRig, library: AnimationLibrary(spec: anims), seed: 1)
        return (scene, catRig, anims)
    }

    func testReactionLingersAndQueuedReactionWaitsABeat() async throws {
        let (scene, catRig, anims) = try makeScene()
        let controller = scene.controller
        let celebrate = try XCTUnwrap(anims.clip(.celebrate))
        XCTAssertGreaterThan(celebrate.linger, 0, "the happy face stays a moment after the jump")
        XCTAssertGreaterThan(anims.reactionGap, 0, "back-to-back reactions get a breath in between")

        var started: [String] = []
        controller.onReactionStarted = { started.append($0.messageKey) }
        controller.handle(completion(.celebrate, key: "reaction.complete.1"))
        controller.handle(completion(.celebrate, key: "reaction.complete.2"))
        XCTAssertEqual(started, ["reaction.complete.1"])

        // The clip time is over (driven directly: unit tests have no SKView clock).
        let endLook = catRig.look
        controller.finishCurrent()
        XCTAssertEqual(controller.currentClip, .idle, "breathing resumes during the beat")
        XCTAssertTrue(controller.queue.isBusy, "the queued reaction is promoted but not started yet")
        XCTAssertEqual(started, ["reaction.complete.1"], "nothing starts (or is recorded) during the beat")
        XCTAssertEqual(catRig.look, endLook, "the finished look lingers instead of snapping back")
        XCTAssertNotNil(catRig.root.action(forKey: CatSceneController.lingerKey))

        try await Task.sleep(for: .milliseconds(Int(anims.reactionGap * 1000) + 200))
        XCTAssertEqual(started, ["reaction.complete.1", "reaction.complete.2"], "the queued reaction starts after the beat")
        XCTAssertEqual(controller.currentClip, .celebrate)
        XCTAssertNil(catRig.root.action(forKey: CatSceneController.lingerKey), "a new reaction cancels the linger")
    }

    func testUndoDuringTheBeatDropsTheQueuedReaction() async throws {
        let (scene, _, anims) = try makeScene()
        let controller = scene.controller
        var started = 0
        controller.onReactionStarted = { _ in started += 1 }
        let second = completion(.celebrate, key: "reaction.complete.2")
        controller.handle(completion(.celebrate, key: "reaction.complete.1"))
        controller.handle(second)
        controller.finishCurrent()
        controller.cancelReactions(habitId: try XCTUnwrap(second.event.habitId), dayKey: second.event.dayKey)
        try await Task.sleep(for: .milliseconds(Int(anims.reactionGap * 1000) + 200))
        XCTAssertEqual(started, 1, "an undone completion never celebrates")
        XCTAssertFalse(controller.queue.isBusy)
        XCTAssertEqual(controller.currentClip, .idle)
    }

    func testUndoEasesTheCatBackInsteadOfSnapping() throws {
        let (scene, catRig, _) = try makeScene()
        let controller = scene.controller
        let intent = completion(.celebrate, key: "reaction.complete.1")
        controller.handle(intent)
        let bodyPivot = try XCTUnwrap(catRig.node("bodyPivot"))
        let restY = catRig.rest["bodyPivot"]!.position.y
        bodyPivot.position.y = restY + 20                       // mid-hop
        controller.cancelReactions(habitId: try XCTUnwrap(intent.event.habitId), dayKey: intent.event.dayKey)
        XCTAssertEqual(controller.currentClip, .idle)
        XCTAssertEqual(bodyPivot.position.y, restY + 20, accuracy: 0.0001, "no teleport to the floor")
        XCTAssertNotNil(bodyPivot.action(forKey: CatRig.restEaseKey), "the hop eases back down over the blend")
        XCTAssertEqual(catRig.look, "idle", "the face cross-fades back (no sad pose on undo)")
    }

    func testReturningToAFadingLookReversesTheFade() throws {
        let (scene, catRig, _) = try makeScene()
        _ = scene
        let pose = try XCTUnwrap(catRig.node("pose"))
        func front() -> SKSpriteNode? { pose.children.compactMap { $0 as? SKSpriteNode }.first { $0.zPosition > 0.005 } }
        let idleTexture = front()?.texture
        catRig.setLook("happy", blend: 0.18)                   // idle fades out on the back sprite
        XCTAssertEqual(front()?.alpha ?? -1, 0, accuracy: 0.0001)
        catRig.setLook("idle", blend: 0.18)                    // a tap/return lands during that fade
        XCTAssertTrue(front()?.texture === idleTexture, "the fading idle sprite comes back to the front")
        XCTAssertEqual(front()?.alpha ?? -1, 1, accuracy: 0.0001, "from where it was, not from transparent (no ghost blink)")
    }

    func testBubbleFollowsTheMotionExceptUnderReduceMotion() async throws {
        let (scene, _, anims) = try makeScene()
        let controller = scene.controller
        let celebrate = try XCTUnwrap(anims.clip(.celebrate))
        XCTAssertGreaterThan(celebrate.messageDelay, 0)
        controller.handle(completion(.celebrate, key: "reaction.complete.1"))
        XCTAssertNil(controller.messageKey, "the cat reacts first")
        try await Task.sleep(for: .milliseconds(Int(celebrate.messageDelay * 1000) + 200))
        XCTAssertEqual(controller.messageKey, "reaction.complete.1", "then speaks; the dwell starts now")

        controller.playDemo(.idle, dayKey: DayKey(string: "2026-10-11")!)
        controller.reduceMotion = true
        controller.handle(completion(.celebrate, key: "reaction.complete.2"))
        XCTAssertEqual(controller.messageKey, "reaction.complete.2", "Reduce Motion: no motion to wait for")
    }

    func testSelectionPrefersWholeBodyWhenBundled() throws {
        let (_, _, _, paths) = try loadBundled()
        let selection = CharacterArtSelection.resolve(paths: paths, bundle: Bundle(for: AppContainer.self))
        guard case .wholeBody(let provider) = selection else { return XCTFail("app bundle carries mali_poses.json") }
        XCTAssertTrue(provider.artLabel.contains("whole-body"))
        XCTAssertEqual(selection.rigResourceName, "mali_wholebody_spec")
        XCTAssertEqual(selection.animationResourceName, "mali_wholebody_animations")
    }
}
