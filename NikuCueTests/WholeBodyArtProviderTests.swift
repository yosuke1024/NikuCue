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

        // A reaction interrupting the sway eases the tail back instead of snapping it.
        let catRig = CatRig(spec: rig, art: provider, pixelsPerUnit: 1)
        let tailPivot = try XCTUnwrap(catRig.node("tailPivot"))
        tailPivot.zRotation = 0.08
        let scene = CatScene(size: CGSize(width: 390, height: 260), rig: catRig, library: AnimationLibrary(spec: anims), seed: 1)
        scene.controller.playDemo(.greet, dayKey: DayKey(string: "2026-10-11")!)
        XCTAssertEqual(tailPivot.zRotation, 0.08, accuracy: 0.0001, "not snapped")
        XCTAssertNotNil(tailPivot.action(forKey: CatRig.restEaseKey), "eases back over the blend time")
        XCTAssertNil(try XCTUnwrap(catRig.node("bodyPivot")).action(forKey: CatRig.restEaseKey), "driven nodes snap instead")
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

    func testSelectionPrefersWholeBodyWhenBundled() throws {
        let (_, _, _, paths) = try loadBundled()
        let selection = CharacterArtSelection.resolve(paths: paths, bundle: Bundle(for: AppContainer.self))
        guard case .wholeBody(let provider) = selection else { return XCTFail("app bundle carries mali_poses.json") }
        XCTAssertTrue(provider.artLabel.contains("whole-body"))
        XCTAssertEqual(selection.rigResourceName, "mali_wholebody_spec")
        XCTAssertEqual(selection.animationResourceName, "mali_wholebody_animations")
    }
}
