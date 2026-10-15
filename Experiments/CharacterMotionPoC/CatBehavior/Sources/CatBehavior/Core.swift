// Small value types shared by every layer. Standard library only (see Package.swift).

/// Which way the character looks along the floor. `right` is the skeleton's authored direction (scaleX = +1).
public enum Facing: Int, Sendable, Equatable, Codable {
    case left = -1
    case right = 1

    public var sign: Double { Double(rawValue) }
    public var flipped: Facing { self == .left ? .right : .left }

    /// The facing that points from `x` towards `targetX` (keeps `self` when they coincide).
    public func towards(_ targetX: Double, from x: Double) -> Facing {
        if targetX > x + 0.5 { return .right }
        if targetX < x - 0.5 { return .left }
        return self
    }
}

/// A point in stage units (the skeleton's own units; y up, floor at y = 0).
public struct Point: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Deterministic generator (SplitMix64) so a seed reproduces a whole session in tests, CI recordings and the browser.
public struct SplitMix64: RandomNumberGenerator, Sendable, Equatable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }

    public mutating func between(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }

    public mutating func chance(_ p: Double) -> Bool { unit() < p }
}

enum Ease {
    /// Smoothstep: zero slope at both ends, so speed ramps never start or stop with a kink.
    static func smooth(_ t: Double) -> Double {
        let u = clamp(t, 0, 1)
        return u * u * (3 - 2 * u)
    }
}

@inline(__always) func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

/// Positive remainder in [0, 1): the phase of a looping clip.
@inline(__always) func fract(_ v: Double) -> Double {
    let r = v - v.rounded(.down)
    return r >= 1 ? 0 : r
}
