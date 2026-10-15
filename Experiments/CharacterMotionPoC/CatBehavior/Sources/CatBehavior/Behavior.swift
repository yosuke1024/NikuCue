// What the character decides to do. Choices are weighted by a small hidden mood and by what it just did, so the
// sequence reads as intention ("walks to the window, looks out, comes back to nap") instead of a random shuffle.
//
// NikuCue rule (CLAUDE.md, no guilt): the mood is never shown, never depends on habits or the user's absence,
// and has no bad state. Low "energy" only makes a nap more likely; nothing gets hungry, sad or sick.

public enum ActivityKind: String, Sendable, Equatable, Codable, CaseIterable {
    // autonomous
    case settle, idle, wander, lookAround, visitWindow, nap, play, approachUser
    // reactions to the person
    case petReaction, callReaction, celebrateReaction, restReaction

    public var isReaction: Bool {
        switch self {
        case .petReaction, .callReaction, .celebrateReaction, .restReaction: return true
        default: return false
        }
    }

    /// Activities that move the character across the floor (none of them run under Reduce Motion).
    var travels: Bool {
        switch self {
        case .wander, .visitWindow, .nap, .play, .approachUser: return true
        default: return false
        }
    }
}

/// One step of a plan. Walk targets are resolved when the step starts, from wherever the character is then.
enum Step: Sendable, Equatable {
    case walk(desiredX: Double, tolerance: Double, cruise: Double)
    case face(Facing)
    case faceTowards(x: Double)
    case stand(seconds: Double)
    case rest(seconds: Double)
    case look(at: Point, seconds: Double)
    case hop
}

struct Plan: Sendable, Equatable {
    var kind: ActivityKind
    var steps: [Step]
    var index = 0
    var started = false
    var stepTime = 0.0
    /// A turn the step needs before it can start (e.g. walking towards something behind the character).
    var turningFirst = false

    init(kind: ActivityKind, steps: [Step]) {
        self.kind = kind
        self.steps = steps
    }

    var current: Step? { index < steps.count ? steps[index] : nil }
    var isFinished: Bool { index >= steps.count }

    mutating func advanceStep() {
        index += 1
        started = false
        stepTime = 0
        turningFirst = false
    }

    /// Keep only the running step: an interrupted plan ends as soon as that step completes.
    mutating func truncateAfterCurrent() {
        if index < steps.count { steps = Array(steps[0...index]) }
    }
}

public struct Mood: Sendable, Equatable {
    public var energy = 0.75
    public var curiosity = 0.55
    public var playfulness = 0.45
    public var sociability = 0.25

    public init() {}

    mutating func tick(_ dt: Double, mode: MotorMode) {
        switch mode {
        case .walking: energy -= 0.012 * dt
        case .hopping: energy -= 0.035 * dt
        case .resting: energy += 0.035 * dt
        case .standing, .turning: energy += 0.002 * dt
        }
        curiosity += 0.008 * dt
        playfulness += 0.006 * dt
        sociability += 0.005 * dt
        energy = clamp(energy, 0.05, 1)
        curiosity = clamp(curiosity, 0, 1)
        playfulness = clamp(playfulness, 0, 1)
        sociability = clamp(sociability, 0, 1)
    }

    mutating func finished(_ kind: ActivityKind) {
        switch kind {
        case .visitWindow: curiosity -= 0.35
        case .lookAround: curiosity -= 0.2
        case .play: playfulness -= 0.5
        case .approachUser, .petReaction, .callReaction, .celebrateReaction, .restReaction: sociability = 0
        default: break
        }
        curiosity = clamp(curiosity, 0, 1)
        playfulness = clamp(playfulness, 0, 1)
    }
}

struct ActivitySelector: Sendable {
    private(set) var history: [ActivityKind] = []
    private var lastStart: [ActivityKind: Double] = [:]

    static let cooldown: [ActivityKind: Double] = [
        .nap: 40, .play: 22, .visitWindow: 25, .approachUser: 30, .lookAround: 8,
    ]

    mutating func record(_ kind: ActivityKind, at time: Double) {
        history.append(kind)
        if history.count > 8 { history.removeFirst(history.count - 8) }
        lastStart[kind] = time
    }

    func weights(mood m: Mood, time: Double, reducedMotion: Bool, available: Set<SpotKind>) -> [(ActivityKind, Double)] {
        var w: [(ActivityKind, Double)] = [
            (.idle, 0.8),
            (.wander, 1.0 * (0.4 + m.energy)),
            (.lookAround, 0.7 * (0.6 + m.curiosity)),
            (.visitWindow, available.contains(.window) ? 1.1 * (0.3 + m.curiosity) * (0.5 + 0.5 * m.energy) : 0),
            (.nap, available.contains(.cushion) || reducedMotion ? 1.4 * pow15(1 - m.energy) + 0.05 : 0),
            (.play, available.contains(.toy) ? 1.0 * m.playfulness * (0.3 + m.energy) : 0),
            (.approachUser, available.contains(.front) ? 1.2 * m.sociability * m.sociability : 0),
        ]
        let last = history.last
        let beforeLast = history.count >= 2 ? history[history.count - 2] : nil
        for i in w.indices {
            let kind = w[i].0
            var f = 1.0
            if reducedMotion && kind.travels && kind != .nap { f = 0 }        // nap happens in place
            if let c = ActivitySelector.cooldown[kind], let t = lastStart[kind], time - t < c { f *= 0.05 }
            if kind == last { f *= 0.1 }
            if kind == beforeLast { f *= 0.5 }
            if last == beforeLast, kind == last { f = 0 }                       // never three in a row
            // natural order: wake up and look around after a nap; pause after travelling; get up after idling
            if last == .nap && (kind == .lookAround || kind == .wander) { f *= 2.2 }
            if let last, last.travels && kind == .idle { f *= 1.6 }
            if (last == .idle || last == .settle) && kind.travels { f *= 1.4 }
            w[i].1 *= f
        }
        return w
    }

    mutating func choose(mood: Mood, time: Double, reducedMotion: Bool, available: Set<SpotKind>,
                         rng: inout SplitMix64) -> ActivityKind {
        let w = weights(mood: mood, time: time, reducedMotion: reducedMotion, available: available)
        let total = w.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return .idle }
        var pick = rng.unit() * total
        for (kind, weight) in w {
            pick -= weight
            if pick < 0 { return kind }
        }
        return w.last?.0 ?? .idle
    }
}

@inline(__always) private func pow15(_ v: Double) -> Double { v * max(0, v).squareRoot() }

struct PlanBuilder {
    let profile: MotionProfile
    let stage: StageLayout

    private var stride: Double { profile.walk.strideLength }

    func plan(_ kind: ActivityKind, x: Double, facing: Facing, rng: inout SplitMix64) -> Plan {
        let h = profile.characterHeight
        let eye = profile.eyeHeight
        switch kind {
        case .settle:
            return Plan(kind: kind, steps: [.stand(seconds: 2.4)])
        case .idle:
            return Plan(kind: kind, steps: [.stand(seconds: rng.between(3, 6))])
        case .wander:
            let lo = stage.minX + profile.halfWidth, hi = stage.maxX - profile.halfWidth
            var desired = rng.between(lo, hi)
            if abs(desired - x) < stride { desired = x + (x < (lo + hi) / 2 ? 1 : -1) * stride * rng.between(1.2, 2.4) }
            return Plan(kind: kind, steps: [
                .walk(desiredX: desired, tolerance: stride * 0.55, cruise: rng.between(0.68, 0.85)),
                .stand(seconds: rng.between(1.4, 2.8)),
            ])
        case .lookAround:
            let sideA = facing.sign * h * rng.between(0.9, 1.6)
            var steps: [Step] = [.look(at: Point(x: x + sideA, y: eye * rng.between(0.7, 1.15)), seconds: rng.between(1.1, 1.7))]
            if rng.chance(0.65) {
                steps.append(.face(facing.flipped))
                steps.append(.look(at: Point(x: x - sideA, y: eye * rng.between(0.6, 1.1)), seconds: rng.between(1.1, 1.7)))
            } else {
                steps.append(.look(at: Point(x: x + sideA * 0.5, y: eye * 1.3), seconds: rng.between(0.9, 1.4)))
            }
            steps.append(.stand(seconds: 0.8))
            return Plan(kind: kind, steps: steps)
        case .visitWindow:
            guard let s = stage.spot(.window) else { return plan(.idle, x: x, facing: facing, rng: &rng) }
            var steps: [Step] = [.walk(desiredX: s.x, tolerance: stride * 0.6, cruise: rng.between(0.72, 0.88))]
            if let f = s.facing { steps.append(.face(f)) }
            if let p = s.lookAt { steps.append(.look(at: p, seconds: rng.between(3, 5))) }
            steps.append(.stand(seconds: 1))
            return Plan(kind: kind, steps: steps)
        case .nap:
            var steps: [Step] = []
            if let s = stage.spot(.cushion) {
                steps.append(.walk(desiredX: s.x, tolerance: stride * 0.6, cruise: 0.7))
                if let f = s.facing { steps.append(.face(f)) }
            }
            steps.append(.rest(seconds: rng.between(8, 12)))
            steps.append(.stand(seconds: 1))
            return Plan(kind: kind, steps: steps)
        case .play:
            guard let s = stage.spot(.toy) else { return plan(.idle, x: x, facing: facing, rng: &rng) }
            var steps: [Step] = [.walk(desiredX: s.x, tolerance: stride * 0.5, cruise: 0.95)]
            if let p = s.lookAt {
                steps.append(.faceTowards(x: p.x))
                steps.append(.look(at: p, seconds: 0.8))
            }
            steps.append(.hop)
            steps.append(.stand(seconds: 1.5))
            return Plan(kind: kind, steps: steps)
        case .approachUser:
            let fx = stage.spot(.front)?.x ?? (stage.minX + stage.maxX) / 2
            return Plan(kind: kind, steps: [
                .walk(desiredX: fx, tolerance: stride * 0.6, cruise: 0.85),
                .look(at: stage.userPoint, seconds: rng.between(2, 3)),
                .stand(seconds: 1.5),
            ])
        case .petReaction, .callReaction, .celebrateReaction, .restReaction:
            return plan(.idle, x: x, facing: facing, rng: &rng)         // reactions are built from their stimulus
        }
    }

    func reaction(_ stimulus: Stimulus, x: Double, facing: Facing) -> Plan {
        let center = (stage.minX + stage.maxX) / 2
        switch stimulus {
        case .pet(let p):
            var steps: [Step] = []
            if abs(p.x - x) > profile.characterHeight * 0.35 { steps.append(.faceTowards(x: p.x)) }
            steps.append(.look(at: p, seconds: 1.6))
            steps.append(.stand(seconds: 0.6))
            return Plan(kind: .petReaction, steps: steps)
        case .call(let p):
            return Plan(kind: .callReaction, steps: [
                .faceTowards(x: p.x),
                .look(at: Point(x: p.x, y: max(p.y, 40)), seconds: 0.5),
                .walk(desiredX: p.x, tolerance: stride, cruise: 1.05),     // "come here": near enough, on a cheap stop
                .look(at: stage.userPoint, seconds: 1.2),
                .stand(seconds: 1.0),
            ])
        case .celebrate:
            return Plan(kind: .celebrateReaction, steps: [
                .faceTowards(x: center),
                .look(at: stage.userPoint, seconds: 0.35),
                .hop,
                .look(at: stage.userPoint, seconds: 1.2),
                .stand(seconds: 1.0),
            ])
        case .encourageRest:
            return Plan(kind: .restReaction, steps: [
                .look(at: stage.userPoint, seconds: 1.2),
                .rest(seconds: 3),
                .stand(seconds: 1),
            ])
        }
    }
}
