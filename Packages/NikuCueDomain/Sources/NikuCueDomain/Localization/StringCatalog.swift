import Foundation

/// Flat key → string tables for th / en / ja with named placeholders such as `{catName}` (docs/09 §2).
public struct StringCatalog: Sendable {
    public static let fallbackLanguage = "en"
    public static let supportedLanguages = ["th", "en", "ja"]

    public let tables: [String: [String: String]]

    public init(tables: [String: [String: String]]) {
        self.tables = tables
    }

    /// Decodes `{ "key": "value" }` JSON tables keyed by language code.
    public init(jsonByLanguage: [String: Data]) throws {
        var tables: [String: [String: String]] = [:]
        for (lang, data) in jsonByLanguage {
            tables[lang] = try JSONDecoder().decode([String: String].self, from: data)
        }
        self.tables = tables
    }

    /// Resolves the effective language code from the in-app preference and the device's preferred languages.
    public static func resolveLanguage(preference: AppLanguage, preferredLanguages: [String]) -> String {
        switch preference {
        case .th: return "th"
        case .en: return "en"
        case .ja: return "ja"
        case .system:
            for tag in preferredLanguages {
                let code = tag.lowercased().split(separator: "-").first.map(String.init) ?? tag.lowercased()
                if supportedLanguages.contains(code) { return code }
            }
            return fallbackLanguage
        }
    }

    /// Looks up `key` in `language`, falling back to English, then to the key itself.
    public func string(_ key: String, language: String, args: [String: String] = [:]) -> String {
        let raw = tables[language]?[key] ?? tables[StringCatalog.fallbackLanguage]?[key] ?? key
        return StringCatalog.substitute(raw, args: args)
    }

    public func hasKey(_ key: String, language: String) -> Bool {
        tables[language]?[key] != nil
    }

    /// Replaces `{name}` placeholders. Unknown placeholders are left visible so tests can catch them.
    public static func substitute(_ template: String, args: [String: String]) -> String {
        guard template.contains("{") else { return template }
        var out = ""
        var i = template.startIndex
        while i < template.endIndex {
            if template[i] == "{", let close = template[i...].firstIndex(of: "}") {
                let name = String(template[template.index(after: i)..<close])
                if let value = args[name] {
                    out += value
                    i = template.index(after: close)
                    continue
                }
            }
            out.append(template[i])
            i = template.index(after: i)
        }
        return out
    }

    /// Placeholder names used in a template, e.g. `["catName"]`.
    public static func placeholders(in template: String) -> Set<String> {
        var names = Set<String>()
        var i = template.startIndex
        while i < template.endIndex {
            if template[i] == "{", let close = template[i...].firstIndex(of: "}") {
                let name = String(template[template.index(after: i)..<close])
                if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                    names.insert(name)
                }
                i = template.index(after: close)
            } else {
                i = template.index(after: i)
            }
        }
        return names
    }

    /// Keys present in the fallback table but missing from `language`.
    public func missingKeys(in language: String) -> [String] {
        let base = Set(tables[StringCatalog.fallbackLanguage]?.keys.map { $0 } ?? [])
        let have = Set(tables[language]?.keys.map { $0 } ?? [])
        return base.subtracting(have).sorted()
    }

    /// Keys whose placeholder set differs from the fallback language.
    public func placeholderMismatches(in language: String) -> [String] {
        guard let base = tables[StringCatalog.fallbackLanguage], let other = tables[language] else { return [] }
        return base.keys.filter { key in
            guard let o = other[key] else { return false }
            return StringCatalog.placeholders(in: base[key]!) != StringCatalog.placeholders(in: o)
        }.sorted()
    }
}
