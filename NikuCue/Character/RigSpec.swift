import Foundation
import NikuCueDomain

/// Decoded `character_spec.json` (the rig contract, docs/04 §3).
struct RigSpec: Decodable, Sendable {
    struct Canvas: Decodable, Sendable {
        var width: Double
        var height: Double
        var rootGroundY: Double
    }

    struct Node: Decodable, Sendable {
        var id: String
        var parent: String?
        var position: [Double]
        var z: Double
        var kind: String
        var size: [Double]?
        var anchor: [Double]?
        var fill: String?
        var opacity: Double?
        /// Optional uniform rest scale (whole-body rig uses it to widen the placeholder shadow).
        var scale: Double?

        var isPivot: Bool { kind == "pivot" }
    }

    var schemaVersion: Int
    var characterId: String
    var isProductionArt: Bool
    var canvas: Canvas
    var palette: [String: String]
    /// Looks the art can show: expression names for the parts rig, pose names for the whole-body rig.
    var expressions: [String]
    /// Whole-body rig only: engine expression → pose (e.g. closedHappy → happy).
    var expressionMap: [String: String]?
    /// Whole-body rig only: visible character bounds in design units (parts rig uses the docs/04 760 × 760 guide).
    var designSize: [Double]?
    var nodes: [Node]

    static func load(from data: Data) throws -> RigSpec {
        try JSONDecoder().decode(RigSpec.self, from: data)
    }

    func node(_ id: String) -> Node? { nodes.first { $0.id == id } }

    /// Children in z order (stable for equal z).
    func children(of parentId: String) -> [Node] {
        nodes.enumerated()
            .filter { $0.element.parent == parentId }
            .sorted { ($0.element.z, $0.offset) < ($1.element.z, $1.offset) }
            .map(\.element)
    }

    var rootNode: Node? { nodes.first { $0.parent == nil } }

    /// Structural validation mirrored from scripts/check_resources.py (one root, no cycles, known parents).
    func validate() -> [String] {
        var problems: [String] = []
        let ids = nodes.map(\.id)
        if Set(ids).count != ids.count { problems.append("duplicate node ids") }
        if nodes.filter({ $0.parent == nil }).count != 1 { problems.append("rig must have exactly one root") }
        let byId = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for n in nodes {
            var seen: Set<String> = [n.id]
            var p = n.parent
            while let parent = p {
                guard let pn = byId[parent] else { problems.append("missing parent \(parent)"); break }
                if !seen.insert(parent).inserted { problems.append("cycle at \(parent)"); break }
                p = pn.parent
            }
            if n.position.count != 2 { problems.append("\(n.id): position needs two values") }
        }
        if expressionMap == nil {
            for e in Expression.allCases where !expressions.contains(e.rawValue) { problems.append("missing expression \(e.rawValue)") }
        } else {
            for e in Expression.allCases {
                guard let mapped = expressionMap?[e.rawValue] else { problems.append("expressionMap lacks \(e.rawValue)"); continue }
                if !expressions.contains(mapped) { problems.append("expressionMap maps \(e.rawValue) to unknown look \(mapped)") }
            }
        }
        return problems
    }

    /// The look to show for an engine expression (identity for the parts rig).
    func look(for expression: Expression) -> String {
        expressionMap?[expression.rawValue] ?? expression.rawValue
    }
}

/// Decoded `mali_paths.json`: vector layers per part, relative to the part's node origin.
struct ArtPaths: Decodable, Sendable {
    struct Layer: Decodable, Sendable {
        var path: String
        var fill: String?
        var stroke: String?
        var width: Double?
        var opacity: Double?
        var cap: String?
    }

    struct Drawing: Decodable, Sendable {
        /// [minX, minY, maxX, maxY] in design units, y up.
        var bounds: [Double]
        var layers: [Layer]
    }

    /// Either a single drawing or one drawing per expression.
    struct Part: Decodable, Sendable {
        var bounds: [Double]?
        var layers: [Layer]?
        var variants: [String: Drawing]?

        func drawing(for look: String?) -> Drawing? {
            if let variants {
                return variants[look ?? Expression.neutral.rawValue] ?? variants[Expression.neutral.rawValue]
            }
            guard let bounds, let layers else { return nil }
            return Drawing(bounds: bounds, layers: layers)
        }

        var hasVariants: Bool { variants != nil }
    }

    var schemaVersion: Int
    var characterId: String
    var isProductionArt: Bool
    var palette: [String: String]
    var parts: [String: Part]

    static func load(from data: Data) throws -> ArtPaths {
        try JSONDecoder().decode(ArtPaths.self, from: data)
    }
}

/// Decoded `animations.json` with the keyframe tracks added in REV-002.
struct AnimationSpec: Decodable, Sendable {
    enum KeyValue: Decodable, Sendable, Equatable {
        case number(Double)
        case name(String)

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { self = .number(d); return }
            self = .name(try c.decode(String.self))
        }

        var number: Double? { if case .number(let d) = self { return d } else { return nil } }
        var name: String? { if case .name(let s) = self { return s } else { return nil } }
    }

    struct Keyframe: Decodable, Sendable {
        var t: Double
        var v: KeyValue
        var ease: String?
    }

    struct Track: Decodable, Sendable {
        var node: String
        var property: String
        var keyframes: [Keyframe]
    }

    struct ReducedHeart: Decodable, Sendable {
        var position: [Double]
        var scale: Double
    }

    struct Hearts: Decodable, Sendable {
        var spawnAtMs: [Double]
        var lifeMs: Double
        var riseUnits: Double
        var max: Int
        var positions: [[Double]]
        var scale: Double
        var reducedMotion: ReducedHeart
    }

    struct Clip: Decodable, Sendable {
        var id: String
        var durationMs: Double
        var loop: Bool
        var expression: String
        var controls: [String]
        var tracks: [Track]
        var reducedMotionTracks: [Track]
        var hearts: Hearts?

        var duration: TimeInterval { durationMs / 1000 }
        var clipID: ClipID? { ClipID(rawValue: id) }
        var defaultExpression: Expression { Expression(rawValue: expression) ?? .neutral }
        /// The look (expression or pose name) the clip starts with.
        var defaultLook: String { expression }
    }

    struct Blink: Decodable, Sendable {
        var intervalMs: [Double]
        var durationMs: Double
        var closedScaleY: Double
        /// Whole-body textures cannot blink (no eye parts); the controller skips scheduling when false.
        var enabled: Bool?
    }

    struct Ambient: Decodable, Sendable {
        var blink: Blink
    }

    var schemaVersion: Int
    var fpsTarget: Int
    var maxQueuedInteractions: Int
    var expressionBlendMs: Double
    var clips: [Clip]
    var ambient: Ambient

    static func load(from data: Data) throws -> AnimationSpec {
        try JSONDecoder().decode(AnimationSpec.self, from: data)
    }

    func clip(_ id: ClipID) -> Clip? { clips.first { $0.id == id.rawValue } }

    var expressionBlend: TimeInterval { expressionBlendMs / 1000 }

    /// Mirrors scripts/check_resources.py for the parts that matter at runtime.
    func validate(against rig: RigSpec) -> [String] {
        var problems: [String] = []
        for id in ClipID.allCases where clip(id) == nil { problems.append("missing clip \(id.rawValue)") }
        for clip in clips where !rig.expressions.contains(clip.expression) { problems.append("\(clip.id): default look \(clip.expression) not in rig looks") }
        let props: Set<String> = ["rotation", "offsetX", "offsetY", "scaleX", "scaleY", "scale", "alpha", "expression"]
        for clip in clips {
            let allowed = Set(clip.controls).union(["face"])
            var seen = Set<String>()
            for track in clip.tracks + clip.reducedMotionTracks {
                if !allowed.contains(track.node) { problems.append("\(clip.id): \(track.node) not in controls") }
                if rig.node(track.node) == nil { problems.append("\(clip.id): unknown node \(track.node)") }
                if !props.contains(track.property) { problems.append("\(clip.id): bad property \(track.property)") }
                let times = track.keyframes.map(\.t)
                if times != times.sorted() || (times.last ?? 0) > clip.durationMs { problems.append("\(clip.id): bad keyframe times on \(track.node)") }
                if track.property == "expression" {
                    for k in track.keyframes where !(k.v.name.map { rig.expressions.contains($0) } ?? false) {
                        problems.append("\(clip.id): expression track value not in rig looks")
                    }
                } else if track.keyframes.contains(where: { $0.v.number == nil }) {
                    problems.append("\(clip.id): non-numeric keyframe on \(track.node).\(track.property)")
                }
            }
            for track in clip.tracks {
                if !seen.insert("\(track.node).\(track.property)").inserted { problems.append("\(clip.id): duplicate track \(track.node).\(track.property)") }
            }
        }
        return problems
    }
}

/// Keyframe sampling shared by every track player (same math as tools/rig-preview/rig.js).
enum KeyframeSampler {
    static func ease(_ name: String?, _ t: Double) -> Double {
        switch name ?? "easeInOut" {
        case "linear": return t
        case "easeIn": return t * t
        case "easeOut": return 1 - (1 - t) * (1 - t)
        case "sine": return 0.5 - 0.5 * cos(.pi * t)
        default: return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        }
    }

    /// Numeric value at `ms`, holding the first/last keyframe outside the range.
    static func number(_ track: AnimationSpec.Track, at ms: Double) -> Double? {
        let kf = track.keyframes
        guard let first = kf.first, let last = kf.last else { return nil }
        if ms <= first.t { return first.v.number }
        if ms >= last.t { return last.v.number }
        for i in 0..<(kf.count - 1) {
            let a = kf[i], b = kf[i + 1]
            if ms >= a.t && ms <= b.t {
                guard let av = a.v.number, let bv = b.v.number else { return nil }
                let span = b.t - a.t
                let u = span > 0 ? (ms - a.t) / span : 1
                return av + (bv - av) * ease(b.ease, u)
            }
        }
        return last.v.number
    }

    /// String value (expression) at `ms`: the latest keyframe whose time has been reached.
    static func name(_ track: AnimationSpec.Track, at ms: Double) -> String? {
        var current: String? = track.keyframes.first?.v.name
        for k in track.keyframes where k.t <= ms { current = k.v.name }
        return current
    }
}
