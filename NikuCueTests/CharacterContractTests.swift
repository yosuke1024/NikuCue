import NikuCueDomain
import SpriteKit
import XCTest
@testable import NikuCue

/// Validates the bundled rig/animation/art contracts as the app loads them (docs/06 §8, P02 acceptance).
/// Runs in the host app on Simulator; not executed on Linux.
@MainActor
final class CharacterContractTests: XCTestCase {
    func loadSpecs() throws -> (RigSpec, ArtPaths, AnimationSpec) {
        let rig = try RigSpec.load(from: try BundledResources.data(named: "character_spec", extension: "json", subdirectory: "Character"))
        let art = try ArtPaths.load(from: try BundledResources.data(named: "mali_paths", extension: "json", subdirectory: "Character"))
        let anims = try AnimationSpec.load(from: try BundledResources.data(named: "animations", extension: "json", subdirectory: "Character"))
        return (rig, art, anims)
    }

    func testContractsLoadAndValidate() throws {
        let (rig, art, anims) = try loadSpecs()
        XCTAssertEqual(rig.nodes.count, 26)
        XCTAssertEqual(rig.validate(), [])
        XCTAssertEqual(anims.validate(against: rig), [])
        XCTAssertEqual(anims.clips.count, 8)
        XCTAssertFalse(art.isProductionArt, "prototype art must stay flagged until human approval (R02)")
        for node in rig.nodes where !node.isPivot {
            XCTAssertNotNil(art.parts[node.id], "no art for \(node.id)")
        }
        for id in ClipID.allCases {
            XCTAssertEqual(anims.clip(id)?.defaultExpression, id.defaultExpression, "expression mismatch for \(id)")
        }
    }

    func testEveryPartRendersAtTwoDensities() throws {
        let (rig, art, _) = try loadSpecs()
        let provider = VectorArtProvider(paths: art)
        for density in [CGFloat(0.5), 1.0] {
            for node in rig.nodes where !node.isPivot {
                let expressions: [Expression?] = provider.hasVariants(node.id) ? Expression.allCases : [nil]
                for e in expressions {
                    let part = provider.art(for: node.id, expression: e, pixelsPerUnit: density)
                    XCTAssertNotNil(part, "\(node.id)/\(e.map(\.rawValue) ?? "-") at \(density)")
                    if let part {
                        XCTAssertGreaterThan(part.size.width, 0)
                        XCTAssertGreaterThan(part.size.height, 0)
                        XCTAssertTrue((0...1).contains(part.anchorPoint.x) && (0...1).contains(part.anchorPoint.y), "anchor inside texture for \(node.id)")
                    }
                }
            }
        }
        XCTAssertNotNil(provider.art(for: "heart", expression: nil, pixelsPerUnit: 1))
    }

    func testRigBuildsHierarchyAndRestoresRest() throws {
        let (spec, art, anims) = try loadSpecs()
        let rig = CatRig(spec: spec, art: VectorArtProvider(paths: art), pixelsPerUnit: 0.5)
        XCTAssertEqual(rig.nodes.count, 26)
        XCTAssertEqual(rig.node("earL")?.parent, rig.node("earLPivot"))
        XCTAssertEqual(rig.node("headPivot")?.parent, rig.node("bodyPivot"))
        XCTAssertEqual(rig.node("tail")?.parent, rig.node("tailPivot"))
        XCTAssertEqual(rig.node("shadow")?.parent, rig.root)
        // ears draw behind the head, paws in front of the body
        XCTAssertLessThan(rig.node("earL")!.zPosition, rig.node("head")!.zPosition)
        XCTAssertGreaterThan(rig.node("forePawL")!.parent!.zPosition, rig.node("body")!.zPosition)

        let head = rig.node("headPivot")!
        let restPosition = head.position
        head.position.y += 40
        head.zRotation = 0.3
        rig.resetToRest()
        XCTAssertEqual(head.position, restPosition)
        XCTAssertEqual(head.zRotation, 0)

        rig.setExpression(.closedHappy, blend: 0)
        XCTAssertEqual(rig.expression, .closedHappy)
        rig.setExpression(.sleepy, blend: anims.expressionBlend)
        XCTAssertEqual(rig.expression, .sleepy)
    }

    func testLibraryBuildsOneKeyedActionPerTrack() throws {
        let (spec, art, anims) = try loadSpecs()
        let rig = CatRig(spec: spec, art: VectorArtProvider(paths: art), pixelsPerUnit: 0.5)
        let library = AnimationLibrary(spec: anims)
        for clip in anims.clips {
            let actions = library.actions(for: clip, reducedMotion: false, rig: rig)
            XCTAssertEqual(actions.count, clip.tracks.count, clip.id)
            XCTAssertEqual(Set(actions.map(\.key)).count, actions.count, "keys unique in \(clip.id)")
            let reduced = library.actions(for: clip, reducedMotion: true, rig: rig)
            XCTAssertEqual(reduced.count, clip.reducedMotionTracks.count, clip.id)
        }
        var rng = SeededRandomNumberGenerator(seed: 1)
        let interval = library.nextBlinkInterval(using: &rng)
        XCTAssertTrue((4.0...7.0).contains(interval))
    }

    func testKeyframeSamplerMatchesPreview() {
        let track = AnimationSpec.Track(node: "bodyPivot", property: "offsetY", keyframes: [
            .init(t: 0, v: .number(0), ease: nil), .init(t: 140, v: .number(0), ease: "easeIn"),
            .init(t: 420, v: .number(34), ease: "easeOut"), .init(t: 680, v: .number(0), ease: "easeIn"),
        ])
        XCTAssertEqual(KeyframeSampler.number(track, at: -5), 0)
        XCTAssertEqual(KeyframeSampler.number(track, at: 420), 34)
        XCTAssertEqual(KeyframeSampler.number(track, at: 280)!, 34 * (1 - pow(1 - 0.5, 2)), accuracy: 0.001)
        XCTAssertEqual(KeyframeSampler.number(track, at: 1000), 0)
        let expr = AnimationSpec.Track(node: "face", property: "expression", keyframes: [
            .init(t: 0, v: .name("softSmile"), ease: nil), .init(t: 680, v: .name("closedHappy"), ease: nil),
        ])
        XCTAssertEqual(KeyframeSampler.name(expr, at: 100), "softSmile")
        XCTAssertEqual(KeyframeSampler.name(expr, at: 680), "closedHappy")
    }
}
