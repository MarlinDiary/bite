import BiteKit

/// What the dots hold on first launch: Bite's first pages (see `FirstLaunchPages`), but on the
/// watch.
enum SampleContent {
    static func markdown(for dot: Int) -> String {
        #if os(watchOS)
        // The watch's pages come from iCloud, the person's own, a moment after it first opens: its
        // own samples would only show until then.
        ""
        #else
        FirstLaunchPages.markdown.indices.contains(dot) ? FirstLaunchPages.markdown[dot] : ""
        #endif
    }

    /// Whether `markdown` is a dot's first-launch page as it came, in whichever language: the
    /// device that made it may speak another.
    static func isUntouched(_ markdown: String, dot: Int) -> Bool {
        let page = normalized(markdown)
        return FirstLaunchPages.everyLanguage.contains { samples in
            samples.indices.contains(dot) && !samples[dot].isEmpty && normalized(samples[dot]) == page
        }
    }

    private static func normalized(_ markdown: String) -> String {
        MarkdownSerializer.markdown(from: MarkdownParser.parse(markdown))
    }
}
