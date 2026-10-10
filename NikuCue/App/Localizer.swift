import Combine
import Foundation
import NikuCueDomain

/// UI-facing string access: resolves the effective language and the cat's display name.
/// All user-visible strings come from the bundled JSON tables (CLAUDE.md).
@MainActor
final class Localizer: ObservableObject {
    let catalog: StringCatalog
    @Published private(set) var languageCode: String
    @Published private(set) var preference: AppLanguage
    @Published private(set) var customNickname: String?

    init(catalog: StringCatalog, preference: AppLanguage = .system, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.catalog = catalog
        self.preference = preference
        self.languageCode = StringCatalog.resolveLanguage(preference: preference, preferredLanguages: preferredLanguages)
    }

    static func loadBundled(bundle: Bundle = .main) throws -> StringCatalog {
        var tables: [String: Data] = [:]
        for lang in StringCatalog.supportedLanguages {
            tables[lang] = try BundledResources.data(named: lang, extension: "json", subdirectory: "Localization", bundle: bundle)
        }
        return try StringCatalog(jsonByLanguage: tables)
    }

    func setPreference(_ p: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) {
        preference = p
        languageCode = StringCatalog.resolveLanguage(preference: p, preferredLanguages: preferredLanguages)
    }

    func setNickname(_ nickname: String?) {
        customNickname = nickname
    }

    /// The cat's name: the custom nickname if set, else the localized default (docs/09 §2).
    var catName: String {
        if let n = customNickname, !n.isEmpty { return n }
        return catalog.string("cat.defaultName", language: languageCode)
    }

    /// Looks up a key; `{catName}` is always available as a placeholder.
    func t(_ key: String, _ args: [String: String] = [:]) -> String {
        var merged = args
        if merged["catName"] == nil { merged["catName"] = catName }
        return catalog.string(key, language: languageCode, args: merged)
    }

    /// Locale for date presentation (Thai Buddhist calendar when the device uses it; stored keys stay Gregorian).
    var locale: Locale {
        switch preference {
        case .system: return Locale.autoupdatingCurrent
        case .th: return Locale(identifier: "th_TH")
        case .en: return Locale(identifier: "en_US")
        case .ja: return Locale(identifier: "ja_JP")
        }
    }
}

/// Locates bundled JSON contracts whether Xcode flattened the folder or kept it (synchronized groups copy
/// files individually, folder references keep the subdirectory).
enum BundledResources {
    enum LoadError: Error { case missing(String) }

    static func url(named name: String, extension ext: String, subdirectory: String?, bundle: Bundle = .main) -> URL? {
        if let sub = subdirectory, let u = bundle.url(forResource: name, withExtension: ext, subdirectory: sub) { return u }
        if let u = bundle.url(forResource: name, withExtension: ext) { return u }
        if let sub = subdirectory, let u = bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources/\(sub)") { return u }
        return nil
    }

    static func data(named name: String, extension ext: String, subdirectory: String?, bundle: Bundle = .main) throws -> Data {
        guard let url = url(named: name, extension: ext, subdirectory: subdirectory, bundle: bundle) else {
            throw LoadError.missing("\(subdirectory ?? "")/\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }
}
