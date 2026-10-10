import Foundation

/// One running interaction plus at most one waiting interaction (docs/05 §5).
///
/// Aggregates are always fully applied in the database; only the *display* of reactions is limited.
public struct ReactionQueue: Sendable, Equatable {
    public static let maxWaiting = 1

    public private(set) var current: ReactionIntent?
    public private(set) var waiting: ReactionIntent?

    public init() {}

    public enum EnqueueOutcome: Equatable, Sendable {
        case startNow(ReactionIntent)
        case queued(ReactionIntent)
        case dropped
    }

    /// Adds an intent. Non-queueable intents (pet, greet…) are dropped while busy; otherwise the
    /// waiting slot is replaced so the final reaction matches the latest state.
    public mutating func enqueue(_ intent: ReactionIntent) -> EnqueueOutcome {
        if current == nil {
            current = intent
            return .startNow(intent)
        }
        guard intent.isQueueable else { return .dropped }
        waiting = intent
        return .queued(intent)
    }

    /// Marks the running interaction finished and promotes the waiting one if `isStillValid` accepts it.
    /// Returns the intent to start next, if any.
    public mutating func finishCurrent(isStillValid: (ReactionIntent) -> Bool) -> ReactionIntent? {
        current = nil
        guard let next = waiting else { return nil }
        waiting = nil
        guard isStillValid(next) else { return nil }
        current = next
        return next
    }

    /// Drops everything (scene left, modal presented, app backgrounded). The database is untouched.
    public mutating func discardAll() {
        current = nil
        waiting = nil
    }

    /// Removes queued or running intents matching `predicate` (e.g. an undone completion).
    /// Returns true when the running interaction was cancelled.
    @discardableResult
    public mutating func cancel(where predicate: (ReactionIntent) -> Bool) -> Bool {
        if let w = waiting, predicate(w) { waiting = nil }
        if let c = current, predicate(c) {
            current = nil
            return true
        }
        return false
    }

    public var isBusy: Bool { current != nil }
}
