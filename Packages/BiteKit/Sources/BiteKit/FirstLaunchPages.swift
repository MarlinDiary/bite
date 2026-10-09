import Foundation

/// The pages Bite opens with the first time, one to a dot: a welcome, a list to tick off, a plan,
/// and the Markdown shortcuts, so there's something to look at, and the first dots have their
/// colours. The rest are empty, to start on. The widgets show them too, before Bite has written
/// any page, so the gallery shows what Bite opens with (user, 2026-10-09).
///
/// They're in each language Bite speaks, a Markdown file to a page in the language's folder of
/// the resources, and Bite opens with them in its own. Each is written alike for every device: a
/// page goes to the person's others through iCloud, and a word for one device, a tap or a click,
/// turned up on all of them. Each starts with a heading, which names the page wherever a page is
/// named: in widgets, Spotlight and Apple Vision Pro's column of tabs.
public enum FirstLaunchPages {
    /// The pages' files, for the first dots in order.
    static let files = ["welcome", "groceries", "this-week", "formatting"]

    /// The pages in the language Bite is shown in.
    public static let markdown = pages(in: nil)

    /// The pages in every language Bite has them in: another device's Bite may have opened with
    /// them in its own.
    public static let everyLanguage: [[String]] = Bundle.module.localizations.filter { $0 != "Base" }.map { pages(in: $0) }

    static func pages(in language: String?) -> [String] {
        files.map { file in
            let url = language.map { Bundle.module.url(forResource: file, withExtension: "md", subdirectory: nil, localization: $0) }
                ?? Bundle.module.url(forResource: file, withExtension: "md")
            return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        } + Array(repeating: "", count: DotPalette.count - files.count)
    }
}
