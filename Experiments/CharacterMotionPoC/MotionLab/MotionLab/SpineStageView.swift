import CatBehavior
import Combine
import QuartzCore
import SpineiOS
import SpineSwift
import SwiftUI

/// Applies the engine's `RenderState` to a spine-ios skeleton once per frame:
///  - the animation advances by the engine's own step (`StageModel.lastEngineStep`), never by spine-ios's frame
///    delta: `SpineView` resets that clock whenever SwiftUI updates the view with an `isRendering` binding
///    (`SpineUIView.isRendering` sets `renderer.lastDraw`), which on the Simulator left the clips lagging the
///    engine (up to 48 ms) and the feet sliding;
///  - track 0: the base clip (a new serial starts it with its mix; a stopping walk is frozen while it blends out),
///    with the engine's playback rate, so the walk cycle and the root movement stay locked together;
///  - track 1: the "look at" overlay, aimed by moving the skeleton's IK target bone to the gaze point;
///  - skeleton x / scaleX: the root position and facing.
/// The driver never decides anything; it only mirrors the engine.
@MainActor
final class SpineDriver: ObservableObject {
    private final class Box {
        weak var driver: SpineDriver?
    }

    let controller: SpineController
    private let model: StageModel
    private var lastBaseSerial = -1
    private var lastLookSerial = -1
    private var lookActive = false
    private var crosshair: Bone?
    private var crosshairSlot: Slot?
    private var feet: [(id: String, bone: Bone)] = []
    /// Leg IK targets (children of the root): pinned by the foot planter during clip blends.
    private var footTargets: [Bone] = []
    private var planter = FootPlanter(groundTolerance: 17.2)
    @Published private(set) var loaded = false

    init(model: StageModel) {
        self.model = model
        let box = Box()
        controller = SpineController(
            onInitialized: { c in SpineDriver.onMain { box.driver?.initialized(c) } },
            onBeforeUpdateWorldTransforms: { c in SpineDriver.onMain { box.driver?.beforeUpdate(c) } },
            onAfterUpdateWorldTransforms: { c in SpineDriver.onMain { box.driver?.afterUpdate(c) } }
        )
        box.driver = self
    }

    /// spine-ios calls back from MTKView drawing, which runs on the main thread.
    nonisolated private static func onMain(_ work: @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.sync { MainActor.assumeIsolated { work() } }
        }
    }

    private func initialized(_ c: SpineController) {
        c.skeleton.scaleX = 1
        c.skeleton.scaleY = 1
        c.animationStateData.defaultMix = 0.2
        crosshair = c.skeleton.findBone("crosshair")
        crosshairSlot = c.skeleton.findSlot("crosshair")
        feet = [("front", "front-foot-tip"), ("rear", "back-foot-tip")].compactMap { id, name in
            c.skeleton.findBone(name).map { (id: id, bone: $0) }
        }
        footTargets = ["front-foot-target", "rear-foot-target"].compactMap { c.skeleton.findBone($0) }
        // Pick up wherever the engine is (also after switching renderers mid-session).
        let s = model.state
        let entry = c.animationState.setAnimation(0, s.base.clip, s.base.loop)
        entry.trackTime = Float(s.baseClipTime)
        lastBaseSerial = s.base.serial
        apply(s, to: c, startClips: false)
        c.animationState.timeScale = 0           // spine-ios's own update only applies the state (see beforeUpdate)
        loaded = true
    }

    private func beforeUpdate(_ c: SpineController) {
        guard loaded else { return }
        let s = model.tick(now: CACurrentMediaTime())
        apply(s, to: c, startClips: true)
        // spine-ios calls AnimationState.update(its delta) and apply right after this callback: advance the state
        // here by the engine's step and leave the global timeScale at 0 so that update adds nothing.
        let state = c.animationState
        state.timeScale = 1
        state.update(Float(model.lastEngineStep))
        state.timeScale = 0
    }

    private func apply(_ s: RenderState, to c: SpineController, startClips: Bool) {
        let state = c.animationState
        if startClips, s.base.serial != lastBaseSerial {
            if s.base.freezePrevious, let current = state.getTrack(0) { current.timeScale = 0 }
            let entry = state.setAnimation(0, s.base.clip, s.base.loop)
            entry.setMixDuration = Float(s.base.mix)
            entry.trackTime = Float(s.base.startTime)
            lastBaseSerial = s.base.serial
        }
        state.getTrack(0)?.timeScale = Float(s.baseTimeScale)
        c.skeleton.x = Float(s.x)
        c.skeleton.y = 0
        c.skeleton.scaleX = Float(s.facing.sign)

        if let look = s.look {
            if !lookActive || look.serial != lastLookSerial {
                let entry: TrackEntry
                if state.getTrack(1) != nil {
                    entry = state.setAnimation(1, look.clip, true)          // blends from whatever is fading out
                } else {
                    _ = state.setEmptyAnimation(1, 0)                         // fade in from "no overlay"
                    entry = state.addAnimation(1, look.clip, true, 0)
                }
                entry.setMixDuration = Float(look.mixIn)
                entry.alpha = Float(look.alpha)
                lastLookSerial = look.serial
                lookActive = true
            }
            // the crosshair bone is a child of the root: local = offset from the root, mirrored with the facing
            if let crosshair {
                crosshair.pose.x = Float((look.target.x - s.x) * s.facing.sign)
                crosshair.pose.y = Float(look.target.y)
            }
        } else if lookActive {
            _ = state.setEmptyAnimation(1, Float(s.lookOutMix))
            lookActive = false
        }
    }

    private func afterUpdate(_ c: SpineController) {
        guard loaded else { return }
        if model.config.footPlanting, footTargets.count == 2 { plantFeet(c) }
        // the sample's aim pose shows a crosshair; the look-at should not
        if let slot = crosshairSlot { _ = slot.appliedPose.color.set(1, 1, 1, 0) }
        var positions: [String: (x: Double, y: Double)] = [:]
        for (id, bone) in feet {
            positions[id] = (Double(bone.appliedPose.worldX), Double(bone.appliedPose.worldY))
        }
        model.diagnostics.feet(positions, state: model.state)
        if let entry = c.animationState.getTrack(0), model.state.base.serial == lastBaseSerial {
            model.diagnostics.drift(engineClipTime: model.state.baseClipTime, rendererTrackTime: Double(entry.trackTime),
                                    mode: model.state.mode)
        }
    }
}

extension SpineDriver {
    /// Foot planting: keep a grounded foot where it is while two clips blend, then step it (CatBehavior.FootPlanter).
    /// Runs after the animation was applied: override the IK targets, recompute world transforms, restore the
    /// animated pose so the next frame starts from the animation again.
    fileprivate func plantFeet(_ c: SpineController) {
        let s = model.state
        let sign = s.facing.sign
        let animated = footTargets.map { Point(x: s.x + sign * Double($0.pose.x), y: Double($0.pose.y)) }
        let planted = planter.solve(animated, state: s)
        for (i, bone) in footTargets.enumerated() {
            bone.pose.x = Float((planted[i].x - s.x) * sign)
            bone.pose.y = Float(planted[i].y)
        }
        c.skeleton.updateWorldTransform(.pose)
        for (i, bone) in footTargets.enumerated() {
            bone.pose.x = Float((animated[i].x - s.x) * sign)
            bone.pose.y = Float(animated[i].y)
        }
    }
}

struct SpineStageView: View {
    /// Not observed: the HUD publishes several times a second and every body update reaches `updateUIView`.
    let model: StageModel
    @StateObject private var driver: SpineDriver
    @State private var isRendering: Bool? = true

    init(model: StageModel) {
        self.model = model
        _driver = StateObject(wrappedValue: SpineDriver(model: model))
    }

    var body: some View {
        SpineView(
            from: .bundle(atlasFileName: "spineboy-pma.atlas", skeletonFileName: "spineboy-pro.skel"),
            controller: driver.controller,
            mode: .fit,
            alignment: .center,
            // the view shows exactly the stage, so stage units map to points with one uniform scale
            boundsProvider: RawBounds(x: model.stage.minX, y: -model.floorDepth,
                                      width: model.stage.maxX - model.stage.minX, height: model.stage.height + model.floorDepth),
            backgroundColor: .clear,
            isRendering: $isRendering
        )
        .onReceive(model.$isActive.removeDuplicates().dropFirst()) { active in
            // stop the Metal view in the background; turning it back on resets its frame clock (no catch-up jump)
            isRendering = active
            if active { driver.controller.resume() } else { driver.controller.pause() }
        }
        .onDisappear { driver.controller.dispose() }
    }
}
