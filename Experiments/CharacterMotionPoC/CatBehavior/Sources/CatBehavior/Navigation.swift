// Where the character may stand and walk. v1 is a side view: one floor line (x) the root moves along.
// Places of interest give walks a purpose ("goes to the window", "naps on the cushion"); no-rest zones keep the
// character from settling where it would cover UI (for NikuCue: the speech bubble anchor, never the ad banner,
// which is outside the stage entirely).

public enum SpotKind: String, Sendable, Equatable, Codable, CaseIterable {
    case window, cushion, toy, front
}

public struct Spot: Sendable, Equatable, Codable {
    public var kind: SpotKind
    public var x: Double
    /// Facing while using the spot (nil: keep the arrival facing).
    public var facing: Facing?
    /// What the character looks at while there (window pane, toy on the floor).
    public var lookAt: Point?

    public init(kind: SpotKind, x: Double, facing: Facing? = nil, lookAt: Point? = nil) {
        self.kind = kind
        self.x = x
        self.facing = facing
        self.lookAt = lookAt
    }
}

public struct StageLayout: Sendable, Equatable, Codable {
    /// Stage extent in units. The root stays `profile.halfWidth` inside it so the body never leaves the stage.
    public var minX: Double
    public var maxX: Double
    public var height: Double
    public var spots: [Spot]
    public var noRestZones: [ClosedRange<Double>]
    /// Where the person is, for "looks at you" (front, above the stage centre).
    public var userPoint: Point

    public init(minX: Double, maxX: Double, height: Double, spots: [Spot], noRestZones: [ClosedRange<Double>] = [],
                userPoint: Point) {
        self.minX = minX
        self.maxX = maxX
        self.height = height
        self.spots = spots
        self.noRestZones = noRestZones
        self.userPoint = userPoint
    }

    public func spot(_ kind: SpotKind) -> Spot? { spots.first { $0.kind == kind } }

    /// A room for evaluation: `width` units wide, window on the left, toy right of centre, cushion on the right.
    public static func evaluationRoom(width: Double, height: Double) -> StageLayout {
        StageLayout(
            minX: 0, maxX: width, height: height,
            spots: [
                Spot(kind: .window, x: width * 0.16, facing: .left, lookAt: Point(x: width * 0.02, y: height * 0.78)),
                Spot(kind: .toy, x: width * 0.58, facing: .right, lookAt: Point(x: width * 0.68, y: 40)),
                Spot(kind: .cushion, x: width * 0.84, facing: .left, lookAt: nil),
                Spot(kind: .front, x: width * 0.5, facing: nil, lookAt: nil),
            ],
            noRestZones: [],
            userPoint: Point(x: width * 0.5, y: height * 1.15)
        )
    }
}

public struct WalkPlan: Sendable, Equatable {
    public var target: Double
    /// Walk-clip phase to start at (from standing); ignored when retargeting a running walk.
    public var startPhase: Double
}

public struct Navigator: Sendable {
    public let stage: StageLayout
    public let profile: MotionProfile

    public init(stage: StageLayout, profile: MotionProfile) {
        self.stage = stage
        self.profile = profile
    }

    /// Allowed root positions.
    public var floor: ClosedRange<Double> {
        let lo = stage.minX + profile.halfWidth
        let hi = max(lo, stage.maxX - profile.halfWidth)
        return lo...hi
    }

    public func clampToFloor(_ x: Double) -> Double { clamp(x, floor.lowerBound, floor.upperBound) }

    public func canRest(at x: Double) -> Bool { !stage.noRestZones.contains { $0.contains(x) } }

    /// Plans a walk towards `desiredX`: the start phase (inside the blend window when starting from standing, or the
    /// current phase when already walking) and a distance that ends inside the blend window. Feet are planted, so the
    /// arrival phase is start + distance / stride; only distances landing in the window stop without sliding.
    /// Returns nil when no such walk ends within `tolerance` of the desired point (the caller looks or turns instead).
    public func plannedWalk(from x: Double, desiredX: Double, startPhases: [Double], tolerance: Double,
                            minimumDistance: Double? = nil) -> WalkPlan? {
        let desired = clampToFloor(desiredX)
        guard abs(desired - x) > 1 else { return nil }
        let direction: Double = desired > x ? 1 : -1
        let walk = profile.walk
        let stride = walk.strideLength
        let minimum = minimumDistance ?? stride * 0.6
        let wanted = abs(desired - x)
        let room = direction > 0 ? floor.upperBound - x : x - floor.lowerBound
        var best: WalkPlan?
        var bestScore = Double.infinity
        for s in startPhases {
            var k = 0.0
            while (k + walk.blendWindow.lowerBound - s) * stride <= room + stride {
                let lo = max(minimum, (k + walk.blendWindow.lowerBound - s) * stride)
                let hi = min(room, (k + walk.blendWindow.upperBound - s) * stride)
                k += 1
                guard lo <= hi else { continue }
                let d = clamp(wanted, lo, hi)
                let target = x + direction * d
                guard canRest(at: target) else { continue }
                // prefer the exact distance, then the start phase closest to the clip's own best entry
                let score = abs(d - wanted) + 20 * abs(s - walk.enterPhase)
                if score < bestScore {
                    bestScore = score
                    best = WalkPlan(target: target, startPhase: s)
                }
            }
        }
        guard let best, abs(best.target - desired) <= tolerance else { return nil }
        return best
    }

    /// Start phases offered when a walk begins from standing: samples across the blend window.
    public var standingStartPhases: [Double] {
        let w = profile.walk.blendWindow
        let n = 16
        return (0...n).map { w.lowerBound + (w.upperBound - w.lowerBound) * Double($0) / Double(n) }
    }

}
