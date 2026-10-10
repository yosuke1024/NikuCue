import Foundation

public enum HabitCategory: String, Codable, CaseIterable, Sendable {
    case water, stretch, read, tidy, custom
}

/// Set of ISO weekdays (Monday = 1 … Sunday = 7) stored as a 7-bit mask.
public struct WeekdaySet: Hashable, Codable, Sendable {
    /// Bit `1 << (iso - 1)` is set when the weekday is included.
    public let mask: Int

    public init(mask: Int) {
        self.mask = mask & 0b111_1111
    }

    public init(isoWeekdays: some Sequence<Int>) {
        var m = 0
        for d in isoWeekdays where (1...7).contains(d) {
            m |= 1 << (d - 1)
        }
        self.mask = m
    }

    public static let everyDay = WeekdaySet(mask: 0b111_1111)
    public static let none = WeekdaySet(mask: 0)

    public func contains(isoWeekday: Int) -> Bool {
        guard (1...7).contains(isoWeekday) else { return false }
        return mask & (1 << (isoWeekday - 1)) != 0
    }

    public var isoWeekdays: [Int] { (1...7).filter(contains(isoWeekday:)) }
    public var isEmpty: Bool { mask == 0 }
    public var isEveryDay: Bool { mask == WeekdaySet.everyDay.mask }
    public var count: Int { isoWeekdays.count }

    public func inserting(_ iso: Int) -> WeekdaySet {
        WeekdaySet(isoWeekdays: isoWeekdays + [iso])
    }

    public func removing(_ iso: Int) -> WeekdaySet {
        WeekdaySet(isoWeekdays: isoWeekdays.filter { $0 != iso })
    }

    public func toggling(_ iso: Int) -> WeekdaySet {
        contains(isoWeekday: iso) ? removing(iso) : inserting(iso)
    }
}

public struct Habit: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var category: HabitCategory
    public var sortOrder: Int
    public let createdAtUTC: Date
    /// First day the habit can ever be scheduled. Schedule versions never start before it.
    public let startDayKey: DayKey

    public init(id: UUID = UUID(), name: String, category: HabitCategory, sortOrder: Int,
                createdAtUTC: Date, startDayKey: DayKey) {
        self.id = id
        self.name = name
        self.category = category
        self.sortOrder = sortOrder
        self.createdAtUTC = createdAtUTC
        self.startDayKey = startDayKey
    }
}

/// One version of a habit's schedule. Archive, resume and weekday changes append a version that
/// takes effect from a later day; history is reconstructed from the version in force on each day.
public struct HabitScheduleVersion: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let habitId: UUID
    public var effectiveFromDayKey: DayKey
    public var isActive: Bool
    public var weekdays: WeekdaySet

    public init(id: UUID = UUID(), habitId: UUID, effectiveFromDayKey: DayKey, isActive: Bool, weekdays: WeekdaySet) {
        self.id = id
        self.habitId = habitId
        self.effectiveFromDayKey = effectiveFromDayKey
        self.isActive = isActive
        self.weekdays = weekdays
    }
}

public enum RecordStatus: String, Codable, Sendable {
    case done, skipped
}

public struct HabitDayRecord: Hashable, Codable, Sendable {
    public let habitId: UUID
    public let dayKey: DayKey
    public var status: RecordStatus
    public var recordedAtUTC: Date
    public var timeZoneID: String
    public var revision: Int

    public init(habitId: UUID, dayKey: DayKey, status: RecordStatus, recordedAtUTC: Date, timeZoneID: String, revision: Int) {
        self.habitId = habitId
        self.dayKey = dayKey
        self.status = status
        self.recordedAtUTC = recordedAtUTC
        self.timeZoneID = timeZoneID
        self.revision = revision
    }

    /// Unique key `habitId:dayKey` (docs/06 §3).
    public var recordKey: String { HabitDayRecord.recordKey(habitId: habitId, dayKey: dayKey) }

    public static func recordKey(habitId: UUID, dayKey: DayKey) -> String {
        "\(habitId.uuidString):\(dayKey.string)"
    }
}

/// Display status of one habit on one day.
public enum DayStatus: String, Sendable, Equatable {
    case pending, done, skipped, notScheduled
}

public struct CompanionProfile: Hashable, Codable, Sendable {
    public var nickname: String?          // nil = default localized "Mali"
    public var didCustomizeName: Bool
    public var firstOpenedAtUTC: Date?
    public var lastHomeDayKey: DayKey?
    public var seenMilestones: Set<Int>
    public var allDoneShownDayKeys: Set<DayKey>

    public init(nickname: String? = nil, didCustomizeName: Bool = false, firstOpenedAtUTC: Date? = nil,
                lastHomeDayKey: DayKey? = nil, seenMilestones: Set<Int> = [], allDoneShownDayKeys: Set<DayKey> = []) {
        self.nickname = nickname
        self.didCustomizeName = didCustomizeName
        self.firstOpenedAtUTC = firstOpenedAtUTC
        self.lastHomeDayKey = lastHomeDayKey
        self.seenMilestones = seenMilestones
        self.allDoneShownDayKeys = allDoneShownDayKeys
    }
}

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system, th, en, ja
}

public enum OnboardingStep: String, Codable, Sendable {
    case intro, name, habit, reminder, finished
}

public struct UserPreferences: Hashable, Codable, Sendable {
    public var language: AppLanguage
    public var hapticsEnabled: Bool
    public var reduceMotion: Bool
    public var onboardingStep: OnboardingStep
    public var hasFinishedFirstSession: Bool
    public var diagnosticsEnabled: Bool
    public var remindersEnabled: Bool

    public init(language: AppLanguage = .system, hapticsEnabled: Bool = true, reduceMotion: Bool = false,
                onboardingStep: OnboardingStep = .intro, hasFinishedFirstSession: Bool = false,
                diagnosticsEnabled: Bool = false, remindersEnabled: Bool = false) {
        self.language = language
        self.hapticsEnabled = hapticsEnabled
        self.reduceMotion = reduceMotion
        self.onboardingStep = onboardingStep
        self.hasFinishedFirstSession = hasFinishedFirstSession
        self.diagnosticsEnabled = diagnosticsEnabled
        self.remindersEnabled = remindersEnabled
    }

    public var isOnboardingComplete: Bool { onboardingStep == .finished }
}
