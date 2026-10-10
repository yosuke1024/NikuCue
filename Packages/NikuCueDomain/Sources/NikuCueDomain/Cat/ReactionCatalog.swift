import Foundation

/// Decoded `reactions.json`. Entries are declarations; `CatReactionEngine` is the evaluator.
public struct ReactionCatalog: Codable, Sendable {
    public struct Conditions: Codable, Sendable, Equatable {
        public var category: HabitCategory?
        public var cooldownMs: Int?
        public var allScheduledDone: Bool?
        public var oncePerDay: Bool?
        public var allResolved: Bool?
        public var hasSkipped: Bool?
        public var hasDone: Bool?
        public var galleryOnlyInV1: Bool?
        public var distinctDoneDaysReached: Int?
        public var notPreviouslyShown: Bool?

        public init() {}
    }

    public struct Item: Codable, Sendable, Equatable {
        public var id: String
        public var event: String
        public var clipId: ClipID
        public var priority: Int
        public var when: Conditions
        public var messageKeys: [String]
        public var textDwellMs: Int
    }

    public var schemaVersion: Int
    public var items: [Item]

    public init(schemaVersion: Int = 1, items: [Item]) {
        self.schemaVersion = schemaVersion
        self.items = items
    }

    public static func load(from data: Data) throws -> ReactionCatalog {
        try JSONDecoder().decode(ReactionCatalog.self, from: data)
    }

    public func item(id: String) -> Item? {
        items.first { $0.id == id }
    }

    public func items(event: String) -> [Item] {
        items.filter { $0.event == event }
    }

    /// Structural checks run by tests and at debug start-up: unique ids, known clips, non-empty keys.
    public func validate(knownMessageKeys: Set<String>) -> [String] {
        var problems: [String] = []
        let ids = items.map(\.id)
        if Set(ids).count != ids.count { problems.append("duplicate reaction ids") }
        for item in items {
            if item.messageKeys.isEmpty { problems.append("\(item.id): no messageKeys") }
            for key in item.messageKeys where !knownMessageKeys.contains(key) {
                problems.append("\(item.id): unknown message key \(key)")
            }
            if item.textDwellMs <= 0 { problems.append("\(item.id): textDwellMs must be positive") }
        }
        for required in ["greeting", "returning", "pet", "complete_generic", "complete_water", "complete_stretch",
                         "complete_read", "complete_tidy", "rest", "all_done", "all_resolved", "cheer", "doze",
                         "milestone_3", "milestone_7", "milestone_14"] where item(id: required) == nil {
            problems.append("missing reaction \(required)")
        }
        return problems
    }
}
