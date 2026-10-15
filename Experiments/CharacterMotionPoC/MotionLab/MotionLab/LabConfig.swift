import Foundation

/// Which renderer draws the character. Both are driven by the same `CatBehaviorEngine`.
enum RendererKind: String, CaseIterable, Identifiable {
    /// Official spine-ios runtime (skeletal animation, mixing, IK look-at).
    case spine
    /// SpriteKit flipbook: frames pre-rendered at 24 fps (baked from the same Spine data at launch, standing in for
    /// an artist's sprite sheets) played on an `SKSpriteNode`.
    case flipbook

    var id: String { rawValue }
    var label: String { self == .spine ? "Spine" : "SpriteKit flipbook" }
}

/// Launch configuration. Scenarios exist for unattended Simulator runs (CI recordings); without one the lab is
/// interactive. Arguments use the UserDefaults argument domain, e.g. `-MLScenario interaction -MLSeconds 90`.
struct LabConfig {
    var scenario: String?
    var seconds: Double
    var seed: UInt64
    var renderer: RendererKind
    var forceReduceMotion: Bool
    var showHUD: Bool
    /// Pin grounded feet during clip blends (Spine only). `-MLFootPlanting NO` shows the raw blends.
    var footPlanting: Bool

    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> LabConfig {
        let scenario = defaults.string(forKey: "MLScenario")
        let seconds = defaults.double(forKey: "MLSeconds")
        let seed = defaults.string(forKey: "MLSeed").flatMap { UInt64($0) } ?? 7
        let renderer = defaults.string(forKey: "MLRenderer").flatMap(RendererKind.init(rawValue:)) ?? .spine
        return LabConfig(scenario: scenario, seconds: seconds > 0 ? seconds : 90, seed: seed, renderer: renderer,
                         forceReduceMotion: defaults.bool(forKey: "MLReduceMotion"),
                         showHUD: defaults.object(forKey: "MLShowHUD") == nil ? true : defaults.bool(forKey: "MLShowHUD"),
                         footPlanting: defaults.object(forKey: "MLFootPlanting") == nil ? true : defaults.bool(forKey: "MLFootPlanting"))
    }
}
