import Foundation
import XCTest
@testable import NikuCueDomain

/// Locates files in the repository (for tests that validate the bundled JSON contracts).
enum RepoFiles {
    static var root: URL {
        // …/Packages/NikuCueDomain/Tests/NikuCueDomainTests/Helpers.swift → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    static func data(_ relative: String) throws -> Data {
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("repository file not found: \(relative)")
        }
        return try Data(contentsOf: url)
    }
}

enum Fixtures {
    static let bangkok = TimeZone(identifier: "Asia/Bangkok")!
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    static let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    static let newYork = TimeZone(identifier: "America/New_York")!
    static let utc = TimeZone(identifier: "UTC")!

    static func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    static func day(_ s: String) -> DayKey { DayKey(string: s)! }

    /// 2026-10-10 12:00 Bangkok (a Saturday, ISO weekday 6).
    static func clock(_ iso: String = "2026-10-10T05:00:00Z", zone: TimeZone = bangkok) -> ManualClock {
        ManualClock(now: date(iso), timeZone: zone)
    }

    static func catalog() throws -> ReactionCatalog {
        try ReactionCatalog.load(from: try RepoFiles.data("NikuCue/Resources/Reactions/reactions.json"))
    }

    /// Minimal catalog for engine tests that must not depend on repository files.
    static func syntheticCatalog() -> ReactionCatalog {
        func item(_ id: String, _ event: String, _ clip: ClipID, _ priority: Int, _ keys: [String], _ when: (inout ReactionCatalog.Conditions) -> Void = { _ in }) -> ReactionCatalog.Item {
            var c = ReactionCatalog.Conditions()
            when(&c)
            return ReactionCatalog.Item(id: id, event: event, clipId: clip, priority: priority, when: c, messageKeys: keys, textDwellMs: 4000)
        }
        return ReactionCatalog(items: [
            item("greeting", "sceneEntered", .greet, 40, ["reaction.greet.1", "reaction.greet.2"]),
            item("returning", "welcomeBack", .greet, 45, ["reaction.return.1", "reaction.return.2"]),
            item("pet", "petTapped", .pet, 30, ["reaction.pet.1", "reaction.pet.2", "reaction.pet.3"]) { $0.cooldownMs = 2000 },
            item("complete_generic", "completionCommitted", .celebrate, 60, ["reaction.complete.1", "reaction.complete.2", "reaction.complete.3", "reaction.complete.4"]) { $0.category = .custom },
            item("complete_water", "completionCommitted", .celebrate, 60, ["reaction.water.1", "reaction.water.2"]) { $0.category = .water },
            item("complete_stretch", "completionCommitted", .celebrate, 60, ["reaction.stretch.1", "reaction.stretch.2"]) { $0.category = .stretch },
            item("complete_read", "completionCommitted", .celebrate, 60, ["reaction.read.1", "reaction.read.2"]) { $0.category = .read },
            item("complete_tidy", "completionCommitted", .celebrate, 60, ["reaction.tidy.1", "reaction.tidy.2"]) { $0.category = .tidy },
            item("rest", "skipCommitted", .settle, 35, ["reaction.rest.1", "reaction.rest.2", "reaction.rest.3"]),
            item("all_done", "completionCommitted", .celebrate, 80, ["reaction.allDone.1", "reaction.allDone.2"]) { $0.allScheduledDone = true; $0.oncePerDay = true },
            item("all_resolved", "completionCommitted", .settle, 55, ["reaction.resolved.1"]) { $0.allResolved = true; $0.hasSkipped = true; $0.hasDone = true },
            item("cheer", "userRequestedEncouragement", .cheer, 20, ["reaction.cheer.1", "reaction.cheer.2"]),
            item("doze", "nightAmbient", .doze, 10, ["reaction.doze.1"]),
            item("milestone_3", "completionCommitted", .milestone, 100, ["reaction.milestone.3"]) { $0.distinctDoneDaysReached = 3; $0.notPreviouslyShown = true },
            item("milestone_7", "completionCommitted", .milestone, 100, ["reaction.milestone.7"]) { $0.distinctDoneDaysReached = 7; $0.notPreviouslyShown = true },
            item("milestone_14", "completionCommitted", .milestone, 100, ["reaction.milestone.14"]) { $0.distinctDoneDaysReached = 14; $0.notPreviouslyShown = true },
        ])
    }
}
