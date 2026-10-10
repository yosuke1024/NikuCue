import Foundation
import NikuCueDomain
import SpriteKit
import UIKit

/// `mali_poses.json`: owner-supplied whole-body textures, one per pose, cross-faded by the rig
/// (docs/assets/mali_v1/README.md). This is an interim treatment: no part is independently movable, so no
/// blink, tail or limb motion is synthesised from these images.
struct WholeBodyPosePack: Decodable, Sendable {
    struct Pose: Decodable, Sendable {
        /// Asset catalog image set name (e.g. `MaliIdle`).
        var imageSet: String
        /// [minX, minY, maxX, maxY] in design units relative to the node origin (floor centre), y up.
        var bounds: [Double]
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
        return problems
    }
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

    func hasVariants(_ partId: String) -> Bool { partId == WholeBodyPosePack.posePartId }

    /// The pose part ignores `pixelsPerUnit` (fixed texture density); other parts come from the decorations provider.
    func art(for partId: String, look: String?, pixelsPerUnit: CGFloat) -> PartArt? {
        guard partId == WholeBodyPosePack.posePartId else {
            return decorations.art(for: partId, look: look, pixelsPerUnit: pixelsPerUnit)
        }
        let poseName = look ?? pack.clipPoses["idle"] ?? "idle"
        guard let pose = pack.poses[poseName] ?? pack.poses["idle"], pose.bounds.count == 4 else { return nil }
        lock.lock()
        if let hit = cache[poseName] { lock.unlock(); return hit }
        lock.unlock()
        guard let texture = loader(pose.imageSet) else { return nil }
        let minX = CGFloat(pose.bounds[0]), minY = CGFloat(pose.bounds[1])
        let size = CGSize(width: CGFloat(pose.bounds[2]) - minX, height: CGFloat(pose.bounds[3]) - minY)
        guard size.width > 0, size.height > 0 else { return nil }
        texture.filteringMode = .linear
        let art = PartArt(size: size, anchorPoint: CGPoint(x: -minX / size.width, y: -minY / size.height), texture: texture)
        lock.lock()
        cache[poseName] = art
        lock.unlock()
        return art
    }

    /// Loads every pose once so the first cross-fade does not stall.
    func preload(completion: @escaping () -> Void) {
        let textures = pack.poses.keys.compactMap { art(for: WholeBodyPosePack.posePartId, look: $0, pixelsPerUnit: 1)?.texture }
        SKTexture.preload(textures, withCompletionHandler: completion)
    }

    func purgeCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
