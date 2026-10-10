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
    }

    func testRigCrossFadesPosesWithoutTouchingTheStateMachine() throws {
        let (rig, anims, pack, paths) = try loadBundled()
        var requested: [String] = []
        let provider = WholeBodyArtProvider(pack: pack, decorations: VectorArtProvider(paths: paths)) { name in
            requested.append(name)
            return self.solidTexture(name)
        }
        let catRig = CatRig(spec: rig, art: provider, pixelsPerUnit: 1)
        XCTAssertEqual(catRig.nodes.count, 4)
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
        XCTAssertEqual(Set(requested), ["MaliIdle", "MaliHappy", "MaliSad"], "textures load lazily per pose")

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
