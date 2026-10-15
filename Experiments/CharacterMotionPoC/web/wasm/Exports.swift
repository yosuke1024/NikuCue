// C-ABI surface of the CatBehavior engine for the browser harness (compiled together with
// ../../CatBehavior/Sources/CatBehavior/*.swift into one WebAssembly module by build_wasm.sh).
// The harness calls these once per frame; numbers go through a Float64 buffer, strings through a UTF-8 buffer.

nonisolated(unsafe) private var engine: CatBehaviorEngine?
nonisolated(unsafe) private var out = [Double](repeating: 0, count: 32)
nonisolated(unsafe) private var text: [UInt8] = []
nonisolated(unsafe) private var lastState: RenderState?
nonisolated(unsafe) private var planter = FootPlanter(groundTolerance: 17.2)

private let clipNames: [String] = {
    let p = MotionProfile.spineboyEvaluation
    var names: [String] = []
    for n in [p.idle.name, p.rest.name, p.walk.clip.name, p.turn.name, p.hop.name, p.look?.name ?? ""] where !names.contains(n) {
        names.append(n)
    }
    return names
}()

private let modes: [MotorMode] = [.standing, .resting, .walking, .turning, .hopping]

@_expose(wasm, "cb_create")
@_cdecl("cb_create")
public func cb_create(_ seed: Double, _ width: Double, _ height: Double, _ startX: Double, _ facing: Int32) {
    engine = CatBehaviorEngine(profile: .spineboyEvaluation, stage: .evaluationRoom(width: width, height: height),
                               seed: UInt64(seed), startX: startX, facing: facing < 0 ? .left : .right)
}

@_expose(wasm, "cb_state_ptr")
@_cdecl("cb_state_ptr")
public func cb_state_ptr() -> UnsafeMutablePointer<Double> {
    out.withUnsafeMutableBufferPointer { $0.baseAddress! }
}

/// Steps the engine and writes the RenderState into the state buffer (layout documented in web/harness.js).
@_expose(wasm, "cb_step")
@_cdecl("cb_step")
public func cb_step(_ dt: Double) {
    guard var e = engine else { return }
    let s = e.step(dt)
    engine = e
    lastState = s
    out[0] = s.time
    out[1] = s.x
    out[2] = s.facing.sign
    out[3] = Double(clipNames.firstIndex(of: s.base.clip) ?? -1)
    out[4] = s.base.loop ? 1 : 0
    out[5] = s.base.startTime
    out[6] = s.base.mix
    out[7] = Double(s.base.serial)
    out[8] = s.base.freezePrevious ? 1 : 0
    out[9] = s.baseTimeScale
    out[10] = s.baseClipTime
    out[11] = s.look == nil ? 0 : 1
    out[12] = Double(s.look.flatMap { clipNames.firstIndex(of: $0.clip) } ?? -1)
    out[13] = s.look?.alpha ?? 0
    out[14] = s.look?.mixIn ?? 0
    out[15] = Double(s.look?.serial ?? 0)
    out[16] = s.look?.target.x ?? 0
    out[17] = s.look?.target.y ?? 0
    out[18] = s.lookOutMix
    out[19] = Double(modes.firstIndex(of: s.mode) ?? -1)
    out[20] = Double(ActivityKind.allCases.firstIndex(of: s.activity) ?? -1)
    out[21] = s.reducedMotion ? 1 : 0
    out[22] = s.paused ? 1 : 0
}

/// Foot planting: animated foot-target world positions in, planted positions out (state buffer slots 24...27).
@_expose(wasm, "cb_plant")
@_cdecl("cb_plant")
public func cb_plant(_ fx: Double, _ fy: Double, _ rx: Double, _ ry: Double) {
    guard let s = lastState else { return }
    let o = planter.solve([Point(x: fx, y: fy), Point(x: rx, y: ry)], state: s)
    out[24] = o[0].x
    out[25] = o[0].y
    out[26] = o[1].x
    out[27] = o[1].y
}

/// kind: 0 pet, 1 call, 2 celebrate, 3 encourageRest
@_expose(wasm, "cb_send")
@_cdecl("cb_send")
public func cb_send(_ kind: Int32, _ x: Double, _ y: Double) {
    guard var e = engine else { return }
    switch kind {
    case 0: e.send(.pet(at: Point(x: x, y: y)))
    case 1: e.send(.call(to: Point(x: x, y: y)))
    case 2: e.send(.celebrate)
    default: e.send(.encourageRest)
    }
    engine = e
}

@_expose(wasm, "cb_set_reduced_motion")
@_cdecl("cb_set_reduced_motion")
public func cb_set_reduced_motion(_ on: Int32) {
    engine?.setReducedMotion(on != 0)
}

@_expose(wasm, "cb_set_paused")
@_cdecl("cb_set_paused")
public func cb_set_paused(_ on: Int32) {
    engine?.setPaused(on != 0)
}

private func publish(_ s: String) -> Int32 {
    text = Array(s.utf8)
    return Int32(text.count)
}

@_expose(wasm, "cb_text_ptr")
@_cdecl("cb_text_ptr")
public func cb_text_ptr() -> UnsafeMutablePointer<UInt8> {
    if text.isEmpty { text = [0] }
    return text.withUnsafeMutableBufferPointer { $0.baseAddress! }
}

/// Static tables as JSON: clip names, motor modes, activities. Returns the byte length (read via cb_text_ptr).
@_expose(wasm, "cb_tables")
@_cdecl("cb_tables")
public func cb_tables() -> Int32 {
    func list(_ a: [String]) -> String { "[" + a.map { "\"\($0)\"" }.joined(separator: ",") + "]" }
    let p = MotionProfile.spineboyEvaluation
    return publish("{\"clips\":\(list(clipNames)),\"modes\":\(list(modes.map(\.rawValue))),"
        + "\"activities\":\(list(ActivityKind.allCases.map(\.rawValue))),"
        + "\"characterHeight\":\(p.characterHeight),\"halfWidth\":\(p.halfWidth),\"maxStep\":\(EngineConfig().maxStep)}")
}

/// Drains engine events as a JSON array of [time, "description"]. Returns the byte length.
@_expose(wasm, "cb_events")
@_cdecl("cb_events")
public func cb_events() -> Int32 {
    guard var e = engine else { return publish("[]") }
    let events = e.drainEvents()
    engine = e
    var parts: [String] = []
    for t in events {
        let d: String
        switch t.event {
        case .activityStarted(let k): d = "activity \(k.rawValue)"
        case .activityFinished(let k): d = "finished \(k.rawValue)"
        case .clipStarted(let n, let mix): d = "clip \(n) mix=\(mix)"
        case .facingChanged(let f): d = "turn \(f == .left ? "left" : "right")"
        case .walkPlanned(let a, let b): d = "walk \(Int(a))->\(Int(b))"
        case .stopRequested(let x, let ph): d = "stopRequested \(Int(x)) phase=\(ph)"
        case .arrived(let x, let ph): d = "stop \(Int(x)) phase=\(ph)"
        case .stimulusReceived(let k): d = "received \(k.rawValue)"
        case .stimulusApplied(let k): d = "applied \(k.rawValue)"
        case .stimulusAcknowledged(let k, let r): d = "glance \(k.rawValue) \(r)"
        case .stimulusDropped(let k, let r): d = "dropped \(k.rawValue) \(r)"
        case .paused(let p): d = p ? "paused" : "resumed"
        case .reducedMotion(let on): d = "reduceMotion \(on)"
        }
        parts.append("[\(t.time),\"\(d)\"]")
    }
    return publish("[" + parts.joined(separator: ",") + "]")
}
