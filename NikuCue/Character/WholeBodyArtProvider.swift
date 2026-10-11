import Foundation
import NikuCueDomain
import SpriteKit
import UIKit

/// `mali_poses.json`: owner-supplied whole-body textures, one per pose, cross-faded by the rig
/// (docs/assets/mali_v1_1/README.md). This is an interim treatment: no part is independently movable, so no
/// blink, tail or limb motion is synthesised from these images.
struct WholeBodyPosePack: Decodable, Sendable {
    /// An independently movable layer cut from a pose image (e.g. the idle tail), drawn by its own rig node.
    struct Layer: Decodable, Sendable {
        var imageSet: String
        /// [minX, minY, maxX, maxY] in design units relative to the layer's pivot node origin, y up.
        var bounds: [Double]
        /// Pivot position relative to the floor centre (documentation; the rig node carries the same value).
        var pivot: [Double]?
    }

    struct Pose: Decodable, Sendable {
        /// Asset catalog image set name (e.g. `MaliIdle`).
        var imageSet: String
        /// [minX, minY, maxX, maxY] in design units relative to the node origin (floor centre), y up.
        var bounds: [Double]
        /// Layer part id (e.g. `tail`) → layer art shown with this pose; poses without an entry show nothing there.
        var layers: [String: Layer]?
    }

    var schemaVersion: Int
    var characterId: String
    var isProductionArt: Bool
    var status: String?
    var pixelsPerUnit: Double
    var frame: [Double]
    var poses: [String: Pose]
    /// Clip id → pose shown when the clip starts (asset manifest `states`).
    var clipPoses: [String: String]
    /// Engine expression → pose.
    var expressionMap: [String: String]
    var optionalPoses: [String]?
    /// Poses that must never be shown for skipped/paused habits (asset README: `sad` is not a guilt cue).
    var neverShowOnSkip: [String]?
    /// Rig part ids served from `Pose.layers` (currently `tail`). Each needs a `<part>Pivot` parent node in the rig.
    var layerParts: [String]?
    var license: String?
    var source: String?

    static let resourceName = "mali_poses"
    static let posePartId = "pose"

    static func load(from data: Data) throws -> WholeBodyPosePack {
        try JSONDecoder().decode(WholeBodyPosePack.self, from: data)
    }

    func validate(against rig: RigSpec) -> [String] {
        var problems: [String] = []
        if pixelsPerUnit <= 0 { problems.append("pixelsPerUnit must be positive") }
        for look in rig.expressions where poses[look] == nil { problems.append("missing pose \(look)") }
        for (name, pose) in poses {
            if pose.bounds.count != 4 || pose.bounds[0] >= pose.bounds[2] || pose.bounds[1] >= pose.bounds[3] { problems.append("\(name): invalid bounds") }
            if pose.imageSet.isEmpty { problems.append("\(name): empty imageSet") }
        }
        for id in ClipID.allCases {
            guard let pose = clipPoses[id.rawValue] else { problems.append("clipPoses lacks \(id.rawValue)"); continue }
            if poses[pose] == nil { problems.append("clipPoses maps \(id.rawValue) to unknown pose \(pose)") }
        }
        for e in Expression.allCases {
            guard let pose = expressionMap[e.rawValue] else { problems.append("expressionMap lacks \(e.rawValue)"); continue }
            if poses[pose] == nil { problems.append("expressionMap maps \(e.rawValue) to unknown pose \(pose)") }
        }
        if rig.node(WholeBodyPosePack.posePartId) == nil { problems.append("rig has no \(WholeBodyPosePack.posePartId) node") }
        for banned in neverShowOnSkip ?? [] where clipPoses["settle"] == banned { problems.append("settle must not show \(banned)") }
        for part in layerParts ?? [] {
            guard let node = rig.node(part) else { problems.append("rig has no \(part) layer node"); continue }
            guard let pivotId = node.parent, let pivot = rig.node(pivotId), pivot.isPivot else {
                problems.append("\(part) layer node needs a pivot parent"); continue
            }
            for (name, pose) in poses {
                guard let layer = pose.layers?[part] else { continue }
                if layer.bounds.count != 4 || layer.bounds[0] >= layer.bounds[2] || layer.bounds[1] >= layer.bounds[3] { problems.append("\(name).\(part): invalid bounds") }
                if layer.imageSet.isEmpty { problems.append("\(name).\(part): empty imageSet") }
                if let p = layer.pivot, p.count == 2, pivot.position.count == 2,
                   abs(p[0] - pivot.position[0]) > 0.5 || abs(p[1] - pivot.position[1]) > 0.5 {
                    problems.append("\(name).\(part): pivot \(p) differs from rig node \(pivotId) \(pivot.position)")
                }
            }
        }
        for (name, pose) in poses {
            for part in pose.layers?.keys ?? [:].keys where !(layerParts ?? []).contains(part) { problems.append("\(name): layer \(part) not in layerParts") }
        }
        return problems
    }

    func isLayerPart(_ partId: String) -> Bool { layerParts?.contains(partId) ?? false }
}

/// Serves the pose textures for the `pose` part and delegates decorations (shadow, hearts) to another provider.
final class WholeBodyArtProvider: CharacterArtProvider {
    typealias TextureLoader = (String) -> SKTexture?

    let pack: WholeBodyPosePack
    let palette: [String: UIColor]
    var isProductionArt: Bool { pack.isProductionArt }
    var artLabel: String { "whole-body textures \(pack.characterId)\(pack.isProductionArt ? "" : " (review)")" }

    private let decorations: CharacterArtProvider
    private let loader: TextureLoader
    private var cache: [String: PartArt] = [:]
    private let lock = NSLock()

    init(pack: WholeBodyPosePack, decorations: CharacterArtProvider, loader: @escaping TextureLoader) {
        self.pack = pack
        self.decorations = decorations
        self.loader = loader
        self.palette = decorations.palette
    }

    /// Loads image sets from the asset catalog (`UIImage(named:)`), which lets Xcode manage compression and thinning.
    convenience init(pack: WholeBodyPosePack, decorations: CharacterArtProvider, bundle: Bundle = .main) {
        self.init(pack: pack, decorations: decorations) { name in
            guard let image = UIImage(named: name, in: bundle, compatibleWith: nil) else { return nil }
            return SKTexture(image: image)
        }
    }

    static func loadBundled(decorations: CharacterArtProvider, bundle: Bundle = .main) -> WholeBodyArtProvider? {
        guard let data = try? BundledResources.data(named: WholeBodyPosePack.resourceName, extension: "json", subdirectory: "Character", bundle: bundle),
              let pack = try? WholeBodyPosePack.load(from: data) else { return nil }
        return WholeBodyArtProvider(pack: pack, decorations: decorations, bundle: bundle)
    }

    /// The pose part and every layer part (e.g. the idle tail) change with the look, so they cross-fade.
    func hasVariants(_ partId: String) -> Bool { partId == WholeBodyPosePack.posePartId || pack.isLayerPart(partId) }

    /// The pose and layer parts ignore `pixelsPerUnit` (fixed texture density); other parts come from the
    /// decorations provider. A layer part returns nil for poses that do not carry that layer (sprite hidden).
    func art(for partId: String, look: String?, pixelsPerUnit: CGFloat) -> PartArt? {
        if partId == WholeBodyPosePack.posePartId {
            let poseName = look ?? pack.clipPoses["idle"] ?? "idle"
            guard let pose = pack.poses[poseName] ?? pack.poses["idle"] else { return nil }
            return cached(key: poseName, imageSet: pose.imageSet, bounds: pose.bounds)
        }
        if pack.isLayerPart(partId) {
            guard let look, let layer = pack.poses[look]?.layers?[partId] else { return nil }
            return cached(key: "\(partId)/\(look)", imageSet: layer.imageSet, bounds: layer.bounds)
        }
        return decorations.art(for: partId, look: look, pixelsPerUnit: pixelsPerUnit)
    }

    private func cached(key: String, imageSet: String, bounds: [Double]) -> PartArt? {
        guard bounds.count == 4 else { return nil }
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        guard let texture = loader(imageSet) else { return nil }
        let minX = CGFloat(bounds[0]), minY = CGFloat(bounds[1])
        let size = CGSize(width: CGFloat(bounds[2]) - minX, height: CGFloat(bounds[3]) - minY)
        guard size.width > 0, size.height > 0 else { return nil }
        texture.filteringMode = .linear
        let art = PartArt(size: size, anchorPoint: CGPoint(x: -minX / size.width, y: -minY / size.height), texture: texture)
        lock.lock()
        cache[key] = art
        lock.unlock()
        return art
    }

    /// Loads every pose and layer once so the first cross-fade does not stall.
    func preload(completion: @escaping () -> Void) {
        var textures: [SKTexture] = []
        for (name, pose) in pack.poses {
            if let t = art(for: WholeBodyPosePack.posePartId, look: name, pixelsPerUnit: 1)?.texture { textures.append(t) }
            for part in pose.layers?.keys ?? [:].keys {
                if let t = art(for: part, look: name, pixelsPerUnit: 1)?.texture { textures.append(t) }
            }
        }
        SKTexture.preload(textures, withCompletionHandler: completion)
    }

    func purgeCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
