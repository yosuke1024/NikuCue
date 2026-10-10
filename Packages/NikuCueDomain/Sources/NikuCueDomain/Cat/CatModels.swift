import Foundation

/// The eight animation clips (assets-spec/animations.json).
public enum ClipID: String, Codable, CaseIterable, Sendable {
    case idle, greet, pet, celebrate, cheer, settle, doze, milestone
}

/// The five facial expressions (assets-spec/character_spec.json).
public enum Expression: String, Codable, CaseIterable, Sendable {
    case neutral, softSmile, closedHappy, curious, sleepy
}

/// Display-only ambient state decided by time of day and settings (docs/05 §1).
public enum CatAmbientState: String, Sendable, Equatable {
    case idle, dozing
}

/// Room tint by local hour (docs/05 §6). Presentation only, never a judgement of the user's rhythm.
public enum TimeOfDay: String, Sendable, Equatable, CaseIterable {
    case morning, day, night

    public init(hour: Int) {
        switch hour {
        case 5...10: self = .morning
        case 11...18: self = .day
        default: self = .night
        }
    }

    public var ambient: CatAmbientState { self == .night ? .dozing : .idle }
}

public enum CatEventKind: String, Sendable, Equatable {
    case sceneEntered, welcomeBack, sceneLeft, petTapped
    case completionCommitted, completionUndone, skipCommitted, historyCorrected
    case dayChanged, modalPresented, modalDismissed
    case nightAmbient, userRequestedEncouragement
}

/// An event handed to the reaction engine. Habit names are never included (docs/05 §2).
public struct CatEvent: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let kind: CatEventKind
    public let occurredAt: Date
    public let dayKey: DayKey
    public let habitId: UUID?
    public let category: HabitCategory?
    public let revision: Int?
    /// Demo events (onboarding "meet the cat", gallery) never touch statistics, milestones or backups.
    public let isDemo: Bool

    public init(id: UUID = UUID(), kind: CatEventKind, occurredAt: Date, dayKey: DayKey,
                habitId: UUID? = nil, category: HabitCategory? = nil, revision: Int? = nil, isDemo: Bool = false) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.dayKey = dayKey
        self.habitId = habitId
        self.category = category
        self.revision = revision
        self.isDemo = isDemo
    }
}

/// What the engine needs to know about the committed database state when an event arrives.
public struct ReactionSnapshot: Hashable, Sendable {
    public var dayKey: DayKey
    public var progress: DayProgress
    public var distinctDoneDays: Int
    public var seenMilestones: Set<Int>
    public var allDoneShownToday: Bool
    public var greetedToday: Bool

    public init(dayKey: DayKey, progress: DayProgress, distinctDoneDays: Int, seenMilestones: Set<Int>,
                allDoneShownToday: Bool, greetedToday: Bool) {
        self.dayKey = dayKey
        self.progress = progress
        self.distinctDoneDays = distinctDoneDays
        self.seenMilestones = seenMilestones
        self.allDoneShownToday = allDoneShownToday
        self.greetedToday = greetedToday
    }

    /// Snapshot used for demo events: no statistics, nothing to mark.
    public static func demo(dayKey: DayKey) -> ReactionSnapshot {
        ReactionSnapshot(dayKey: dayKey, progress: .empty, distinctDoneDays: 0, seenMilestones: [],
                         allDoneShownToday: true, greetedToday: true)
    }
}

/// The one reaction chosen for an event (docs/05 §4). `CatSceneController` turns it into actions.
public struct ReactionIntent: Hashable, Sendable {
    public let reactionId: String
    public let clip: ClipID
    public let expression: Expression
    public let priority: Int
    public let messageKey: String
    public let textDwellMs: Int
    /// Milestone threshold to record as shown when this reaction actually starts (docs/05 §4).
    public let marksMilestone: Int?
    /// Day whose all-done celebration is consumed when this reaction actually starts.
    public let marksAllDoneDay: DayKey?
    public let event: CatEvent

    public init(reactionId: String, clip: ClipID, expression: Expression, priority: Int, messageKey: String,
                textDwellMs: Int, marksMilestone: Int? = nil, marksAllDoneDay: DayKey? = nil, event: CatEvent) {
        self.reactionId = reactionId
        self.clip = clip
        self.expression = expression
        self.priority = priority
        self.messageKey = messageKey
        self.textDwellMs = textDwellMs
        self.marksMilestone = marksMilestone
        self.marksAllDoneDay = marksAllDoneDay
        self.event = event
    }

    /// Pet and greeting reactions are dropped when the cat is busy instead of being queued (docs/05 §3).
    public var isQueueable: Bool {
        switch clip {
        case .pet, .greet, .cheer, .doze: return false
        case .idle, .celebrate, .settle, .milestone: return true
        }
    }
}

extension ClipID {
    /// Default expression of each clip from animations.json (kept in sync by ReactionCatalogTests).
    public var defaultExpression: Expression {
        switch self {
        case .idle: return .neutral
        case .greet: return .softSmile
        case .pet: return .closedHappy
        case .celebrate: return .closedHappy
        case .cheer: return .curious
        case .settle: return .softSmile
        case .doze: return .sleepy
        case .milestone: return .closedHappy
        }
    }
}
