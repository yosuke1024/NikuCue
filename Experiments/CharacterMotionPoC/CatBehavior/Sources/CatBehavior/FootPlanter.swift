// Foot planting for skeletal renderers. Blending two clips whose feet stand in different places makes a grounded
// foot glide from one place to the other. With IK-driven legs the renderer can instead keep that foot where it
// landed for the length of the blend and then move it with a short lifted step, which reads as the character
// settling its stance. Pure math: the renderer passes the animated foot-target positions (world, stage units) and
// writes back the returned ones before computing world transforms. A flipbook renderer cannot do this.

public struct FootPlanter: Sendable {
    public var groundTolerance: Double
    public var stepDuration = 0.16
    public var stepHeight = 34.0
    /// Offsets smaller than this are absorbed without lifting the foot.
    public var liftThreshold = 6.0

    private struct Foot: Sendable {
        var lockX: Double?
        var step: (from: Double, start: Double)?
        var last: Point?
    }

    private var feet: [Foot] = []
    private var serial = -1
    private var serialStart = 0.0
    private var facing: Facing = .right

    public init(groundTolerance: Double) {
        self.groundTolerance = groundTolerance
    }

    /// Animated target positions in, planted positions out (same order).
    public mutating func solve(_ animated: [Point], state s: RenderState) -> [Point] {
        if feet.count != animated.count { feet = Array(repeating: Foot(), count: animated.count) }
        if s.base.serial != serial {
            serial = s.base.serial
            serialStart = s.time
        }
        // The turn's first frame mirrors the body (scaleX): an asymmetric stance would make the feet jump to the
        // other side. Instead every foot steps from where it was to where the mirrored pose puts it.
        let flipped = s.facing != facing
        facing = s.facing
        // Grounded feet are held while two clips blend and while an in-place turn plays (its feet shuffle), and are
        // re-planted with a step afterwards. A walk past its start blend plants nothing new.
        let blending = s.time - serialStart < s.base.mix || s.mode == .turning
        var out: [Point] = []
        for i in animated.indices {
            let p = animated[i]
            var f = feet[i]
            defer { feet[i] = f }
            if flipped, let last = f.last {
                f.lockX = nil
                f.step = (last.x, s.time)
            }
            if let lock = f.lockX {
                if p.y > groundTolerance || !blending {
                    f.lockX = nil
                    f.step = (lock, s.time)            // the animation lifts the foot, or the blend is over: step
                } else {
                    let q = Point(x: lock, y: p.y)
                    f.last = q
                    out.append(q)
                    continue
                }
            } else if f.step == nil, blending, p.y <= groundTolerance, let last = f.last, last.y <= groundTolerance {
                f.lockX = last.x                       // grounded when the blend began: keep it where it is
                let q = Point(x: last.x, y: p.y)
                f.last = q
                out.append(q)
                continue
            }
            if let step = f.step {
                let u = s.time - step.start >= stepDuration ? 1.0 : (s.time - step.start) / stepDuration
                // lift first, travel while lifted, then set down: no horizontal motion while the foot touches
                let eased = Ease.smooth((u - 0.15) / 0.7)
                let x = step.from + (p.x - step.from) * eased
                let lift = abs(p.x - step.from) > liftThreshold ? stepHeight * 4 * u * (1 - u) : 0
                let q = Point(x: x, y: p.y + lift)
                if u >= 1 { f.step = nil }
                f.last = q
                out.append(q)
                continue
            }
            f.last = p
            out.append(p)
        }
        return out
    }
}
