import NikuCueDomain
import SpriteKit
import XCTest
@testable import NikuCue

/// The production-art seam: textures from a manifest drive the same rig without code changes.
@MainActor
final class TexturePackArtProviderTests: XCTestCase {
    func rigSpec() throws -> RigSpec {
        try RigSpec.load(from: try BundledResources.data(named: "character_spec", extension: "json", subdirectory: "Character"))
    }

    /// A manifest covering every drawable node with 10×10-unit textures, eyes/mouth with all five expressions.
    func fullManifest(rig: RigSpec, pixelsPerUnit: Double = 2) -> TexturePackManifest {
        var parts: [String: TexturePackManifest.Part] = [:]
        for node in rig.nodes where !node.isPivot {
            if ["eyeL", "eyeR", "mouth"].contains(node.id) {
                var variants: [String: TexturePackManifest.Drawing] = [:]
                for e in Expression.allCases {
                    variants[e.rawValue] = TexturePackManifest.Drawing(texture: "\(node.id)_\(e.rawValue)", bounds: [-5, -5, 5, 5])
                }
                parts[node.id] = TexturePackManifest.Part(texture: nil, bounds: nil, variants: variants)
            } else {
                parts[node.id] = TexturePackManifest.Part(texture: node.id, bounds: [-4, -2, 6, 8], variants: nil)
            }
        }
        parts["heart"] = TexturePackManifest.Part(texture: "heart", bounds: [-2, -2, 2, 2], variants: nil)
        return TexturePackManifest(schemaVersion: 1, characterId: "test", isProductionArt: false, status: nil, atlas: nil, folder: nil,
                                   pixelsPerUnit: pixelsPerUnit, parts: parts, license: nil, source: nil)
    }

    func solidTexture(_ name: String, size: CGSize = CGSize(width: 20, height: 20)) -> SKTexture {
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemPink.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }

    func testManifestValidatesAgainstRig() throws {
        let rig = try rigSpec()
        XCTAssertEqual(fullManifest(rig: rig).validate(against: rig), [])
        var broken = fullManifest(rig: rig)
        broken.parts["tail"] = nil
        broken.parts["mouth"]?.variants?["sleepy"] = nil
        broken.parts["body"] = TexturePackManifest.Part(texture: "body", bounds: [5, 0, 1, 1], variants: nil)
        let problems = broken.validate(against: rig)
        XCTAssertTrue(problems.contains("missing part tail"))
        XCTAssertTrue(problems.contains("mouth: missing variant sleepy"))
        XCTAssertTrue(problems.contains { $0.hasPrefix("body/") })
    }

    func testProviderComputesSizeAndAnchorFromBounds() throws {
        let rig = try rigSpec()
        var requested: [String] = []
        let provider = TexturePackArtProvider(manifest: fullManifest(rig: rig)) { name in
            requested.append(name)
            return self.solidTexture(name)
        }
        XCTAssertFalse(provider.isProductionArt)
        XCTAssertTrue(provider.hasVariants("eyeL"))
        XCTAssertFalse(provider.hasVariants("body"))
        let body = try XCTUnwrap(provider.art(for: "body", expression: nil, pixelsPerUnit: 99))
        XCTAssertEqual(body.size, CGSize(width: 10, height: 10))
        XCTAssertEqual(body.anchorPoint.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(body.anchorPoint.y, 0.2, accuracy: 0.0001)
        _ = provider.art(for: "body", expression: nil, pixelsPerUnit: 1)
        XCTAssertEqual(requested.filter { $0 == "body" }.count, 1, "textures are cached")
        let sleepy = try XCTUnwrap(provider.art(for: "eyeL", expression: .sleepy, pixelsPerUnit: 1))
        XCTAssertEqual(sleepy.anchorPoint, CGPoint(x: 0.5, y: 0.5))
        XCTAssertTrue(requested.contains("eyeL_sleepy"))
        XCTAssertNil(provider.art(for: "nonexistent", expression: nil, pixelsPerUnit: 1))
    }

    func testRigBuildsFromTexturePackWithoutCodeChanges() throws {
        let rig = try rigSpec()
        let provider = TexturePackArtProvider(manifest: fullManifest(rig: rig)) { self.solidTexture($0) }
        let catRig = CatRig(spec: rig, art: provider, pixelsPerUnit: 1)
        XCTAssertEqual(catRig.nodes.count, 26)
        let body = try XCTUnwrap(catRig.node("body") as? SKSpriteNode)
        XCTAssertNotNil(body.texture)
        XCTAssertEqual(body.size, CGSize(width: 10, height: 10))
        catRig.setExpression(.closedHappy, blend: 0)
        XCTAssertEqual(catRig.expression, .closedHappy)
        XCTAssertNotNil(catRig.makeHeart())
    }

    func testMissingTextureYieldsNoArtInsteadOfCrash() throws {
        let rig = try rigSpec()
        let provider = TexturePackArtProvider(manifest: fullManifest(rig: rig)) { name in name == "tail" ? nil : self.solidTexture(name) }
        XCTAssertNil(provider.art(for: "tail", expression: nil, pixelsPerUnit: 1))
        let catRig = CatRig(spec: rig, art: provider, pixelsPerUnit: 1)
        let tail = try XCTUnwrap(catRig.node("tail") as? SKSpriteNode)
        XCTAssertNil(tail.texture)
        XCTAssertEqual(tail.size, .zero)
    }

    func testSelectionFallsBackToPlaceholderWithoutBundledPack() throws {
        let paths = try ArtPaths.load(from: try BundledResources.data(named: "mali_paths", extension: "json", subdirectory: "Character"))
        let selection = CharacterArtSelection.resolve(paths: paths, bundle: Bundle(for: TexturePackArtProviderTests.self))
        if case .placeholder(let p) = selection {
            XCTAssertFalse(p.isProductionArt)
            XCTAssertTrue(p.artLabel.contains("placeholder"))
        } else {
            XCTFail("test bundle has no texture pack; placeholder expected")
        }
    }
}
