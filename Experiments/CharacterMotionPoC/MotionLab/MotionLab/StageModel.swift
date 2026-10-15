import CatBehavior
import Combine
import QuartzCore
import SwiftUI
import UIKit

/// One line to stdout, flushed at once (stdout is a file under `simctl launch --stdout`, which would buffer it).
func labLog(_ line: String) {
    print(line)
    fflush(stdout)
}

/// Owns the behaviour engine and everything around it (lifecycle, Reduce Motion, input, diagnostics). The active
/// renderer calls `tick` once per frame before it updates its skeleton and applies the returned `RenderState`.
@MainActor
final class StageModel: ObservableObject {
    struct HUD: Equatable {
        var activity = ""
        var mode = ""
        var x = 0.0
        var fps = 0.0
        var memoryMB = 0.0
        var log: [String] = []
        var scenarioRemaining: Double?
    }

    struct TapMark: Identifiable, Equatable {
        let id = UUID()
        var point: Point
        var scripted: Bool
        var born: Date
    }

    let config: LabConfig
    let profile = MotionProfile.spineboyEvaluation
    let stage: StageLayout
    /// Extra room drawn under the floor line (stage units).
    let floorDepth = 140.0
    @Published var renderer: RendererKind
    @Published var appReduceMotion = false
    @Published private(set) var systemReduceMotion = UIAccessibility.isReduceMotionEnabled
    @Published private(set) var hud = HUD()
    @Published private(set) var taps: [TapMark] = []
    @Published var showHUD: Bool
    @Published private(set) var isActive = true
    @Published private(set) var scenarioFinished = false

    private(set) var engine: CatBehaviorEngine
    private(set) var state: RenderState
    /// Seconds the engine actually advanced in the last frame (0 while paused, at most `maxStep` after a hitch).
    /// Renderers advance their clips by exactly this, so the engine is the only clock.
    private(set) var lastEngineStep = 0.0
    let diagnostics = Diagnostics()
    private var lastTick: CFTimeInterval?
    private var startTime: CFTimeInterval?
    private var lastHUD: CFTimeInterval = 0
    private var script: ScriptedInput?
    private var observers: [NSObjectProtocol] = []

    init(config: LabConfig) {
        self.config = config
        renderer = config.renderer
        showHUD = config.showHUD
        appReduceMotion = config.forceReduceMotion
        let room = StageLayout.evaluationRoom(width: 1800, height: 1500)
        var engine = CatBehaviorEngine(profile: MotionProfile.spineboyEvaluation, stage: room, seed: config.seed,
                                       startX: 1800 * 0.4, facing: .right)
        let first = engine.step(0)
        stage = room
        self.engine = engine
        state = first
        diagnostics.groundTolerance = 17.2
        script = ScriptedInput(scenario: config.scenario)
        observers.append(NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemReduceMotion = UIAccessibility.isReduceMotionEnabled }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.diagnostics.mark("memory warning", at: self?.engine.time ?? 0) }
        })
        labLog("ML_START scenario=\(config.scenario ?? "interactive") renderer=\(config.renderer.rawValue) seed=\(config.seed) systemReduceMotion=\(systemReduceMotion)")
    }

    var effectiveReduceMotion: Bool { appReduceMotion || systemReduceMotion }

    /// Stage units → view points (the stage view keeps the stage aspect ratio, so this is one uniform scale).
    func viewScale(for size: CGSize) -> CGFloat { size.width / CGFloat(stage.maxX - stage.minX) }

    func stagePoint(fromView p: CGPoint, size: CGSize) -> Point {
        let s = Double(viewScale(for: size))
        return Point(x: stage.minX + Double(p.x) / s, y: Double(size.height - p.y) / s - floorDepth)
    }

    func viewPoint(fromStage p: Point, size: CGSize) -> CGPoint {
        let s = viewScale(for: size)
        return CGPoint(x: CGFloat(p.x - stage.minX) * s, y: size.height - CGFloat(p.y + floorDepth) * s)
    }

    // MARK: Frame

    func tick(now: CFTimeInterval) -> RenderState {
        let raw = lastTick.map { now - $0 } ?? 0
        lastTick = now
        if startTime == nil { startTime = now }
        engine.setReducedMotion(effectiveReduceMotion)
        if let script, let start = startTime, !scenarioFinished {
            script.fire(elapsed: now - start, model: self)
        }
        let before = engine.time
        state = engine.step(raw)
        lastEngineStep = engine.time - before
        diagnostics.frame(state, now: now)
        diagnostics.events(engine.drainEvents())
        if now - lastHUD > 0.25 {
            lastHUD = now
            updateHUD(now: now)
        }
        if let start = startTime, config.scenario != nil, !scenarioFinished, now - start >= config.seconds {
            finishScenario()
        }
        return state
    }

    private func updateHUD(now: CFTimeInterval) {
        var h = HUD()
        h.activity = state.activity.rawValue
        h.mode = state.mode.rawValue
        h.x = state.x
        h.fps = diagnostics.fps
        h.memoryMB = diagnostics.lastMemoryMB
        h.log = diagnostics.recentLog
        if let start = startTime, config.scenario != nil { h.scenarioRemaining = max(0, config.seconds - (now - start)) }
        hud = h
        taps.removeAll { Date().timeIntervalSince($0.born) > 1.2 }
    }

    // MARK: Input

    /// A tap on the stage (from the gesture, or from the CI script through the same path).
    func tap(at p: Point, scripted: Bool = false) {
        taps.append(TapMark(point: p, scripted: scripted, born: Date()))
        let onCharacter = abs(p.x - state.x) < profile.halfWidth * 0.9 && p.y > -40 && p.y < profile.characterHeight * 1.1
            + (state.mode == .hopping ? 700 : 0)
        engine.send(onCharacter ? .pet(at: p) : .call(to: Point(x: p.x, y: max(0, p.y))))
    }

    func celebrate() { engine.send(.celebrate) }
    func encourageRest() { engine.send(.encourageRest) }

    // MARK: Lifecycle

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        engine.setPaused(!active)
        diagnostics.lifecycle(active ? "active" : "inactive", engine: engine)
        diagnostics.events(engine.drainEvents())
        if active { lastTick = nil }          // the first frame after resume starts from zero, not the time away
        labLog("ML_LIFECYCLE \(active ? "active" : "inactive") engineTime=\(engine.time) x=\(engine.x)")
    }

    private func finishScenario() {
        scenarioFinished = true
        let name = "\(config.scenario ?? "interactive")-\(renderer.rawValue)"
        let url = diagnostics.write(name: name, extra: [
            "scenario": config.scenario ?? "interactive",
            "renderer": renderer.rawValue,
            "seed": "\(config.seed)",
            "seconds": "\(config.seconds)",
            "reduceMotion": "\(effectiveReduceMotion)",
            "systemReduceMotion": "\(systemReduceMotion)",
            "profile": profile.name,
            "device": UIDevice.current.model + " " + UIDevice.current.systemVersion,
        ])
        labLog("ML_DIAG_DONE \(url?.path ?? "write failed")")
    }
}
