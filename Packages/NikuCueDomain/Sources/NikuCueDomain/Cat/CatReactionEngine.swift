import Foundation

/// Snapshot + event → at most one `ReactionIntent`. No I/O, deterministic with a seeded generator.
///
/// Selection order for `completionCommitted` (docs/05 §4): milestone → all_done → all_resolved →
/// category → generic. Milestone and all_done are never shown together; when both apply the
/// milestone intent also consumes the all-done token for that day.
public struct CatReactionEngine: Sendable {
    public static let petCooldownMs = 2000

    public let catalog: ReactionCatalog
    private var rng: SeededRandomNumberGenerator
    private var lastPetAt: Date?
    /// Last two message keys shown per reaction id, to avoid immediate repeats (docs/05 §7).
    private var recentMessages: [String: [String]] = [:]

    public init(catalog: ReactionCatalog, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.catalog = catalog
        self.rng = SeededRandomNumberGenerator(seed: seed)
    }

    public mutating func intent(for event: CatEvent, snapshot: ReactionSnapshot) -> ReactionIntent? {
        switch event.kind {
        case .completionCommitted:
            return completionIntent(for: event, snapshot: snapshot)
        case .skipCommitted:
            return make("rest", event: event)
        case .petTapped:
            if let last = lastPetAt, event.occurredAt.timeIntervalSince(last) * 1000 < Double(CatReactionEngine.petCooldownMs),
               event.occurredAt >= last {
                return nil
            }
            lastPetAt = event.occurredAt
            return make("pet", event: event)
        case .sceneEntered:
            guard !snapshot.greetedToday else { return nil }
            return make("greeting", event: event)
        case .welcomeBack:
            return make("returning", event: event)
        case .nightAmbient:
            return make("doze", event: event)
        case .userRequestedEncouragement:
            return make("cheer", event: event)
        case .completionUndone, .historyCorrected, .sceneLeft, .dayChanged, .modalPresented, .modalDismissed:
            // Undo returns to ambient quietly; history corrections only get save feedback (docs/02 §4).
            return nil
        }
    }

    private mutating func completionIntent(for event: CatEvent, snapshot: ReactionSnapshot) -> ReactionIntent? {
        if !event.isDemo {
            if let threshold = Milestones.newlyReached(distinctDoneDays: snapshot.distinctDoneDays, seen: snapshot.seenMilestones),
               catalog.item(id: "milestone_\(threshold)") != nil {
                let consumesAllDone = snapshot.progress.isAllDone && !snapshot.allDoneShownToday
                return make("milestone_\(threshold)", event: event, marksMilestone: threshold,
                            marksAllDoneDay: consumesAllDone ? snapshot.dayKey : nil)
            }
            if snapshot.progress.isAllDone && !snapshot.allDoneShownToday {
                return make("all_done", event: event, marksAllDoneDay: snapshot.dayKey)
            }
            if snapshot.progress.isAllResolved {
                return make("all_resolved", event: event)
            }
        }
        switch event.category {
        case .water?: return make("complete_water", event: event)
        case .stretch?: return make("complete_stretch", event: event)
        case .read?: return make("complete_read", event: event)
        case .tidy?: return make("complete_tidy", event: event)
        case .custom?, nil: return make("complete_generic", event: event)
        }
    }

    private mutating func make(_ id: String, event: CatEvent, marksMilestone: Int? = nil, marksAllDoneDay: DayKey? = nil) -> ReactionIntent? {
        guard let item = catalog.item(id: id) else { return nil }
        let key = pickMessage(for: item)
        return ReactionIntent(reactionId: item.id, clip: item.clipId, expression: item.clipId.defaultExpression,
                              priority: item.priority, messageKey: key, textDwellMs: item.textDwellMs,
                              marksMilestone: event.isDemo ? nil : marksMilestone,
                              marksAllDoneDay: event.isDemo ? nil : marksAllDoneDay, event: event)
    }

    /// Avoids the last two keys of the same reaction when enough candidates exist.
    private mutating func pickMessage(for item: ReactionCatalog.Item) -> String {
        let recent = recentMessages[item.id] ?? []
        let candidates = item.messageKeys.filter { !recent.contains($0) }
        let pool = candidates.isEmpty ? item.messageKeys : candidates
        let key = pool[Int(rng.next() % UInt64(pool.count))]
        var updated = recent + [key]
        if updated.count > 2 { updated.removeFirst(updated.count - 2) }
        recentMessages[item.id] = updated
        return key
    }
}
