import Foundation
import XCTest
@testable import NikuCueDomain

final class StringCatalogTests: XCTestCase {
    func testSubstitutionFallbackAndResolution() {
        let catalog = StringCatalog(tables: [
            "en": ["onboarding.intro": "I'm {catName}.", "only.en": "English only", "home.progress": "Done: {done} of {total}"],
            "ja": ["onboarding.intro": "{catName}だよ。"],
            "th": ["onboarding.intro": "เราชื่อ{catName}"],
        ])
        XCTAssertEqual(catalog.string("onboarding.intro", language: "ja", args: ["catName": "マリ"]), "マリだよ。")
        XCTAssertEqual(catalog.string("onboarding.intro", language: "th", args: ["catName": "มะลิ"]), "เราชื่อมะลิ")
        XCTAssertEqual(catalog.string("only.en", language: "th"), "English only", "falls back to English")
        XCTAssertEqual(catalog.string("missing.key", language: "en"), "missing.key")
        XCTAssertEqual(catalog.string("home.progress", language: "en", args: ["done": "2", "total": "3"]), "Done: 2 of 3")
        XCTAssertEqual(StringCatalog.substitute("{a} {b} {a}", args: ["a": "x"]), "x {b} x")
        XCTAssertEqual(StringCatalog.placeholders(in: "{catName} and {count} {not valid}"), ["catName", "count"])
        XCTAssertEqual(catalog.missingKeys(in: "ja"), ["home.progress", "only.en"])
        XCTAssertEqual(StringCatalog.resolveLanguage(preference: .system, preferredLanguages: ["th-TH", "en"]), "th")
        XCTAssertEqual(StringCatalog.resolveLanguage(preference: .system, preferredLanguages: ["fr-FR", "ja-JP"]), "ja")
        XCTAssertEqual(StringCatalog.resolveLanguage(preference: .system, preferredLanguages: ["fr-FR"]), "en")
        XCTAssertEqual(StringCatalog.resolveLanguage(preference: .ja, preferredLanguages: ["th"]), "ja")
    }

    func testBundledTablesAreCompleteAndConsistent() throws { // Q37
        var tables: [String: Data] = [:]
        for lang in StringCatalog.supportedLanguages {
            tables[lang] = try RepoFiles.data("NikuCue/Resources/Localization/\(lang).json")
        }
        let catalog = try StringCatalog(jsonByLanguage: tables)
        for lang in StringCatalog.supportedLanguages {
            XCTAssertEqual(catalog.missingKeys(in: lang), [], lang)
            XCTAssertEqual(catalog.placeholderMismatches(in: lang), [], lang)
            XCTAssertEqual(catalog.tables[lang]?.count, 169)
            XCTAssertEqual(catalog.string("app.name", language: lang), "NikuCue")
        }
        XCTAssertEqual(catalog.string("cat.defaultName", language: "th"), "มะลิ")
        XCTAssertEqual(catalog.string("cat.defaultName", language: "ja"), "マリ")
        XCTAssertEqual(catalog.string("cat.defaultName", language: "en"), "Mali")
    }
}

final class ReminderPlannerTests: XCTestCase {
    func testAtMostFourteenStableRequests() { // Q18 / Q21
        let a = ReminderSlot(enabled: true, hour: 8, minute: 0, weekdays: .everyDay)
        let b = ReminderSlot(enabled: true, hour: 21, minute: 15, weekdays: .everyDay)
        let specs = ReminderPlanner.requests(for: [a, b])
        XCTAssertEqual(specs.count, 14)
        XCTAssertEqual(Set(specs.map(\.identifier)).count, 14)
        XCTAssertTrue(specs.allSatisfy { ReminderPlanner.isOwnIdentifier($0.identifier) })
        XCTAssertEqual(specs.first?.identifier, "nikucue.reminder.v1.\(a.id.uuidString).weekday.1")
        XCTAssertEqual(specs.first?.appleWeekday, 2)
        // reconciling 20 times against the already-pending set adds and removes nothing
        var pending = Set(specs.map(\.identifier))
        pending.insert("other.app.request")
        for _ in 0..<20 {
            let d = ReminderPlanner.diff(pendingIdentifiers: pending, desired: specs)
            XCTAssertTrue(d.toAdd.isEmpty)
            XCTAssertTrue(d.toRemove.isEmpty)
        }
        // disabling a slot removes exactly its seven requests, foreign identifiers untouched
        var off = b
        off.enabled = false
        let d = ReminderPlanner.diff(pendingIdentifiers: pending, desired: ReminderPlanner.requests(for: [a, off]))
        XCTAssertEqual(d.toRemove.count, 7)
        XCTAssertFalse(d.toRemove.contains("other.app.request"))
        XCTAssertEqual(ReminderPlanner.requests(for: [a, b], remindersEnabled: false).count, 0)
        XCTAssertEqual(ReminderPlanner.requests(for: [a, b, a]).count, 14, "third slot ignored")
    }

    func testDuplicates() {
        let a = ReminderSlot(enabled: true, hour: 8, minute: 0, weekdays: WeekdaySet(isoWeekdays: [1, 2, 3]))
        let b = ReminderSlot(enabled: true, hour: 8, minute: 0, weekdays: WeekdaySet(isoWeekdays: [3, 4]))
        let c = ReminderSlot(enabled: true, hour: 8, minute: 0, weekdays: WeekdaySet(isoWeekdays: [6, 7]))
        XCTAssertTrue(ReminderPlanner.hasDuplicate([a, b]))
        XCTAssertFalse(ReminderPlanner.hasDuplicate([a, c]), "same time on different days is allowed")
        XCTAssertFalse(ReminderPlanner.hasDuplicate([a]))
    }
}

final class AdGateTests: XCTestCase {
    func testAllInputsMustBeTrue() { // Q28 / Q30
        let ok = AdGateInputs(configValid: true, entitlement: .notOwned, onboardingComplete: true, firstRealSessionFinished: true,
                              homeVisible: true, sceneActive: true, canRequestAds: true, sdkPrivacyConfigurationVerified: true)
        XCTAssertTrue(AdGate.adsAllowed(ok))
        var v = ok; v.entitlement = .unknown; XCTAssertFalse(AdGate.adsAllowed(v))
        v = ok; v.entitlement = .owned; XCTAssertFalse(AdGate.adsAllowed(v))
        v = ok; v.canRequestAds = false; XCTAssertFalse(AdGate.adsAllowed(v))
        v = ok; v.firstRealSessionFinished = false; XCTAssertFalse(AdGate.adsAllowed(v))
        v = ok; v.homeVisible = false; XCTAssertFalse(AdGate.adsAllowed(v))
        v = ok; v.sceneActive = false; XCTAssertFalse(AdGate.adsAllowed(v))
        v = ok; v.configValid = false; XCTAssertFalse(AdGate.adsAllowed(v))
        v = ok; v.onboardingComplete = false; XCTAssertFalse(AdGate.adsAllowed(v))
        v = ok; v.sdkPrivacyConfigurationVerified = false; XCTAssertFalse(AdGate.adsAllowed(v))
    }
}

final class BackupValidatorTests: XCTestCase {
    func document() -> BackupDocument {
        let habit = Habit(name: "Water", category: .water, sortOrder: 0, createdAtUTC: Fixtures.date("2026-10-01T00:00:00Z"), startDayKey: Fixtures.day("2026-10-01"))
        let version = HabitScheduleVersion(habitId: habit.id, effectiveFromDayKey: habit.startDayKey, isActive: true, weekdays: .everyDay)
        let record = HabitDayRecord(habitId: habit.id, dayKey: Fixtures.day("2026-10-02"), status: .done, recordedAtUTC: Fixtures.date("2026-10-02T03:00:00Z"), timeZoneID: "Asia/Bangkok", revision: 1)
        return BackupDocument(appVersion: "0.1", exportedAtUTC: Fixtures.date("2026-10-10T00:00:00Z"), habits: [habit], scheduleVersions: [version],
                              records: [record], companion: CompanionProfile(nickname: "มะลิ"), preferences: UserPreferences(),
                              reminderSlots: [ReminderSlot(enabled: true, hour: 8, minute: 0, weekdays: .everyDay)])
    }

    func testValidDocumentRoundTripsAndDisablesReminders() throws {
        let data = try document().encoded()
        let result = BackupValidator.validate(data: data)
        guard case .success(let doc) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(doc.habits.count, 1)
        XCTAssertEqual(doc.reminderSlots.map(\.enabled), [false])
        XCTAssertEqual(doc.companion.nickname, "มะลิ")
    }

    func testRejections() throws { // Q32
        XCTAssertEqual(BackupValidator.validate(data: Data(repeating: 0x20, count: BackupValidator.maxBytes + 1)).failureValue,
                       .tooLarge(bytes: BackupValidator.maxBytes + 1, max: BackupValidator.maxBytes))
        XCTAssertEqual(BackupValidator.validate(data: Data("not json".utf8)).failureValue, .malformedJSON)
        XCTAssertEqual(BackupValidator.validate(data: Data("[]".utf8)).failureValue, .malformedJSON)
        var v2 = document(); v2.schemaVersion = 2
        XCTAssertEqual(BackupValidator.validate(data: try v2.encoded()).failureValue, .unsupportedSchemaVersion(2))

        var json = try JSONSerialization.jsonObject(with: try document().encoded()) as! [String: Any]
        json["adConsent"] = true
        XCTAssertEqual(BackupValidator.validate(data: try JSONSerialization.data(withJSONObject: json)).failureValue, .unexpectedField("adConsent"))

        var dangling = document()
        dangling.records.append(HabitDayRecord(habitId: UUID(), dayKey: Fixtures.day("2026-10-03"), status: .done, recordedAtUTC: Date(timeIntervalSince1970: 0), timeZoneID: "UTC", revision: 1))
        if case .danglingReference(let field, _)? = BackupValidator.validate(data: try dangling.encoded()).failureValue {
            XCTAssertEqual(field, "records.habitId")
        } else { XCTFail("dangling record accepted") }

        var dup = document()
        dup.records.append(dup.records[0])
        if case .duplicate(let field, _)? = BackupValidator.validate(data: try dup.encoded()).failureValue {
            XCTAssertEqual(field, "records.recordKey")
        } else { XCTFail("duplicate record accepted") }

        var badDate = try JSONSerialization.jsonObject(with: try document().encoded()) as! [String: Any]
        var records = badDate["records"] as! [[String: Any]]
        records[0]["dayKey"] = "2569-10-02"
        badDate["records"] = records
        if case .invalidRecord(_, let reason)? = BackupValidator.validate(data: try JSONSerialization.data(withJSONObject: badDate)).failureValue {
            XCTAssertEqual(reason, "day after export", "a Buddhist-era year stored as a key is a future Gregorian date")
        } else { XCTFail("future-dated record accepted") }
        var notADate = try JSONSerialization.jsonObject(with: try document().encoded()) as! [String: Any]
        var recs = notADate["records"] as! [[String: Any]]
        recs[0]["dayKey"] = "10/02/2026"
        notADate["records"] = recs
        XCTAssertEqual(BackupValidator.validate(data: try JSONSerialization.data(withJSONObject: notADate)).failureValue, .malformedJSON)

        var noVersion = document(); noVersion.scheduleVersions = []
        if case .invalidHabit? = BackupValidator.validate(data: try noVersion.encoded()).failureValue {} else { XCTFail("habit without versions accepted") }

        var early = document(); early.scheduleVersions[0].effectiveFromDayKey = Fixtures.day("2026-09-30")
        if case .invalidScheduleVersion? = BackupValidator.validate(data: try early.encoded()).failureValue {} else { XCTFail("version before start accepted") }

        var longName = document(); longName.habits[0].name = String(repeating: "a", count: 41)
        if case .invalidHabit? = BackupValidator.validate(data: try longName.encoded()).failureValue {} else { XCTFail("long name accepted") }

        var threeSlots = document()
        threeSlots.reminderSlots = (0..<3).map { ReminderSlot(enabled: true, hour: $0, minute: 0, weekdays: .everyDay) }
        if case .tooManyItems? = BackupValidator.validate(data: try threeSlots.encoded()).failureValue {} else { XCTFail("three slots accepted") }
    }
}

private extension Result where Success == BackupDocument, Failure == BackupValidationError {
    var failureValue: BackupValidationError? {
        if case .failure(let e) = self { return e }
        return nil
    }
}
