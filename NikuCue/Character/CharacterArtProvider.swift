import CoreGraphics
import Foundation
import NikuCueDomain
import SpriteKit
import UIKit

/// One rendered part: a texture plus where the node origin sits inside it.
struct PartArt {
    /// Size in design units (the rig is scaled as a whole; textures carry the pixel density).
    let size: CGSize
    /// SpriteKit anchor so that the node's origin is the pivot described by the rig contract.
    let anchorPoint: CGPoint
    let texture: SKTexture
}

/// Supplies textures for rig parts. The state machine never depends on how art is produced, so the
/// code-drawn prototype can be replaced by approved transparent PNGs without touching `CatRig` (CLAUDE.md "Art quality").
protocol CharacterArtProvider: AnyObject {
    var palette: [String: UIColor] { get }
    var isProductionArt: Bool { get }
    /// Shown in the Debug gallery so placeholder and production art are never confused.
    var artLabel: String { get }
    /// `expression` is only meaningful for parts that have expression variants (eyes, mouth).
    func art(for partId: String, expression: Expression?, pixelsPerUnit: CGFloat) -> PartArt?
    func hasVariants(_ partId: String) -> Bool
}

/// Parses the mini path language used by mali_paths.json (`M x y | L x y | C … | Q … | Z`, absolute coordinates).
enum PathParser {
    enum ParseError: Error { case badToken(String), truncated }

    static func cgPath(_ d: String) throws -> CGPath {
        let path = CGMutablePath()
        let tokens = d.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).map(String.init)
        var i = 0
        func number() throws -> CGFloat {
            guard i < tokens.count, let v = Double(tokens[i]) else { throw ParseError.truncated }
            i += 1
            return CGFloat(v)
        }
        while i < tokens.count {
            let t = tokens[i]
            i += 1
            switch t {
            case "M": path.move(to: CGPoint(x: try number(), y: try number()))
            case "L": path.addLine(to: CGPoint(x: try number(), y: try number()))
            case "C":
                let c1 = CGPoint(x: try number(), y: try number())
                let c2 = CGPoint(x: try number(), y: try number())
                path.addCurve(to: CGPoint(x: try number(), y: try number()), control1: c1, control2: c2)
            case "Q":
                let c = CGPoint(x: try number(), y: try number())
                path.addQuadCurve(to: CGPoint(x: try number(), y: try number()), control: c)
            case "Z": path.closeSubpath()
            default: throw ParseError.badToken(t)
            }
        }
        return path
    }
}

extension UIColor {
    /// `#RRGGBB` or `#RRGGBBAA`.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 6 {
            r = CGFloat((v >> 16) & 0xFF) / 255; g = CGFloat((v >> 8) & 0xFF) / 255; b = CGFloat(v & 0xFF) / 255; a = 1
        } else {
            r = CGFloat((v >> 24) & 0xFF) / 255; g = CGFloat((v >> 16) & 0xFF) / 255; b = CGFloat((v >> 8) & 0xFF) / 255; a = CGFloat(v & 0xFF) / 255
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

/// DEVELOPMENT PLACEHOLDER (owner decision 2026-10-10, docs/CHARACTER_ASSET_PIPELINE.md): renders the code-drawn
/// `mali_paths.json` layers into textures once per (part, expression, density). Used only while no texture pack
/// is bundled; it is not product art and is not developed further.
final class VectorArtProvider: CharacterArtProvider {
    let paths: ArtPaths
    let palette: [String: UIColor]
    var isProductionArt: Bool { false }
    var artLabel: String { "placeholder (code-drawn)" }

    private var compiled: [String: [CGPath]] = [:]   // "part/variant" → one CGPath per layer
    private var cache: [String: PartArt] = [:]
    private let lock = NSLock()

    init(paths: ArtPaths) {
        self.paths = paths
        var colors: [String: UIColor] = [:]
        for (name, hex) in paths.palette {
            if let c = UIColor(hex: hex) { colors[name] = c }
        }
        palette = colors
    }

    func hasVariants(_ partId: String) -> Bool { paths.parts[partId]?.hasVariants ?? false }

    func art(for partId: String, expression: Expression?, pixelsPerUnit: CGFloat) -> PartArt? {
        guard let part = paths.parts[partId], let drawing = part.drawing(for: expression) else { return nil }
        let variant = part.hasVariants ? (expression ?? .neutral).rawValue : "_"
        let density = (pixelsPerUnit * 100).rounded() / 100
        let key = "\(partId)/\(variant)@\(density)"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        guard drawing.bounds.count == 4 else { return nil }
        let minX = CGFloat(drawing.bounds[0]), minY = CGFloat(drawing.bounds[1])
        let maxX = CGFloat(drawing.bounds[2]), maxY = CGFloat(drawing.bounds[3])
        let unitSize = CGSize(width: maxX - minX, height: maxY - minY)
        guard unitSize.width > 0, unitSize.height > 0 else { return nil }
        let pixelSize = CGSize(width: max(1, (unitSize.width * density).rounded(.up)),
                               height: max(1, (unitSize.height * density).rounded(.up)))
        let cgPaths = compiledPaths(partId: partId, variant: variant, layers: drawing.layers)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            // design units are y-up; UIKit contexts are y-down: flip once, then scale and shift to bounds.
            cg.translateBy(x: 0, y: pixelSize.height)
            cg.scaleBy(x: density, y: -density)
            cg.translateBy(x: -minX, y: -minY)
            cg.setLineJoin(.round)
            for (layer, path) in zip(drawing.layers, cgPaths) {
                cg.setAlpha(CGFloat(layer.opacity ?? 1))
                if let fill = layer.fill, let color = palette[fill] {
                    cg.addPath(path)
                    cg.setFillColor(color.cgColor)
                    cg.fillPath()
                }
                if let stroke = layer.stroke, let color = palette[stroke] {
                    cg.addPath(path)
                    cg.setStrokeColor(color.cgColor)
                    cg.setLineWidth(CGFloat(layer.width ?? 4))
                    cg.setLineCap(layer.cap == "butt" ? .butt : (layer.cap == "square" ? .square : .round))
                    cg.strokePath()
                }
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        let art = PartArt(size: unitSize,
                          anchorPoint: CGPoint(x: -minX / unitSize.width, y: -minY / unitSize.height),
                          texture: texture)
        lock.lock()
        cache[key] = art
        lock.unlock()
        return art
    }

    private func compiledPaths(partId: String, variant: String, layers: [ArtPaths.Layer]) -> [CGPath] {
        let key = "\(partId)/\(variant)"
        lock.lock()
        defer { lock.unlock() }
        if let hit = compiled[key] { return hit }
        let paths = layers.map { (try? PathParser.cgPath($0.path)) ?? CGMutablePath() }
        compiled[key] = paths
        return paths
    }

    /// Drops cached textures (e.g. on memory warnings); parts are re-rendered on demand.
    func purgeCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
