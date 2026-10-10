import Foundation

public enum HabitValidationError: Error, Equatable, Sendable {
    case emptyName
    case nameTooLong(max: Int)
    case noWeekdays
    case activeLimitReached(max: Int)
    case emptyNickname
    case nicknameTooLong(max: Int)
}

public enum HabitValidation {
    public static let maxActiveHabits = 5
    public static let nameMaxGraphemes = 40
    public static let nicknameMaxGraphemes = 16
    public static let editableDays = 7 // today + 6 previous days

    /// Trims whitespace/newlines and checks 1…40 extended grapheme clusters (never byte-truncated).
    public static func validateName(_ raw: String) -> Result<String, HabitValidationError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyName) }
        guard trimmed.count <= nameMaxGraphemes else { return .failure(.nameTooLong(max: nameMaxGraphemes)) }
        return .success(trimmed)
    }

    /// Trims and checks 1…16 extended grapheme clusters. Emoji and Thai clusters count as one.
    public static func validateNickname(_ raw: String) -> Result<String, HabitValidationError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyNickname) }
        guard trimmed.count <= nicknameMaxGraphemes else { return .failure(.nicknameTooLong(max: nicknameMaxGraphemes)) }
        return .success(trimmed)
    }

    public static func validateWeekdays(_ set: WeekdaySet) -> Result<WeekdaySet, HabitValidationError> {
        set.isEmpty ? .failure(.noWeekdays) : .success(set)
    }
}
