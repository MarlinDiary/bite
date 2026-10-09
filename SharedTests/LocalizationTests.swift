import Foundation
import Testing

/// Every string Bite shows is in each language it speaks, with the same blanks to fill, and Siri
/// hears its name in each of them. Read from the string catalogs as they are in the project.
struct LocalizationTests {
    nonisolated static let languages = ["zh-Hans", "zh-Hant", "ja", "ko"]
    nonisolated static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    nonisolated static let catalogs = ["Bite", "BiteMac", "BiteVision", "BiteControls", "BiteShare", "BiteMessages", "BiteWatch", "BiteWatchWidgets"]
        .map { "\($0)/Localizable.xcstrings" } + ["Packages/BiteKit/Sources/BiteKit/Resources/Localizable.xcstrings"]
    nonisolated static let shortcuts = ["Bite", "BiteMac", "BiteVision"].map { "\($0)/AppShortcuts.xcstrings" }

    private static func strings(in catalog: String) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: root.appending(path: catalog))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["strings"] as? [String: [String: Any]])
    }

    @Test(arguments: catalogs)
    func everyStringIsInEveryLanguage(catalog: String) throws {
        for (key, entry) in try Self.strings(in: catalog) where entry["shouldTranslate"] as? Bool != false {
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in Self.languages {
                #expect(localizations[language] != nil, "“\(key)” has no \(language)")
            }
        }
    }

    /// A blank the code fills, a page's name or a count, is in every language's words too.
    @Test(arguments: catalogs)
    func translationsKeepTheirBlanks(catalog: String) throws {
        func blanks(_ text: String) -> [String] {
            ["%@", "%lld"].flatMap { blank in Array(repeating: blank, count: text.components(separatedBy: blank).count - 1) }
        }
        for (key, entry) in try Self.strings(in: catalog) {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in Self.languages {
                guard let unit = localizations[language]?["stringUnit"] as? [String: Any], let value = unit["value"] as? String else { continue }
                #expect(blanks(value) == blanks(key), "“\(key)” in \(language): \(value)")
            }
        }
    }

    @Test(arguments: shortcuts)
    func everySiriPhraseNamesBite(catalog: String) throws {
        for (key, entry) in try Self.strings(in: catalog) {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in Self.languages {
                let phrases = (localizations[language]?["stringSet"] as? [String: Any])?["values"] as? [String] ?? []
                #expect(!phrases.isEmpty, "“\(key)” has no \(language) phrases")
                for phrase in phrases {
                    #expect(phrase.contains("${applicationName}"), "\(language): \(phrase)")
                }
            }
        }
    }
}
