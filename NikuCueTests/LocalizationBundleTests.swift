import NikuCueDomain
import XCTest
@testable import NikuCue

/// The app's bundled string tables and reactions must stay complete in all three languages (docs/09 §6).
final class LocalizationBundleTests: XCTestCase {
    func testBundledTablesComplete() throws {
        let catalog = try Localizer.loadBundled()
        for lang in StringCatalog.supportedLanguages {
            XCTAssertEqual(catalog.missingKeys(in: lang), [], lang)
            XCTAssertEqual(catalog.placeholderMismatches(in: lang), [], lang)
        }
        let reactions = try ReactionCatalog.load(from: try BundledResources.data(named: "reactions", extension: "json", subdirectory: "Reactions"))
        XCTAssertEqual(reactions.validate(knownMessageKeys: Set(catalog.tables["en"]!.keys)), [])
    }

    @MainActor
    func testLocalizerResolvesNameAndLanguage() throws {
        let localizer = Localizer(catalog: try Localizer.loadBundled(), preference: .system, preferredLanguages: ["th-TH"])
        XCTAssertEqual(localizer.languageCode, "th")
        XCTAssertEqual(localizer.catName, "มะลิ")
        localizer.setPreference(.ja, preferredLanguages: ["th-TH"])
        XCTAssertEqual(localizer.catName, "マリ")
        localizer.setNickname("Momo")
        XCTAssertEqual(localizer.t("home.petAccessibility"), "Momoをなでる")
        localizer.setPreference(.en)
        XCTAssertEqual(localizer.t("home.petAccessibility"), "Pet Momo", "custom names survive a language switch (Q37)")
    }

    func testConfigurationPlaceholdersAreExplicit() {
        let config = AppConfiguration.development
        XCTAssertFalse(config.isReleaseReady)
        XCTAssertEqual(config.placeholders.count, 6)
    }
}
