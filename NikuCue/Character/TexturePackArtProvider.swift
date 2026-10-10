import Foundation
import NikuCueDomain
import SpriteKit
import UIKit

/// `mali_texture_pack.json`: the production art contract (docs/CHARACTER_ASSET_PIPELINE.md §2).
/// Bounds are design units relative to each part's node origin, y up — the same convention as the
/// placeholder paths, so `CatRig` needs no change when the art changes.
struct TexturePackManifest: Decodable, Sendable {
    struct Drawing: Decodable, Sendable {
        /// Texture name inside the atlas, or the PNG file name (without extension) in `folder`.
        var texture: String
        /// [minX, minY, maxX, maxY] in design units relative to the node origin.
        var bounds: [Double]

        init(texture: String, bounds: [Double]) {
            self.texture = texture
            self.bounds = bounds
        }
    }

    struct Part: Decodable, Sendable {
        var texture: String?
        var bounds: [Double]?
        var variants: [String: Drawing]?

        init(texture: String?, bounds: [Double]?, variants: [String: Drawing]?) {
            self.texture = texture
            self.bounds = bounds
            self.variants = variants
        }

        func drawing(for look: String?) -> Drawing? {
            if let variants {
                return variants[look ?? Expression.neutral.rawValue] ?? variants[Expression.neutral.rawValue]
            }
            guard let texture, let bounds else { return nil }
            return Drawing(texture: texture, bounds: bounds)
        }

        var hasVariants: Bool { variants != nil }
    }

    var schemaVersion: Int
    var characterId: String
    var isProductionArt: Bool
    var status: String?
    /// `SKTextureAtlas` name (an `.spriteatlas` folder in the asset catalog). When nil, `folder` holds loose PNGs.
    var atlas: String?
    var folder: String?
    var pixelsPerUnit: Double
    var parts: [String: Part]
    var license: String?
    var source: String?

    init(schemaVersion: Int, characterId: String, isProductionArt: Bool, status: String?, atlas: String?, folder: String?,
         pixelsPerUnit: Double, parts: [String: Part], license: String?, source: String?) {
        self.schemaVersion = schemaVersion
        self.characterId = characterId
        self.isProductionArt = isProductionArt
        self.status = status
        self.atlas = atlas
        self.folder = folder
        self.pixelsPerUnit = pixelsPerUnit
        self.parts = parts
        self.license = license
        self.source = source
    }

    static let resourceName = "mali_texture_pack"

    static func load(from data: Data) throws -> TexturePackManifest {
        try JSONDecoder().decode(TexturePackManifest.self, from: data)
    }

    /// Structural check against the rig: every drawable node has art, eyes/mouth cover all expressions, bounds are sane.
    func validate(against rig: RigSpec) -> [String] {
        var problems: [String] = []
        if pixelsPerUnit <= 0 { problems.append("pixelsPerUnit must be positive") }
        for node in rig.nodes where !node.isPivot {
            guard let part = parts[node.id] else { problems.append("missing part \(node.id)"); continue }
            let drawings: [(String, Drawing)]
            if let variants = part.variants {
                for e in Expression.allCases where variants[e.rawValue] == nil { problems.append("\(node.id): missing variant \(e.rawValue)") }
                drawings = variants.map { ($0.key, $0.value) }
            } else if let d = part.drawing(for: nil) {
                drawings = [("_", d)]
            } else {
                problems.append("\(node.id): neither texture/bounds nor variants")
                continue
            }
            for (name, d) in drawings {
                if d.bounds.count != 4 || d.bounds[0] >= d.bounds[2] || d.bounds[1] >= d.bounds[3] {
                    problems.append("\(node.id)/\(name): invalid bounds")
                }
                if d.texture.isEmpty { problems.append("\(node.id)/\(name): empty texture name") }
            }
        }
        if parts["heart"] == nil { problems.append("missing part heart") }
        return problems
    }
}

/// Production art provider: textures from an `SKTextureAtlas` or bundled PNGs described by the manifest.
/// The rig, animations, scene controller and Domain stay untouched when the art is replaced.
final class TexturePackArtProvider: CharacterArtProvider {
    typealias TextureLoader = (String) -> SKTexture?

    let manifest: TexturePackManifest
    let palette: [String: UIColor] = [:]
    var isProductionArt: Bool { manifest.isProductionArt }
    var artLabel: String { "texture pack \(manifest.characterId)\(manifest.isProductionArt ? "" : " (review)")" }

    private let loader: TextureLoader
    private var cache: [String: PartArt] = [:]
    private let lock = NSLock()

    init(manifest: TexturePackManifest, loader: @escaping TextureLoader) {
        self.manifest = manifest
        self.loader = loader
    }

    /// Loads textures from the atlas named in the manifest, or from PNG files in `manifest.folder` inside the bundle.
    convenience init(manifest: TexturePackManifest, bundle: Bundle = .main) {
        if let atlasName = manifest.atlas {
            let atlas = SKTextureAtlas(named: atlasName)
            let names = Set(atlas.textureNames.map { ($0 as NSString).deletingPathExtension })
            self.init(manifest: manifest) { name in
                guard names.contains(name) else { return nil }
                return atlas.textureNamed(name)
            }
        } else {
            let folder = manifest.folder
            self.init(manifest: manifest) { name in
                guard let url = BundledResources.url(named: name, extension: "png", subdirectory: folder, bundle: bundle),
                      let image = UIImage(contentsOfFile: url.path) else { return nil }
                return SKTexture(image: image)
            }
        }
    }

    static func loadBundled(bundle: Bundle = .main) -> TexturePackArtProvider? {
        guard let data = try? BundledResources.data(named: TexturePackManifest.resourceName, extension: "json", subdirectory: "Character", bundle: bundle),
              let manifest = try? TexturePackManifest.load(from: data) else { return nil }
        return TexturePackArtProvider(manifest: manifest, bundle: bundle)
    }

    func hasVariants(_ partId: String) -> Bool { manifest.parts[partId]?.hasVariants ?? false }

    /// `pixelsPerUnit` is ignored: the art has one fixed density (`manifest.pixelsPerUnit`).
    func art(for partId: String, look: String?, pixelsPerUnit: CGFloat) -> PartArt? {
        guard let part = manifest.parts[partId], let drawing = part.drawing(for: look), drawing.bounds.count == 4 else { return nil }
        let key = "\(partId)/\(part.hasVariants ? (look ?? Expression.neutral.rawValue) : "_")"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        guard let texture = loader(drawing.texture) else { return nil }
        let minX = CGFloat(drawing.bounds[0]), minY = CGFloat(drawing.bounds[1])
        let maxX = CGFloat(drawing.bounds[2]), maxY = CGFloat(drawing.bounds[3])
        let size = CGSize(width: maxX - minX, height: maxY - minY)
        guard size.width > 0, size.height > 0 else { return nil }
        texture.filteringMode = .linear
        let art = PartArt(size: size, anchorPoint: CGPoint(x: -minX / size.width, y: -minY / size.height), texture: texture)
        lock.lock()
        cache[key] = art
        lock.unlock()
        return art
    }

    /// Loads every texture once so the first reaction does not stall (call off the critical path).
    func preload(rig: RigSpec, completion: @escaping () -> Void) {
        var textures: [SKTexture] = []
        for node in rig.nodes where !node.isPivot {
            let looks: [String?] = hasVariants(node.id) ? rig.expressions : [nil]
            for look in looks {
                if let art = art(for: node.id, look: look, pixelsPerUnit: 1) { textures.append(art.texture) }
            }
        }
        if let heart = art(for: "heart", look: nil, pixelsPerUnit: 1) { textures.append(heart.texture) }
        SKTexture.preload(textures, withCompletionHandler: completion)
    }

    func purgeCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}

/// Picks the art for this build, in order: whole-body pose textures (owner-supplied, mali_poses.json) →
/// layered texture pack (mali_texture_pack.json) → code-drawn placeholder. Each choice names its rig and animation files.
enum CharacterArtSelection {
    case wholeBody(WholeBodyArtProvider)
    case texturePack(TexturePackArtProvider)
    case placeholder(VectorArtProvider)

    var provider: CharacterArtProvider {
        switch self {
        case .wholeBody(let p): return p
        case .texturePack(let p): return p
        case .placeholder(let p): return p
        }
    }

    /// Drops decoded textures that are not on screen (memory warnings); sprites keep what they display.
    func purgeCaches() {
        switch self {
        case .wholeBody(let p): p.purgeCache()
        case .texturePack(let p): p.purgeCache()
        case .placeholder(let p): p.purgeCache()
        }
    }

    /// Resource names (without extension) of the rig contract and the animation tracks for this art.
    var rigResourceName: String {
        if case .wholeBody = self { return "mali_wholebody_spec" }
        return "character_spec"
    }

    var animationResourceName: String {
        if case .wholeBody = self { return "mali_wholebody_animations" }
        return "animations"
    }

    static func resolve(paths: ArtPaths, bundle: Bundle = .main) -> CharacterArtSelection {
        let placeholder = VectorArtProvider(paths: paths)
        if let poses = WholeBodyArtProvider.loadBundled(decorations: placeholder, bundle: bundle) {
            return .wholeBody(poses)
        }
        if let pack = TexturePackArtProvider.loadBundled(bundle: bundle) {
            return .texturePack(pack)
        }
        return .placeholder(placeholder)
    }
}
