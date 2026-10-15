import CatBehavior
import Darwin
import Foundation
import QuartzCore

/// Measurements taken while the lab runs. The same definitions are used by the browser harness (web/harness.js),
/// so Simulator and browser numbers are comparable:
///  - foot slide: horizontal world movement of a foot while it is on the ground (y ≤ ground tolerance on two
///    consecutive frames), split by what the body was doing (steady walk, clip blend, turn, standing, hop);
///  - root step: largest per-frame root movement (a teleport would show up here);
///  - facing flips that do not coincide with the start of a turn clip;
///  - clip drift: base-track time in the renderer minus the time the engine expects;
///  - frame intervals and memory (phys_footprint, the number iOS uses for jetsam limits).
@MainActor
final class Diagnostics {
    struct SlideStats: Encodable {
        var frames = 0
        var total = 0.0
        var maxStep = 0.0
        var maxRunDrift = 0.0
        /// Largest total grounded-foot slide inside one occurrence (one blend, one turn, one walk), both feet.
        var maxOccurrence = 0.0
    }

    private(set) var frameCount = 0
    private var intervals: [Double] = []
    private var lastFrameTime: CFTimeInterval?
    private var previous: RenderState?
    private var lastBaseSerialTime: [Int: Double] = [:]
    private var serialFrom: [Int: String] = [:]
    private(set) var maxRootStep = 0.0
    private(set) var facingFlipsOutsideTurn = 0
    private(set) var maxClipDrift = 0.0
    private var slide: [String: SlideStats] = [:]
    private var occurrence: [String: Double] = [:]
    private var feetPrev: [String: (x: Double, y: Double)] = [:]
    private var runStart: [String: (x: Double, context: [String: Int])] = [:]
    private var memory: [[Double]] = []
    private var lastMemorySample: CFTimeInterval = 0
    private(set) var log: [String] = []
    private var lifecycle: [[String: String]] = []
    private var activityCounts: [String: Int] = [:]
    private var stimulusLatency: [String: [Double]] = [:]
    private var pendingStimuli: [(kind: StimulusKind, time: Double)] = []

    var groundTolerance = 17.2

    func frame(_ s: RenderState, now: CFTimeInterval) {
        frameCount += 1
        if let last = lastFrameTime { intervals.append(now - last) }
        lastFrameTime = now
        if let p = previous {
            maxRootStep = max(maxRootStep, abs(s.x - p.x))
            if s.facing != p.facing && !(s.base.serial != p.base.serial && s.mode == .turning) { facingFlipsOutsideTurn += 1 }
        }
        if previous?.base.serial != s.base.serial {
            lastBaseSerialTime[s.base.serial] = s.time
            serialFrom[s.base.serial] = previous?.base.clip ?? "start"
        }
        previous = s
        if now - lastMemorySample >= 1 {
            lastMemorySample = now
            memory.append([s.time, Diagnostics.physFootprintMB()])
        }
    }

    /// What the body is doing this frame, for attributing foot slide ("blend:walk>idle" names the transition).
    func context(of s: RenderState) -> String {
        let sinceClip = s.time - (lastBaseSerialTime[s.base.serial] ?? -1)
        if sinceClip < s.base.mix + 1e-6 { return "blend:\(serialFrom[s.base.serial] ?? "?")>\(s.base.clip)" }
        switch s.mode {
        case .walking: return "walk"
        case .turning: return "turn"
        case .hopping: return "hop"
        case .standing, .resting: return "stand"
        }
    }

    /// Foot world positions (stage units) after the renderer updated the skeleton.
    func feet(_ positions: [String: (x: Double, y: Double)], state s: RenderState) {
        let ctx = context(of: s)
        for (id, p) in positions {
            defer { feetPrev[id] = p }
            guard let q = feetPrev[id] else { continue }
            let grounded = p.y <= groundTolerance && q.y <= groundTolerance
            if grounded {
                let d = abs(p.x - q.x)
                var st = slide[ctx] ?? SlideStats()
                st.frames += 1
                st.total += d
                st.maxStep = max(st.maxStep, d)
                let key = "\(ctx)#\(s.base.serial)"
                occurrence[key, default: 0] += d
                st.maxOccurrence = max(st.maxOccurrence, occurrence[key] ?? 0)
                slide[ctx] = st
                if runStart[id] == nil { runStart[id] = (q.x, [:]) }
                runStart[id]?.context[ctx, default: 0] += 1
            } else if let run = runStart[id] {
                closeRun(id: id, run: run, endX: q.x)
            }
        }
    }

    private func closeRun(id: String, run: (x: Double, context: [String: Int]), endX: Double) {
        runStart[id] = nil
        guard let dominant = run.context.max(by: { $0.value < $1.value })?.key else { return }
        var st = slide[dominant] ?? SlideStats()
        st.maxRunDrift = max(st.maxRunDrift, abs(endX - run.x))
        slide[dominant] = st
    }

    func drift(engineClipTime: Double, rendererTrackTime: Double, mode: MotorMode) {
        guard mode == .walking else { return }
        maxClipDrift = max(maxClipDrift, abs(engineClipTime - rendererTrackTime))
    }

    func events(_ events: [TimedEvent]) {
        for e in events {
            switch e.event {
            case .activityStarted(let k):
                activityCounts[k.rawValue, default: 0] += 1
                note(e.time, "activity \(k.rawValue)")
            case .stimulusReceived(let k):
                pendingStimuli.append((k, e.time))
            case .stimulusApplied(let k):
                if let i = pendingStimuli.firstIndex(where: { $0.kind == k }) {
                    stimulusLatency[k.rawValue, default: []].append(e.time - pendingStimuli[i].time)
                    pendingStimuli.removeAll { $0.kind == k }
                }
                note(e.time, "applied \(k.rawValue)")
            case .stimulusAcknowledged(let k, let reason):
                pendingStimuli.removeAll { $0.kind == k }       // a glance only: no body reaction follows
                note(e.time, "glance \(k.rawValue) (\(reason))")
            case .stimulusDropped(let k, let reason):
                pendingStimuli.removeAll { $0.kind == k }
                note(e.time, "dropped \(k.rawValue) (\(reason))")
            case .facingChanged(let f):
                note(e.time, "turn → \(f == .left ? "left" : "right")")
            case .arrived(let x, let phase):
                note(e.time, String(format: "stop x=%.0f phase=%.3f", x, phase))
            case .paused(let p):
                note(e.time, p ? "paused" : "resumed")
            case .reducedMotion(let on):
                note(e.time, "reduce motion \(on)")
            default:
                break
            }
        }
    }

    func lifecycle(_ phase: String, engine: CatBehaviorEngine) {
        lifecycle.append([
            "phase": phase,
            "wallClock": String(format: "%.3f", CACurrentMediaTime()),
            "engineTime": String(format: "%.4f", engine.time),
            "x": String(format: "%.3f", engine.x),
            "paused": "\(engine.isPaused)",
        ])
    }

    func mark(_ text: String, at t: Double) { note(t, text) }

    private func note(_ t: Double, _ text: String) {
        log.append(String(format: "%6.2fs %@", t, text))
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    var recentLog: [String] { Array(log.suffix(6)) }

    var fps: Double {
        let recent = intervals.suffix(60)
        guard !recent.isEmpty else { return 0 }
        return Double(recent.count) / recent.reduce(0, +)
    }

    var lastMemoryMB: Double { memory.last?[1] ?? Diagnostics.physFootprintMB() }

    func summary(extra: [String: String]) -> [String: Any] {
        let sorted = intervals.sorted()
        func pct(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        var slideOut: [String: Any] = [:]
        for (k, v) in slide {
            slideOut[k] = ["frames": v.frames, "total": v.total, "maxStep": v.maxStep, "maxRunDrift": v.maxRunDrift,
                           "maxOccurrence": v.maxOccurrence,
                           "meanPerFrame": v.frames > 0 ? v.total / Double(v.frames) : 0]
        }
        let mem = memory.map { $0[1] }.filter { $0 > 0 }
        return [
            "extra": extra,
            "frames": frameCount,
            "frameInterval": ["median": pct(0.5), "p95": pct(0.95), "max": sorted.last ?? 0],
            "maxRootStep": maxRootStep,
            "facingFlipsOutsideTurn": facingFlipsOutsideTurn,
            "maxClipDriftWalking": maxClipDrift,
            "footSlide": slideOut,
            "memoryMB": ["min": mem.min() ?? 0, "max": mem.max() ?? 0, "last": mem.last ?? 0, "samples": memory],
            "activities": activityCounts,
            "stimulusLatency": stimulusLatency,
            "lifecycle": lifecycle,
            "log": log,
        ]
    }

    func write(name: String, extra: [String: String]) -> URL? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("diagnostics-\(name).json")
        guard let data = try? JSONSerialization.data(withJSONObject: summary(extra: extra), options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        try? data.write(to: url)
        return url
    }

    /// Memory the system charges to the app (what jetsam limits use), in MB.
    nonisolated static func physFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}
