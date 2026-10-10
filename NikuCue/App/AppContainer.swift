import Combine
import Foundation
import NikuCueDomain
import SpriteKit
import SwiftUI

/// Composition root. Builds the clock, repository, services, localizer and the single cat scene.
/// Views never touch the repository or a ModelContext directly (docs/06 §5).
@MainActor
final class AppContainer: ObservableObject {
    let configuration: AppConfiguration
    let clock: any Clock
    let repository: any HabitRepository
    let habitService: HabitService
    let localizer: Localizer
    let reactionCatalog: ReactionCatalog
    let rigSpec: RigSpec
    let artPaths: ArtPaths
    let animationSpec: AnimationSpec
    let artProvider: VectorArtProvider
    let rig: CatRig
    let scene: CatScene
    private(set) var reactionEngine: CatReactionEngine

    /// Problems found while validating the bundled contracts at start-up (shown in Debug only).
    let contractProblems: [String]

    init(configuration: AppConfiguration = .current, repository: (any HabitRepository)? = nil, clock: any Clock = SystemClock()) throws {
        self.configuration = configuration
        self.clock = clock
        let repo = repository ?? InMemoryHabitRepository()
        self.repository = repo
        self.habitService = HabitService(repository: repo, clock: clock)
        self.localizer = Localizer(catalog: try Localizer.loadBundled())

        reactionCatalog = try ReactionCatalog.load(from: try BundledResources.data(named: "reactions", extension: "json", subdirectory: "Reactions"))
        rigSpec = try RigSpec.load(from: try BundledResources.data(named: "character_spec", extension: "json", subdirectory: "Character"))
        artPaths = try ArtPaths.load(from: try BundledResources.data(named: "mali_paths", extension: "json", subdirectory: "Character"))
        animationSpec = try AnimationSpec.load(from: try BundledResources.data(named: "animations", extension: "json", subdirectory: "Character"))

        var problems = rigSpec.validate()
        problems += animationSpec.validate(against: rigSpec)
        problems += reactionCatalog.validate(knownMessageKeys: Set(localizer.catalog.tables["en"]?.keys.map { $0 } ?? []))
        contractProblems = problems

        artProvider = VectorArtProvider(paths: artPaths)
        // Textures are rendered for the largest room (≈260 pt tall) at the device scale; the rig is scaled as a whole.
        let unitsPerPoint = rigSpec.canvas.height / 300
        let pixelsPerUnit = CGFloat(1 / unitsPerPoint) * UIScreen.main.scale
        rig = CatRig(spec: rigSpec, art: artProvider, pixelsPerUnit: pixelsPerUnit)
        let library = AnimationLibrary(spec: animationSpec)
        scene = CatScene(size: CGSize(width: 390, height: 260), rig: rig, library: library, seed: UInt64.random(in: 0...UInt64.max))
        reactionEngine = CatReactionEngine(catalog: reactionCatalog)
    }

    // MARK: Cat event routing

    /// Feeds an event through the pure engine and hands any intent to the scene controller.
    func dispatch(_ event: CatEvent, snapshot: ReactionSnapshot) {
        guard let intent = reactionEngine.intent(for: event, snapshot: snapshot) else { return }
        scene.controller.handle(intent)
    }

    /// Demo path (onboarding "meet the cat", gallery): no statistics, no milestone tokens.
    func dispatchDemo(kind: CatEventKind, category: HabitCategory? = nil) {
        let day = CalendarService(clock: clock).dayKey(for: clock.now)
        let event = CatEvent(kind: kind, occurredAt: clock.now, dayKey: day, category: category, isDemo: true)
        dispatch(event, snapshot: .demo(dayKey: day))
    }

    var currentTimeOfDay: TimeOfDay {
        TimeOfDay(hour: CalendarService(clock: clock).hour(of: clock.now))
    }
}
