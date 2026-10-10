import Foundation

/// One of at most two reminder times (docs/07 §1).
public struct ReminderSlot: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var enabled: Bool
    public var hour: Int      // 0…23 local time
    public var minute: Int    // 0…59
    public var weekdays: WeekdaySet

    public init(id: UUID = UUID(), enabled: Bool, hour: Int, minute: Int, weekdays: WeekdaySet) {
        self.id = id
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
    }

    public var isValid: Bool { (0...23).contains(hour) && (0...59).contains(minute) && !weekdays.isEmpty }
}

/// A single repeating calendar request the notification service should keep registered.
public struct ReminderRequestSpec: Hashable, Sendable {
    public let identifier: String
    public let slotId: UUID
    public let isoWeekday: Int
    public let hour: Int
    public let minute: Int

    /// Apple `Calendar` weekday for `UNCalendarNotificationTrigger` date components.
    public var appleWeekday: Int { CalendarService.appleWeekday(fromISO: isoWeekday) }
}

public enum ReminderPlanner {
    public static let maxSlots = 2
    public static let maxRequests = 14
    public static let identifierPrefix = "nikucue.reminder.v1."

    public static func identifier(slotId: UUID, isoWeekday: Int) -> String {
        "\(identifierPrefix)\(slotId.uuidString).weekday.\(isoWeekday)"
    }

    public static func isOwnIdentifier(_ id: String) -> Bool {
        id.hasPrefix(identifierPrefix)
    }

    /// Desired pending requests: one per enabled slot × weekday, at most 14, stable identifiers.
    public static func requests(for slots: [ReminderSlot], remindersEnabled: Bool = true) -> [ReminderRequestSpec] {
        guard remindersEnabled else { return [] }
        var specs: [ReminderRequestSpec] = []
        for slot in slots.prefix(maxSlots) where slot.enabled && slot.isValid {
            for iso in slot.weekdays.isoWeekdays {
                specs.append(ReminderRequestSpec(identifier: identifier(slotId: slot.id, isoWeekday: iso),
                                                 slotId: slot.id, isoWeekday: iso, hour: slot.hour, minute: slot.minute))
            }
        }
        return Array(specs.prefix(maxRequests))
    }

    /// Two slots with the same time and at least one shared weekday are duplicates (docs/07 §6).
    public static func hasDuplicate(_ slots: [ReminderSlot]) -> Bool {
        guard slots.count >= 2 else { return false }
        for i in 0..<slots.count {
            for j in (i + 1)..<slots.count {
                let a = slots[i], b = slots[j]
                if a.hour == b.hour && a.minute == b.minute && (a.weekdays.mask & b.weekdays.mask) != 0 { return true }
            }
        }
        return false
    }

    /// Differences between what is pending and what should be pending.
    public static func diff(pendingIdentifiers: Set<String>, desired: [ReminderRequestSpec]) -> (toAdd: [ReminderRequestSpec], toRemove: [String]) {
        let desiredIds = Set(desired.map(\.identifier))
        let own = pendingIdentifiers.filter(isOwnIdentifier)
        let toAdd = desired.filter { !own.contains($0.identifier) }
        let toRemove = own.filter { !desiredIds.contains($0) }
        return (toAdd, Array(toRemove).sorted())
    }
}
